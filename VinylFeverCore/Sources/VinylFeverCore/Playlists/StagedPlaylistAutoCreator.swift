import Dependencies
import Foundation
import VinylFeverAppleMusic
import VinylFeverNotes
import VinylFeverListening

public struct StagedPlaylistRouteClient: Sendable {
  public var read: @Sendable (_ host: String, _ recordedAt: Date) throws -> [RecommendationTrack]?

  public init(read: @escaping @Sendable (String, Date) throws -> [RecommendationTrack]?) {
    self.read = read
  }

  public static let liveValue = Self { host, recordedAt in
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/recommendations", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else { return nil }
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { url -> Data in
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return try coordinatedRead(url)
      }
    let ledger = RecommendationLedgerCodec.readFiles(files)
    let key = PlaylistCreationsCodec.batchKey(host: host, recordedAt: recordedAt)
    return ledger.batches.first {
      $0.kind == "staged-playlist"
        && PlaylistCreationsCodec.batchKey(host: $0.host, recordedAt: $0.recordedAt) == key
    }?.tracks
  }

  private static func coordinatedRead(_ url: URL) throws -> Data {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readError: Error?
    var data: Data?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
      do { data = try Data(contentsOf: target) } catch { readError = error }
    }
    if let coordinationError { throw coordinationError }
    if let readError { throw readError }
    guard let data else { throw CocoaError(.fileReadUnknown) }
    return data
  }
}

extension StagedPlaylistRouteClient: TestDependencyKey, DependencyKey {
  public static let testValue = Self(read: { _, _ in nil })
}

extension DependencyValues {
  public var stagedPlaylistRouteClient: StagedPlaylistRouteClient {
    get { self[StagedPlaylistRouteClient.self] }
    set { self[StagedPlaylistRouteClient.self] = newValue }
  }
}

public struct StagedPlaylistAutoCreator {
  @Dependency(\.playlistInboxClient) private var inbox
  @Dependency(\.playlistCreationClient) private var creations
  @Dependency(\.stagedPlaylistRouteClient) private var routeClient
  @Dependency(\.appleMusicCatalogClient) private var appleMusic
  @Dependency(\.catalogMatchResolver) private var catalogResolver
  @Dependency(\.librarySnapshotStore) private var snapshotStore
  @Dependency(\.continuousClock) private var clock
  @Dependency(\.date.now) private var now

  public init() {}

  public func processInbox() async {
    let items: [StagedPlaylistSummary]
    do { items = try inbox.list() }
    catch {
      NSLog("Vinyl Fever could not read the staged playlist inbox: %@", error.localizedDescription)
      return
    }
    for item in items { await process(item) }
  }

  private func process(_ item: StagedPlaylistSummary) async {
    guard let batchHost = item.batchHost, let recordedAt = item.recordedAt else { return }
    let key = PlaylistCreationsCodec.batchKey(host: batchHost, recordedAt: recordedAt)
    let existing: PlaylistCreationsReadResult
    do { existing = try creations.read() }
    catch {
      NSLog("Vinyl Fever could not check playlist creation history: %@", error.localizedDescription)
      return
    }
    if let event = PlaylistCreationsCodec.latestEvents(existing.events)[key],
      event.kind == .created || event.kind == .dismissed || event.kind == .needsReview { return }

    let decoded: PlaylistDecodeResult
    do { decoded = try PlaylistContract.decode(inbox.read(item.handoff)) }
    catch {
      NSLog("Vinyl Fever could not decode staged playlist %@: %@", item.name, error.localizedDescription)
      return
    }
    guard !decoded.request.tracks.isEmpty else { return }

    let routes: [RecommendationTrack]?
    do { routes = try routeClient.read(batchHost, recordedAt) }
    catch {
      await writeNeedsReview(item, host: batchHost, recordedAt: recordedAt,
        skipped: decoded.request.tracks.map { .init(title: $0.title, artist: $0.artist, reason: "error") },
        error: "The saved upload route could not be read: \(error.localizedDescription)")
      return
    }
    let aliases: [String: String]
    do { aliases = try snapshotStore.readAliases() }
    catch {
      await writeNeedsReview(item, host: batchHost, recordedAt: recordedAt, skipped: [],
        error: "Artist aliases could not be read: \(error.localizedDescription)")
      return
    }
    let identity = ArtistIdentity(aliases: aliases, knownArtists: [])
    let rows = await resolve(decoded.request, routes: routes, identity: identity)
    let skipped = rows.compactMap { row -> PlaylistCreationSkippedSong? in
      let reason: String
      switch row.status {
      case .matched: return nil
      case .ambiguous, .duplicate: reason = "ambiguous"
      case let .notFound(error): reason = error == nil ? "not-found" : "error"
      case let .uploadNotFound(_, isFailure): reason = isFailure ? "error" : "not-found"
      }
      return PlaylistCreationSkippedSong(title: row.request.title, artist: row.request.artist, reason: reason)
    }
    guard skipped.isEmpty else {
      await writeNeedsReview(item, host: batchHost, recordedAt: recordedAt, skipped: skipped)
      return
    }

    do {
      guard await appleMusic.authorizationStatus() == .authorized else {
        throw AutoCreateError.message("Apple Music access is not authorized on this Mac.")
      }
      let subscription = try await appleMusic.subscriptionStatus()
      guard subscription.canPlayCatalogContent, subscription.hasCloudLibraryEnabled else {
        throw AutoCreateError.message("Apple Music subscription and Sync Library are required to create playlists.")
      }
      // iCloud can lag behind a phone Create; repeat the log check immediately before writing to Music.
      let latestLog = try creations.read()
      if let latest = PlaylistCreationsCodec.latestEvents(latestLog.events)[key],
        latest.kind == .created || latest.kind == .dismissed || latest.kind == .needsReview { return }
      let names = try await appleMusic.libraryPlaylistNames()
      guard !names.contains(decoded.request.name) else { return }
      let songs = rows.compactMap { row -> PlaylistSongReference? in
        guard case let .matched(candidate, _) = row.status else { return nil }
        return PlaylistSongReference(id: candidate.id, source: candidate.source)
      }
      let created = try await appleMusic.createLibraryPlaylist(decoded.request.name,
        decoded.request.description, songs)
      try creations.append(PlaylistCreationEvent(kind: .created, host: batchHost,
        recordedAt: recordedAt, playlist: decoded.request.name, at: now,
        writerHost: ListeningStore.liveHostName(), musicID: created.id,
        songs: created.trackCount, skipped: []))
      _ = try inbox.markProcessed(item.handoff)
    } catch {
      await writeNeedsReview(item, host: batchHost, recordedAt: recordedAt, skipped: [],
        error: error.localizedDescription)
    }
  }

  private func resolve(_ request: PlaylistRequest, routes: [RecommendationTrack]?, identity: ArtistIdentity) async -> [ResolvedPlaylistRow] {
    let tracks = request.tracks
    let catalogIndices = Set(tracks.indices.filter { index in
      guard let routes, routes.indices.contains(index) else { return true }
      return routes[index].upload != true
    })
    let catalogRequest = PlaylistRequest(name: request.name, description: request.description,
      tracks: tracks.enumerated().filter { catalogIndices.contains($0.offset) }.map(\.element))
    let catalogRows = catalogRequest.tracks.isEmpty ? [] : await catalogResolver.resolve(catalogRequest, identity)
    var rowsByIndex = Dictionary(uniqueKeysWithValues: catalogRows.map { ($0.request.index, $0) })
    let appleMusic = self.appleMusic
    let clock = self.clock

    for (offset, track) in tracks.enumerated() {
      let uploadRoute = routes?.indices.contains(offset) == true && routes?[offset].upload == true
      guard uploadRoute else { continue }
      let outcome = await LibraryUploadMatcher.match(track, identity: identity, clock: clock,
        searchAlbums: { try await appleMusic.searchLibraryAlbums($0) },
        albumTracks: { try await appleMusic.libraryAlbumTracks($0) },
        searchSongs: { try await appleMusic.searchLibrarySongs($0, $1) })
      rowsByIndex[track.index] = Self.row(track, outcome: outcome)
    }
    // Pre-S3 staged items have no route. Preserve the phone's catalog-first, upload-fallback behavior.
    for (offset, track) in tracks.enumerated() {
      let routeWasNotRecorded = routes?.indices.contains(offset) != true || routes?[offset].upload == nil
      if routeWasNotRecorded, track.album != nil {
        guard case .notFound? = rowsByIndex[track.index]?.status else { continue }
        let outcome = await LibraryUploadMatcher.match(track, identity: identity, clock: clock,
          searchAlbums: { try await appleMusic.searchLibraryAlbums($0) },
          albumTracks: { try await appleMusic.libraryAlbumTracks($0) },
          searchSongs: { try await appleMusic.searchLibrarySongs($0, $1) })
        rowsByIndex[track.index] = Self.row(track, outcome: outcome)
      }
    }
    var firstBySong: [String: Int] = [:]
    return tracks.map { track in
      guard var row = rowsByIndex[track.index] else { return ResolvedPlaylistRow(request: track, status: .notFound(error: nil)) }
      if case let .matched(candidate, _) = row.status {
        let key = "\(candidate.source.rawValue)|\(candidate.id)"
        if let first = firstBySong[key] { row.status = .duplicate(candidate, ofTrackIndex: first) }
        else { firstBySong[key] = track.index }
      }
      return row
    }
  }

  private static func row(_ track: TrackRequest, outcome: LibraryUploadMatcher.Outcome) -> ResolvedPlaylistRow {
    let status: ResolvedPlaylistRow.Status = switch outcome {
    case let .matched(candidate): .matched(candidate, score: 1)
    case let .ambiguous(candidates): .ambiguous(candidates.map { ScoredCandidate(candidate: $0, score: 1) })
    case .notFound: .uploadNotFound(reason: "Apple Music couldn't find this upload.", isFailure: false)
    case let .failed(message): .uploadNotFound(reason: message, isFailure: true)
    }
    return ResolvedPlaylistRow(request: track, status: status)
  }

  private func writeNeedsReview(_ item: StagedPlaylistSummary, host: String, recordedAt: Date,
    skipped: [PlaylistCreationSkippedSong], error: String? = nil) async {
    do {
      try creations.append(PlaylistCreationEvent(kind: .needsReview, host: host,
        recordedAt: recordedAt, playlist: item.name, at: now, writerHost: ListeningStore.liveHostName(),
        skipped: skipped, error: error))
    } catch {
      NSLog("Vinyl Fever could not record why playlist %@ needs review: %@", item.name, error.localizedDescription)
    }
  }
}

private enum AutoCreateError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case let .message(value): value
    }
  }
}
