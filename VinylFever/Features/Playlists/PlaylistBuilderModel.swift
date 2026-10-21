import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import VinylFeverCore

@MainActor
@Observable
final class PlaylistBuilderModel {
  private static let snapshotStaleInterval: TimeInterval = 6 * 60 * 60
  @ObservationIgnored @Dependency(\.appleMusicCatalogClient) private var appleMusic
  @ObservationIgnored @Dependency(\.catalogMatchResolver) private var resolver
  @ObservationIgnored @Dependency(\.continuousClock) private var clock
  @ObservationIgnored @Dependency(\.musicAppClient) private var musicApp
  @ObservationIgnored @Dependency(\.librarySnapshotStore) private var snapshotStore
  @ObservationIgnored @Dependency(\.playlistInboxClient) private var playlistInbox
  @ObservationIgnored @Dependency(\.date.now) private var now

  var pastedText = ""
  var playlistName = ""
  var playlistDescription = ""
  var rows: [ResolvedPlaylistRow] = []
  var stagedPlaylists: [StagedPlaylistSummary] = []
  private var openedStagedPlaylist: StagedHandoff?
  var droppedTracks: [DroppedPlaylistTrack] = []
  var markerWarning: String?
  var decodeError: String?
  var gate: PlaylistGate?
  var operationError: String?
  var isResolving = false
  var isCreating = false
  var isRetryingSearches = false
  var isRefreshingSnapshot = false
  var librarySnapshot: LibrarySnapshot? {
    didSet {
      let buildID = UUID()
      snapshotIndexBuildID = buildID
      libraryIndex = nil
      guard let librarySnapshot else { return }
      let aliases = (try? snapshotStore.readAliases()) ?? [:]
      currentArtistAliases = aliases
      libraryIndexTask = Task.detached(priority: .userInitiated) { [weak self] in
        let index = LibraryIndex(snapshot: librarySnapshot, aliases: aliases)
        await MainActor.run {
          guard let self, self.snapshotIndexBuildID == buildID else { return }
          self.libraryIndex = index
        }
      }
    }
  }
  private var libraryIndex: LibraryIndex?
  @ObservationIgnored private var currentArtistAliases: [String: String] = [:]
  @ObservationIgnored private var snapshotIndexBuildID = UUID()
  @ObservationIgnored private var libraryIndexTask: Task<Void, Never>?
  var librarySnapshotError: String?
  var createdPlaylist: CreatedPlaylistRef?
  var hasResolvedPaste = false
  var searchTerms: [Int: String] = [:]
  private(set) var removedTrackIndexes: Set<Int> = []
  private(set) var appendedTrackIndexes: Set<Int> = []
  private(set) var createdTrackIndexes: Set<Int> = []
  private(set) var addingTrackIndexes: Set<Int> = []
  private(set) var resolvingTrackIndexes: Set<Int> = []
  private var libraryAlbumHints: [Int: String] = [:]
  private var snapshotPickerTrackIndexes: Set<Int> = []
  @ObservationIgnored private var rowResolutionTokens: [Int: UUID] = [:]

  var visibleRows: [ResolvedPlaylistRow] {
    rows.filter {
      !removedTrackIndexes.contains($0.request.index)
        && !appendedTrackIndexes.contains($0.request.index)
        && (createdPlaylist == nil || !createdTrackIndexes.contains($0.request.index))
    }
  }

  var matchedCount: Int {
    visibleRows.filter { if case .matched = $0.status { true } else { false } }.count
  }

  var unresolvedCount: Int {
    visibleRows.filter {
      switch $0.status {
      case .ambiguous, .notFound, .uploadNotFound: true
      case .matched, .duplicate: false
      }
    }.count
  }
  var consideredTrackCount: Int { matchedCount + unresolvedCount }
  var canCreate: Bool {
    createdPlaylist == nil && matchedCount > 0 && !isCreating && !isRetryingSearches
  }
  var isAppending: Bool { !addingTrackIndexes.isEmpty }
  var failedSearchCount: Int { failedSearchTrackIndexes.count }
  var heavilyPlayedCount: Int {
    visibleRows.filter { row in
      guard case .matched(let candidate, _) = row.status,
        case .inLibrary(let plays, _, _, _) = annotation(for: row.request, candidate: candidate)
      else { return false }
      return plays >= LibrarySnapshot.heavilyPlayedThreshold
    }.count
  }

  func annotation(for request: TrackRequest, candidate: CatalogSongCandidate? = nil)
    -> LibraryAnnotation
  {
    guard let libraryIndex else { return .snapshotUnavailable }
    return libraryIndex.annotation(
      artist: request.artist, title: request.title,
      candidateArtist: candidate?.artistName, candidateTitle: candidate?.title)
  }

  func waitForLibraryIndex() async {
    await libraryIndexTask?.value
  }

  private func refreshArtistAliases() {
    guard let librarySnapshot, let aliases = try? snapshotStore.readAliases(),
      aliases != currentArtistAliases else { return }
    currentArtistAliases = aliases
    let buildID = UUID()
    snapshotIndexBuildID = buildID
    libraryIndex = nil
    libraryIndexTask = Task.detached(priority: .userInitiated) { [weak self] in
      let index = LibraryIndex(snapshot: librarySnapshot, aliases: aliases)
      await MainActor.run {
        guard let self, self.snapshotIndexBuildID == buildID else { return }
        self.libraryIndex = index
      }
    }
  }

  func visibleAnnotation(for row: ResolvedPlaylistRow) -> LibraryAnnotation? {
    switch row.status {
    case .matched(let candidate, _):
      annotation(for: row.request, candidate: candidate)
    case .ambiguous:
      annotation(for: row.request)
    case .notFound, .uploadNotFound, .duplicate:
      nil
    }
  }

  func loadSnapshotAndRefreshIfStale() async {
    do {
      librarySnapshot = try await snapshotStore.read()
      let modifiedAt = try await snapshotStore.modifiedAt()
      if modifiedAt == nil || now.timeIntervalSince(modifiedAt!) >= Self.snapshotStaleInterval {
        await refreshSnapshot(requestingPermission: false)
      }
    } catch { librarySnapshotError = error.localizedDescription }
  }

  func refreshInbox() {
    do { stagedPlaylists = try playlistInbox.list() }
    catch { operationError = error.localizedDescription }
  }

  func openStagedPlaylist(_ summary: StagedPlaylistSummary) async {
    do {
      pastedText = try playlistInbox.read(summary.handoff)
      openedStagedPlaylist = summary.handoff
      await resolve()
    } catch { operationError = error.localizedDescription }
  }

  /// Files the staged playlist under `Processed/` without creating it; nothing is deleted.
  func dismissStagedPlaylist(_ summary: StagedPlaylistSummary) {
    do {
      _ = try playlistInbox.markProcessed(summary.handoff)
      stagedPlaylists = try playlistInbox.list()
    } catch { operationError = error.localizedDescription }
  }

  /// The manual refresh. Unlike the launch refresh, it may show the Automation prompt.
  func refreshLibrarySnapshot() async {
    await refreshSnapshot(requestingPermission: true)
  }

  private func refreshSnapshot(requestingPermission: Bool) async {
    guard !isRefreshingSnapshot else { return }
    isRefreshingSnapshot = true
    librarySnapshotError = nil
    defer { isRefreshingSnapshot = false }
    // Launch only checks, so opening the app never raises a permission dialog.
    let permission =
      requestingPermission
      ? await musicApp.requestAutomationPermission() : await musicApp.automationPermission()
    guard permission == .authorized else {
      librarySnapshotError =
        permission == .notDetermined && !requestingPermission
        ? "Click Refresh Library Snapshot to allow Vinyl Fever to read your Music library."
        : permission.displayMessage
      return
    }
    do {
      let snapshot = try await musicApp.readLibrarySnapshot()
      let aliases = try snapshotStore.readAliases()
      try await snapshotStore.writeAliases(aliases)
      try await snapshotStore.write(snapshot)
      librarySnapshot = snapshot
    } catch { librarySnapshotError = error.localizedDescription }
  }

  func removeHeavilyPlayedRows() {
    let indexes = visibleRows.compactMap { row -> Int? in
      guard case .matched(let candidate, _) = row.status,
        case .inLibrary(let plays, _, _, _) = annotation(for: row.request, candidate: candidate),
        plays >= LibrarySnapshot.heavilyPlayedThreshold
      else { return nil }
      return row.request.index
    }
    removedTrackIndexes.formUnion(indexes)
    reconcileDuplicates()
  }

  private var failedSearchTrackIndexes: [Int] {
    visibleRows.compactMap { row in
      switch row.status {
      case .notFound(error: .some): row.request.index
      case .uploadNotFound(_, isFailure: true): row.request.index
      default: nil
      }
    }
  }

  func resolve() async {
    decodeError = nil
    operationError = nil
    gate = nil
    let decoded: PlaylistDecodeResult
    do {
      decoded = try PlaylistContract.decode(pastedText)
    } catch {
      decodeError = error.localizedDescription
      return
    }
    guard await passGates() else { return }

    isResolving = true
    defer { isResolving = false }
    playlistName = decoded.request.name
    playlistDescription = decoded.request.description ?? ""
    droppedTracks = decoded.droppedTracks
    markerWarning = decoded.warning
    removedTrackIndexes = []
    appendedTrackIndexes = []
    createdTrackIndexes = []
    libraryAlbumHints = [:]
    snapshotPickerTrackIndexes = []
    resolvingTrackIndexes = []
    rowResolutionTokens = [:]
    searchTerms = Dictionary(
      uniqueKeysWithValues: decoded.request.tracks.map {
        ($0.index, "\($0.artist) \($0.title)")
      })
    refreshArtistAliases()
    await libraryIndexTask?.value
    let libraryRequests = decoded.request.tracks.filter {
      libraryIndex?.shouldUseLibraryRoute($0) == true
    }
    let libraryIndexes = Set(libraryRequests.map(\.index))
    libraryAlbumHints = Dictionary(uniqueKeysWithValues: libraryRequests.compactMap { request in
      guard let album = request.album, !album.isEmpty else { return nil }
      return (request.index, album)
    })
    let catalogRequest = PlaylistRequest(
      name: decoded.request.name, description: decoded.request.description,
      tracks: decoded.request.tracks.filter { !libraryIndexes.contains($0.index) })
    let catalogRows: [ResolvedPlaylistRow]
    if catalogRequest.tracks.isEmpty {
      catalogRows = []
    } else {
      catalogRows = await resolver.resolve(catalogRequest, libraryIndex?.artistIdentity ?? .empty)
    }
    let catalogRowsByIndex = Dictionary(
      uniqueKeysWithValues: catalogRows.map { ($0.request.index, $0) })
    rows = decoded.request.tracks.map { request in
      catalogRowsByIndex[request.index]
        ?? ResolvedPlaylistRow(request: request, status: .notFound(error: nil))
    }
    for index in rows.indices {
      let request = rows[index].request
      if libraryIndexes.contains(request.index) {
        rows[index].status = await resolveLibrary(request)
      } else if case .notFound = rows[index].status {
        let uploads = libraryIndex?.uploadedCandidates(request) ?? []
        if !uploads.isEmpty {
          snapshotPickerTrackIndexes.insert(request.index)
          rows[index].status = .ambiguous(uploads.map { ScoredCandidate(candidate: $0, score: 1) })
        }
      }
    }
    reconcileDuplicates()
    hasResolvedPaste = true
  }

  func reSearch(trackIndex: Int) async {
    guard !isCreating else { return }
    guard await passGates() else { return }
    guard !isCreating else { return }
    operationError = nil
    await search(trackIndex: trackIndex)
  }

  /// Searches again, one row at a time, for every row whose search failed (for example, because
  /// Apple Music rate-limited the bulk resolve).
  func retryFailedSearches() async {
    guard !isCreating, !isRetryingSearches else { return }
    isRetryingSearches = true
    defer { isRetryingSearches = false }
    guard await passGates() else { return }
    operationError = nil
    for trackIndex in failedSearchTrackIndexes {
      guard !isCreating else { return }
      await search(trackIndex: trackIndex)
    }
  }

  func selectCandidate(_ candidate: CatalogSongCandidate, for trackIndex: Int) async {
    guard !isCreating, !resolvingTrackIndexes.contains(trackIndex) else { return }
    guard let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }) else { return }
    if candidate.source == .libraryUpload, snapshotPickerTrackIndexes.contains(trackIndex) {
      let request = rows[rowIndex].request
      let token = UUID()
      rowResolutionTokens[trackIndex] = token
      resolvingTrackIndexes.insert(trackIndex)
      if let album = candidate.albumTitle, !album.isEmpty {
        libraryAlbumHints[trackIndex] = album
      }
      let status = await resolveLibrary(request, albumHint: libraryAlbumHints[trackIndex])
      defer {
        if rowResolutionTokens[trackIndex] == token {
          rowResolutionTokens.removeValue(forKey: trackIndex)
          resolvingTrackIndexes.remove(trackIndex)
        }
      }
      guard rowResolutionTokens[trackIndex] == token,
        !removedTrackIndexes.contains(trackIndex),
        let currentRowIndex = rows.firstIndex(where: { $0.request.index == trackIndex })
      else { return }
      rows[currentRowIndex].status = status
      snapshotPickerTrackIndexes.remove(trackIndex)
    } else {
      rows[rowIndex].status = .matched(
        candidate, score: CatalogMatchScorer.score(
          rows[rowIndex].request, candidate, identity: libraryIndex?.artistIdentity ?? .empty))
      snapshotPickerTrackIndexes.remove(trackIndex)
      libraryAlbumHints.removeValue(forKey: trackIndex)
    }
    reconcileDuplicates()
  }

  func reopen(trackIndex: Int) {
    guard !isCreating, !createdTrackIndexes.contains(trackIndex),
      !appendedTrackIndexes.contains(trackIndex),
      let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }),
      case .matched = rows[rowIndex].status
    else { return }
    rows[rowIndex].status = .notFound(error: nil)
    libraryAlbumHints.removeValue(forKey: trackIndex)
    snapshotPickerTrackIndexes.remove(trackIndex)
    reconcileDuplicates()
  }

  func canReopenMatch(trackIndex: Int) -> Bool {
    guard !createdTrackIndexes.contains(trackIndex),
      !appendedTrackIndexes.contains(trackIndex),
      !removedTrackIndexes.contains(trackIndex),
      let row = rows.first(where: { $0.request.index == trackIndex })
    else { return false }
    if case .matched = row.status { return true }
    return false
  }

  func remove(trackIndex: Int) {
    guard !isCreating else { return }
    removedTrackIndexes.insert(trackIndex)
    rowResolutionTokens.removeValue(forKey: trackIndex)
    resolvingTrackIndexes.remove(trackIndex)
    libraryAlbumHints.removeValue(forKey: trackIndex)
    snapshotPickerTrackIndexes.remove(trackIndex)
    reconcileDuplicates()
  }

  func isResolvingCandidate(trackIndex: Int) -> Bool {
    resolvingTrackIndexes.contains(trackIndex)
  }

  func createPlaylist() async {
    guard canCreate else { return }
    isCreating = true
    operationError = nil
    defer { isCreating = false }
    let matched = visibleRows.compactMap { row -> PlaylistSongReference? in
      if case .matched(let candidate, _) = row.status {
        PlaylistSongReference(id: candidate.id, source: candidate.source)
      } else {
        nil
      }
    }
    do {
      let trackIndexes = Set(
        visibleRows.compactMap { row in
          if case .matched = row.status { row.request.index } else { nil }
        })
      let playlist = try await appleMusic.createLibraryPlaylist(
        playlistName.trimmingCharacters(in: .whitespacesAndNewlines),
        playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines),
        matched
      )
      createdTrackIndexes = trackIndexes
      createdPlaylist = playlist
      if let openedStagedPlaylist {
        do {
          _ = try playlistInbox.markProcessed(openedStagedPlaylist)
        } catch {
          self.openedStagedPlaylist = nil
          operationError = "Playlist created, but the inbox item couldn't be moved to Processed: \(error.localizedDescription)"
          return
        }
        self.openedStagedPlaylist = nil
        do {
          stagedPlaylists = try playlistInbox.list()
        } catch {
          operationError = "Playlist created and the inbox item moved to Processed, but the inbox list couldn't be refreshed: \(error.localizedDescription)"
        }
      }
    } catch {
      operationError = error.localizedDescription
    }
  }

  func addToCreatedPlaylist(trackIndex: Int) async {
    guard canAddToCreatedPlaylist(trackIndex: trackIndex),
      let createdPlaylist,
      let row = rows.first(where: { $0.request.index == trackIndex }),
      case .matched(let candidate, _) = row.status
    else { return }
    addingTrackIndexes.insert(trackIndex)
    defer { addingTrackIndexes.remove(trackIndex) }
    operationError = nil
    do {
      try await appleMusic.appendToLibraryPlaylist(
        createdPlaylist.id,
        [PlaylistSongReference(id: candidate.id, source: candidate.source)])
      guard let currentPlaylist = self.createdPlaylist, currentPlaylist.id == createdPlaylist.id
      else { return }
      appendedTrackIndexes.insert(trackIndex)
      self.createdPlaylist = CreatedPlaylistRef(
        id: currentPlaylist.id,
        name: currentPlaylist.name,
        trackCount: currentPlaylist.trackCount + 1
      )
    } catch {
      operationError = error.localizedDescription
    }
    reconcileDuplicates()
  }

  func canAddToCreatedPlaylist(trackIndex: Int) -> Bool {
    guard createdPlaylist != nil,
      !createdTrackIndexes.contains(trackIndex),
      !appendedTrackIndexes.contains(trackIndex),
      !removedTrackIndexes.contains(trackIndex),
      !addingTrackIndexes.contains(trackIndex),
      let row = rows.first(where: { $0.request.index == trackIndex })
    else { return false }
    if case .matched = row.status { return true }
    return false
  }

  func startOver() {
    guard !isCreating, !isAppending else { return }
    pastedText = ""
    openedStagedPlaylist = nil
    playlistName = ""
    playlistDescription = ""
    rows = []
    droppedTracks = []
    markerWarning = nil
    decodeError = nil
    operationError = nil
    gate = nil
    createdPlaylist = nil
    hasResolvedPaste = false
    searchTerms = [:]
    removedTrackIndexes = []
    appendedTrackIndexes = []
    createdTrackIndexes = []
    addingTrackIndexes = []
    resolvingTrackIndexes = []
    libraryAlbumHints = [:]
    snapshotPickerTrackIndexes = []
    rowResolutionTokens = [:]
  }

  private func search(trackIndex: Int) async {
    guard let request = rows.first(where: { $0.request.index == trackIndex })?.request else {
      return
    }
    guard !resolvingTrackIndexes.contains(trackIndex) else { return }
    let token = UUID()
    rowResolutionTokens[trackIndex] = token
    resolvingTrackIndexes.insert(trackIndex)
    defer {
      if rowResolutionTokens[trackIndex] == token {
        rowResolutionTokens.removeValue(forKey: trackIndex)
        resolvingTrackIndexes.remove(trackIndex)
      }
    }
    let status: ResolvedPlaylistRow.Status
    if let albumHint = libraryAlbumHints[trackIndex] {
      status = await resolveLibrary(request, albumHint: albumHint)
    } else {
      let term = (searchTerms[trackIndex] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !term.isEmpty else { return }
      let client = appleMusic
      do {
        let candidates = try await CatalogMatchResolver.search(term, clock: clock) {
          try await client.searchSongs($0, CatalogMatchResolver.searchResultLimit)
        }
        status =
          switch CatalogMatchScorer.score(
            request, candidates: candidates, identity: libraryIndex?.artistIdentity ?? .empty) {
          case .matched(let candidate, let score): .matched(candidate, score: score)
          case .ambiguous(let candidates): .ambiguous(candidates)
          case .notFound: .notFound(error: nil)
          }
      } catch {
        status = .notFound(error: error.localizedDescription)
      }
    }
    guard rowResolutionTokens[trackIndex] == token,
      !removedTrackIndexes.contains(trackIndex),
      let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex })
    else { return }
    rows[rowIndex].status = status
    reconcileDuplicates()
  }

  private func resolveLibrary(
    _ request: TrackRequest, albumHint: String? = nil
  ) async -> ResolvedPlaylistRow.Status {
    let client = appleMusic
    let result = await LibraryUploadMatcher.match(
      request, albumHint: albumHint, identity: libraryIndex?.artistIdentity ?? .empty, clock: clock,
      searchAlbums: { try await client.searchLibraryAlbums($0) },
      albumTracks: { try await client.libraryAlbumTracks($0) },
      searchSongs: { try await client.searchLibrarySongs($0, $1) }
    )
    let status: ResolvedPlaylistRow.Status = switch result {
    case let .matched(candidate): .matched(candidate, score: 1)
    case let .ambiguous(candidates):
      .ambiguous(candidates.map { ScoredCandidate(candidate: $0, score: 1) })
    case let .notFound(reason): .uploadNotFound(reason: reason, isFailure: false)
    case let .failed(reason): .uploadNotFound(reason: reason, isFailure: true)
    }
    return status
  }

  private func passGates() async -> Bool {
    let status = await appleMusic.authorizationStatus()
    let authorized = status == .authorized ? status : await appleMusic.requestAuthorization()
    guard authorized == .authorized else {
      gate = .notAuthorized
      return false
    }
    do {
      let subscription = try await appleMusic.subscriptionStatus()
      guard subscription.canPlayCatalogContent else {
        gate = .noSubscription
        return false
      }
      guard subscription.hasCloudLibraryEnabled else {
        gate = .cloudLibraryOff
        return false
      }
      gate = nil
      return true
    } catch {
      gate = .checkFailed(error.localizedDescription)
      return false
    }
  }

  private func reconcileDuplicates() {
    var firstRowByCatalogID: [String: Int] = [:]
    let persistedTrackIndexes = createdTrackIndexes.union(appendedTrackIndexes)

    for rowIndex in rows.indices {
      let row = rows[rowIndex]
      guard persistedTrackIndexes.contains(row.request.index) else { continue }
      let candidate: CatalogSongCandidate
      switch row.status {
      case .matched(let value, _), .duplicate(let value, _):
        candidate = value
      case .ambiguous, .notFound, .uploadNotFound:
        continue
      }
      let key = "\(candidate.source.rawValue)|\(candidate.id)"
      if firstRowByCatalogID[key] == nil {
        firstRowByCatalogID[key] = row.request.index
      }
      rows[rowIndex].status = .matched(
        candidate,
        score: CatalogMatchScorer.score(
          row.request, candidate, identity: libraryIndex?.artistIdentity ?? .empty)
      )
    }

    for rowIndex in rows.indices {
      let row = rows[rowIndex]
      guard !removedTrackIndexes.contains(row.request.index),
        !persistedTrackIndexes.contains(row.request.index)
      else { continue }
      let candidate: CatalogSongCandidate
      switch row.status {
      case .matched(let value, _), .duplicate(let value, _):
        candidate = value
      case .ambiguous, .notFound, .uploadNotFound:
        continue
      }
      let key = "\(candidate.source.rawValue)|\(candidate.id)"
      if let firstTrackIndex = firstRowByCatalogID[key] {
        rows[rowIndex].status = .duplicate(candidate, ofTrackIndex: firstTrackIndex)
      } else {
        firstRowByCatalogID[key] = row.request.index
        rows[rowIndex].status = .matched(
          candidate,
          score: CatalogMatchScorer.score(
            row.request, candidate, identity: libraryIndex?.artistIdentity ?? .empty)
        )
      }
    }
  }
}

enum PlaylistGate: Equatable {
  case notAuthorized
  case noSubscription
  case cloudLibraryOff
  case checkFailed(String)

  var message: String {
    switch self {
    case .notAuthorized:
      "Vinyl Fever needs Apple Music access. Allow it in System Settings → Privacy & Security → Media & Apple Music, then try again."
    case .noSubscription:
      "An Apple Music subscription is required to search the catalog and create this playlist."
    case .cloudLibraryOff:
      "Turn on Sync Library in Music → Settings → General so the playlist can be added to your library."
    case .checkFailed(let message):
      "Could not check Apple Music access: \(message)"
    }
  }
}
