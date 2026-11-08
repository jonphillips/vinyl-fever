import Dependencies
import DependenciesMacros
import Foundation
import MusicKit
import Observation
import UIKit
import VinylFeverAppleMusic
import VinylFeverNotes

@DependencyClient
struct PlaylistCreateSupportClient {
  var artistIdentity: @Sendable () throws -> ArtistIdentity = { .empty }
  var readCreations: @Sendable () throws -> PlaylistCreationsReadResult = {
    PlaylistCreationsReadResult(events: [], skippedLines: 0, filesRead: 0)
  }
  var appendCreation: @Sendable (PlaylistCreationEvent) throws -> Void
  var deviceName: @Sendable () async -> String = { "iPhone" }
}

extension PlaylistCreateSupportClient: TestDependencyKey {
  static var testValue: Self { Self() }
}

struct PlaylistCreateGate: Equatable {
  var playlistID: String
  var message: String
}

struct PlaylistCreateOutcome: Equatable {
  var playlistID: String
  var message: String?
  var skipped: [PlaylistCreationSkippedSong]
  var recordError: String?
  var error: String?
}

enum PlaylistCreateSupport {
  static func loadArtistIdentity(
    folder: URL,
    startDownload: (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) },
    read: (URL) throws -> Data
  ) throws -> ArtistIdentity {
    let url = folder.appending(path: "Taste Intelligence/artist-aliases.json")
    try? startDownload(url)
    let data: Data
    do { data = try read(url) }
    catch {
      let nsError = error as NSError
      if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.fileNoSuchFile.rawValue {
        return .empty
      }
      throw error
    }
    guard let document = try? JSONDecoder().decode(ArtistAliasesDocument.self, from: data),
      document.format == ArtistAliasesDocument.format,
      document.version <= ArtistAliasesDocument.currentVersion
    else { return .empty }
    return ArtistIdentity(aliases: document.aliases, knownArtists: Set(document.aliases.keys).union(document.aliases.values))
  }
}

enum PlaylistCreateSupportClientKey: DependencyKey {
  typealias Value = PlaylistCreateSupportClient
  static let liveValue = PlaylistCreateSupportClient(
    artistIdentity: {
      try ProbeBookmarkStore.withFolder { folder in
        try PlaylistCreateSupport.loadArtistIdentity(folder: folder, read: TasteFolderReader.coordinatedRead)
      }
    },
    readCreations: {
      try ProbeBookmarkStore.withFolder { folder in
        let result = TasteFolderReader.read(folder: folder, subdirectory: "playlist-creations",
          includes: { $0.hasSuffix(".jsonl") }, missingDirectoryIsUnavailable: false,
          emptyDirectoryIsUnavailable: false)
        return PlaylistCreationsCodec.readFiles(result.files, unreadableFileCount: result.unreadableFileCount)
      }
    },
    appendCreation: { event in
      try ProbeBookmarkStore.withFolder { folder in
        let root = folder.appending(path: "Taste Intelligence/playlist-creations", directoryHint: .isDirectory)
        let writer = event.device ?? "iPhone"
        let safe = writer.unicodeScalars.map {
          CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
        }.joined()
        try JSONLAppend.append(PlaylistCreationsCodec.encode(event),
          to: root.appending(path: "\(safe.isEmpty ? "iPhone" : safe).jsonl"))
      }
    },
    deviceName: { await MainActor.run { UIDevice.current.name } }
  )

}

extension DependencyValues {
  var playlistCreateSupportClient: PlaylistCreateSupportClient {
    get { self[PlaylistCreateSupportClientKey.self] }
    set { self[PlaylistCreateSupportClientKey.self] = newValue }
  }
}

struct PlaylistCreateRow: Equatable, Identifiable {
  var request: TrackRequest
  var status: ResolvedPlaylistRow.Status
  var choice: CatalogSongCandidate?
  var isSkipped = false
  var id: Int { request.index }

  var resolvedCandidate: CatalogSongCandidate? {
    guard !isSkipped else { return nil }
    return switch status {
    case .matched(let candidate, _): candidate
    case .ambiguous: choice
    case .notFound, .uploadNotFound, .duplicate: nil
    }
  }
}

@MainActor
@Observable
final class PlaylistCreateModel {
  enum Destination: Hashable, Identifiable {
    case create
    var id: Self { self }
  }

  private(set) var rows: [PlaylistCreateRow] = []
  private(set) var isResolving = false
  private(set) var isCreating = false
  private(set) var gate: PlaylistCreateGate?
  private(set) var outcome: PlaylistCreateOutcome?
  var destination: Destination?
  private(set) var playlist: PlaylistShelfPlaylist?
  private(set) var playlistName: String?

  @ObservationIgnored @Dependency(\.appleMusicCatalogClient) private var appleMusic
  @ObservationIgnored @Dependency(\.catalogMatchResolver) private var resolver
  @ObservationIgnored @Dependency(\.keepLibraryClient) private var library
  @ObservationIgnored @Dependency(\.playlistCreateSupportClient) private var support
  @ObservationIgnored @Dependency(\.date.now) private var now

  var unresolvedChoiceCount: Int {
    rows.filter { if case .ambiguous = $0.status { return $0.choice == nil && !$0.isSkipped }; return false }.count
  }

  var createButtonTitle: String {
    "Create Playlist · \(rows.filter { duplicateOf($0) == nil }.compactMap(\.resolvedCandidate).count) songs"
  }
  var canCreate: Bool { !isResolving && !isCreating && unresolvedChoiceCount == 0 && !rows.filter { duplicateOf($0) == nil }.compactMap(\.resolvedCandidate).isEmpty }

  func gate(for playlistID: String) -> String? { gate?.playlistID == playlistID ? gate?.message : nil }
  func outcome(for playlistID: String) -> PlaylistCreateOutcome? { outcome?.playlistID == playlistID ? outcome : nil }

  func clearMessages(for playlistID: String) {
    if gate?.playlistID == playlistID { gate = nil }
    if outcome?.playlistID == playlistID { outcome = nil }
  }

  func duplicateOf(_ row: PlaylistCreateRow) -> Int? {
    guard let candidate = row.resolvedCandidate else { return nil }
    return rows.first { earlier in
      earlier.id < row.id && earlier.resolvedCandidate?.id == candidate.id
        && earlier.resolvedCandidate?.source == candidate.source
    }?.id
  }

  func createButtonTapped(_ playlist: PlaylistShelfPlaylist) async {
    guard !isResolving, !isCreating else { return }
    self.playlist = playlist
    playlistName = nil
    rows = []
    gate = nil
    isResolving = true
    defer { isResolving = false }

    var authorization = await appleMusic.authorizationStatus()
    if authorization == .notDetermined { authorization = await appleMusic.requestAuthorization() }
    let granted = authorization == .authorized
    guard granted else { setGate("Allow Apple Music access in Settings to create this playlist.", for: playlist); return }
    let subscription: AppleMusicSubscriptionStatus
    do { subscription = try await appleMusic.subscriptionStatus() }
    catch { setGate(error.localizedDescription, for: playlist); return }
    guard subscription.canPlayCatalogContent else {
      setGate("An Apple Music subscription is needed to create this playlist.", for: playlist); return
    }
    guard subscription.hasCloudLibraryEnabled else {
      setGate("Turn on Sync Library in Settings → Music → Sync Library, then try again.", for: playlist); return
    }
    guard let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      setGate("This staged playlist has no name.", for: playlist); return
    }
    playlistName = name
    let creationEvents: [PlaylistCreationEvent]
    let support = self.support
    do { creationEvents = try await Task.detached { try support.readCreations().events }.value }
    catch { setGate(error.localizedDescription, for: playlist); return }
    let key = PlaylistCreationsCodec.batchKey(host: playlist.batch.host, recordedAt: playlist.batch.recordedAt)
    if let event = PlaylistCreationsCodec.latestEvents(creationEvents)[key], event.kind == .created {
      setGate("Already created on \(event.writerName).", for: playlist); return
    }
    do {
      if try await library.libraryPlaylists().contains(where: { $0.name == name }) {
        setGate("Already in Music", for: playlist); return
      }
    } catch { setGate(error.localizedDescription, for: playlist); return }

    destination = .create
    let isPreS3 = !playlist.batch.tracks.contains { $0.upload != nil }
    let identity = (try? await Task.detached { try support.artistIdentity() }.value) ?? .empty
    await resolve(playlist, identity: identity, isPreS3: isPreS3)
    guard !rows.isEmpty else {
      destination = nil
      setGate("This playlist has no songs to create.", for: playlist)
      return
    }
  }

  func choose(_ candidate: CatalogSongCandidate, for rowID: Int) {
    guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
    rows[index].choice = candidate
    rows[index].isSkipped = false
  }

  func skip(_ rowID: Int) {
    guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
    rows[index].isSkipped = true
    rows[index].choice = nil
  }

  func cancel() { destination = nil; rows = [] }

  func create() async {
    guard canCreate, let playlist, let name = playlistName, !isCreating else { return }
    isCreating = true
    defer { isCreating = false }
    outcome = nil
    do {
      if try await library.libraryPlaylists().contains(where: { $0.name == name }) {
        setOutcome(playlist, error: "Already in Music"); return
      }
    } catch { setOutcome(playlist, error: error.localizedDescription); return }

    let resolved = rows.filter { duplicateOf($0) == nil }.compactMap(\.resolvedCandidate)
    let references = resolved.map { PlaylistSongReference(id: $0.id, source: $0.source) }
    let skipped = skippedSongs()
    do {
      let created = try await appleMusic.createLibraryPlaylist(name, playlist.batch.description, references)
      let recordError = await record(created: created, skipped: skipped)
      outcome = PlaylistCreateOutcome(playlistID: playlist.id,
        message: successText(name, actual: created.trackCount, requested: references.count, skippedCount: skipped.count),
        skipped: skipped, recordError: recordError, error: nil)
      destination = nil
    } catch let partial as CreatedPlaylistPartialError {
      let failed = partial.unaddedSongs.compactMap { reference in
        rows.first(where: { row in row.resolvedCandidate?.id == reference.id })?.request
      }.map { PlaylistCreationSkippedSong(title: $0.title, artist: $0.artist, reason: "not-found") }
      let allSkipped = skipped + failed
      let recordError = await record(created: partial.createdPlaylist, skipped: allSkipped)
      outcome = PlaylistCreateOutcome(playlistID: playlist.id,
        message: successText(name, actual: partial.createdPlaylist.trackCount, requested: references.count,
          skippedCount: allSkipped.count), skipped: allSkipped, recordError: recordError, error: nil)
      destination = nil
    } catch { setOutcome(playlist, error: error.localizedDescription) }
  }

  private func resolve(_ playlist: PlaylistShelfPlaylist, identity: ArtistIdentity, isPreS3: Bool) async {
    let tracks = playlist.batch.tracks.enumerated().map { index, track in
      TrackRequest(index: index, artist: track.artist, title: track.title, album: track.album, year: track.year)
    }
    var resolved = Array<PlaylistCreateRow?>(repeating: nil, count: tracks.count)
    for start in stride(from: 0, to: tracks.count, by: 4) {
      let batch = Array(tracks[start..<min(start + 4, tracks.count)])
      await withTaskGroup(of: PlaylistCreateRow.self) { group in
        for request in batch {
          group.addTask {
            await self.resolve(request, track: playlist.batch.tracks[request.index], identity: identity, isPreS3: isPreS3)
          }
        }
        for await row in group { resolved[row.id] = row }
      }
    }
    rows = resolved.compactMap { $0 }
  }

  private func resolve(_ request: TrackRequest, track: RecommendationTrack, identity: ArtistIdentity, isPreS3: Bool) async -> PlaylistCreateRow {
    if track.upload == true {
      return await uploadRow(request, identity: identity)
    }
    let rows = await resolver.resolve(PlaylistRequest(name: "", tracks: [request]), identity)
    guard let row = rows.first else { return PlaylistCreateRow(request: request, status: .notFound(error: nil), choice: nil) }
    if isPreS3, case .notFound = row.status, track.album != nil {
      return await uploadRow(request, identity: identity)
    }
    return PlaylistCreateRow(request: request, status: row.status, choice: nil)
  }

  private func uploadRow(_ request: TrackRequest, identity: ArtistIdentity) async -> PlaylistCreateRow {
    let result = await LibraryUploadMatcher.match(request, identity: identity,
      searchAlbums: appleMusic.searchLibraryAlbums,
      albumTracks: appleMusic.libraryAlbumTracks,
      searchSongs: appleMusic.searchLibrarySongs)
    switch result {
    case .matched(let candidate): return PlaylistCreateRow(request: request, status: .matched(candidate, score: 1), choice: nil)
    case .ambiguous(let candidates): return PlaylistCreateRow(request: request,
      status: .ambiguous(candidates.map { ScoredCandidate(candidate: $0, score: 1) }), choice: nil)
    case .notFound(let reason): return PlaylistCreateRow(request: request, status: .uploadNotFound(reason: reason, isFailure: false), choice: nil)
    case .failed(let message): return PlaylistCreateRow(request: request, status: .uploadNotFound(reason: message, isFailure: true), choice: nil)
    }
  }

  private func skippedSongs() -> [PlaylistCreationSkippedSong] {
    var skipped: [PlaylistCreationSkippedSong] = []
    for row in rows {
      if row.isSkipped {
        skipped.append(.init(title: row.request.title, artist: row.request.artist, reason: "skipped")); continue
      }
      if let candidate = row.resolvedCandidate {
        let key = "\(candidate.source.rawValue)|\(candidate.id)"
        if rows.prefix(while: { $0.id < row.id }).contains(where: {
          guard let previous = $0.resolvedCandidate else { return false }
          return "\(previous.source.rawValue)|\(previous.id)" == key
        }) {
          skipped.append(.init(title: row.request.title, artist: row.request.artist, reason: "duplicate"))
        }
      } else {
        skipped.append(.init(title: row.request.title, artist: row.request.artist, reason: "not-found"))
      }
    }
    return skipped
  }

  private func record(created: CreatedPlaylistRef, skipped: [PlaylistCreationSkippedSong]) async -> String? {
    guard let playlist else { return nil }
    let device = await support.deviceName()
    let event = PlaylistCreationEvent(kind: .created, host: playlist.batch.host, recordedAt: playlist.batch.recordedAt,
      playlist: playlist.batch.playlist ?? created.name, at: now, device: device, musicID: created.id,
      songs: created.trackCount, skipped: skipped)
    let support = self.support
    do {
      try await Task.detached { try support.appendCreation(event) }.value
      return nil
    } catch {
      return "Created in Music, but the record didn’t save: \(error.localizedDescription). The Mac will still list it in its inbox."
    }
  }

  private func setGate(_ message: String, for playlist: PlaylistShelfPlaylist) {
    gate = PlaylistCreateGate(playlistID: playlist.id, message: message)
  }

  private func setOutcome(_ playlist: PlaylistShelfPlaylist, error: String) {
    outcome = PlaylistCreateOutcome(playlistID: playlist.id, message: nil, skipped: [], recordError: nil, error: error)
  }

  private func successText(_ name: String, actual: Int, requested: Int, skippedCount: Int) -> String {
    if actual < requested { return "Created “\(name)” with \(actual) of \(requested) songs" }
    let songWord = actual == 1 ? "song" : "songs"
    return skippedCount == 0 ? "Created “\(name)” with \(actual) \(songWord)." : "Created “\(name)” with \(actual) \(songWord). \(skippedCount) skipped."
  }
}

private struct ArtistAliasesDocument: Decodable {
  var format: String
  var version: Int
  var aliases: [String: String]
  static let format = "vf-artist-aliases"
  static let currentVersion = 1
}
