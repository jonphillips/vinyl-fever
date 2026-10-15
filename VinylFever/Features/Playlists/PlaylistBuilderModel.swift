import Dependencies
import Foundation
import Observation
import VinylFeverCore

@MainActor
@Observable
final class PlaylistBuilderModel {
  @ObservationIgnored @Dependency(\.appleMusicCatalogClient) private var appleMusic
  @ObservationIgnored @Dependency(\.catalogMatchResolver) private var resolver
  @ObservationIgnored @Dependency(\.continuousClock) private var clock

  var pastedText = ""
  var playlistName = ""
  var playlistDescription = ""
  var rows: [ResolvedPlaylistRow] = []
  var droppedTracks: [DroppedPlaylistTrack] = []
  var markerWarning: String?
  var decodeError: String?
  var gate: PlaylistGate?
  var operationError: String?
  var isResolving = false
  var isCreating = false
  var isRetryingSearches = false
  var createdPlaylist: CreatedPlaylistRef?
  var hasResolvedPaste = false
  var searchTerms: [Int: String] = [:]
  private(set) var removedTrackIndexes: Set<Int> = []
  private(set) var appendedTrackIndexes: Set<Int> = []
  private(set) var createdTrackIndexes: Set<Int> = []
  private(set) var addingTrackIndexes: Set<Int> = []

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
      case .ambiguous, .notFound: true
      case .matched, .duplicate: false
      }
    }.count
  }
  var consideredTrackCount: Int { matchedCount + unresolvedCount }
  var canCreate: Bool { createdPlaylist == nil && matchedCount > 0 && !isCreating && !isRetryingSearches }
  var isAppending: Bool { !addingTrackIndexes.isEmpty }
  var failedSearchCount: Int { failedSearchTrackIndexes.count }

  private var failedSearchTrackIndexes: [Int] {
    visibleRows.compactMap { row in
      if case .notFound(error: .some) = row.status { row.request.index } else { nil }
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
    searchTerms = Dictionary(uniqueKeysWithValues: decoded.request.tracks.map {
      ($0.index, "\($0.artist) \($0.title)")
    })
    rows = await resolver.resolve(decoded.request)
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

  func selectCandidate(_ candidate: CatalogSongCandidate, for trackIndex: Int) {
    guard !isCreating else { return }
    guard let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }) else { return }
    rows[rowIndex].status = .matched(candidate, score: CatalogMatchScorer.score(rows[rowIndex].request, candidate))
    reconcileDuplicates()
  }

  func reopen(trackIndex: Int) {
    guard !isCreating, !createdTrackIndexes.contains(trackIndex), !appendedTrackIndexes.contains(trackIndex),
      let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }),
      case .matched = rows[rowIndex].status
    else { return }
    rows[rowIndex].status = .notFound(error: nil)
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
    reconcileDuplicates()
  }

  func createPlaylist() async {
    guard canCreate else { return }
    isCreating = true
    operationError = nil
    defer { isCreating = false }
    let matched = visibleRows.compactMap { row -> CatalogSongCandidate? in
      if case let .matched(candidate, _) = row.status { candidate } else { nil }
    }
    do {
      let trackIndexes = Set(visibleRows.compactMap { row in
        if case .matched = row.status { row.request.index } else { nil }
      })
      let playlist = try await appleMusic.createLibraryPlaylist(
        playlistName.trimmingCharacters(in: .whitespacesAndNewlines),
        playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines),
        matched.map(\.id)
      )
      createdTrackIndexes = trackIndexes
      createdPlaylist = playlist
    } catch {
      operationError = error.localizedDescription
    }
  }

  func addToCreatedPlaylist(trackIndex: Int) async {
    guard canAddToCreatedPlaylist(trackIndex: trackIndex),
      let createdPlaylist,
      let row = rows.first(where: { $0.request.index == trackIndex }),
      case let .matched(candidate, _) = row.status
    else { return }
    addingTrackIndexes.insert(trackIndex)
    defer { addingTrackIndexes.remove(trackIndex) }
    operationError = nil
    do {
      try await appleMusic.appendToLibraryPlaylist(createdPlaylist.id, [candidate.id])
      guard let currentPlaylist = self.createdPlaylist, currentPlaylist.id == createdPlaylist.id else { return }
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
  }

  private func search(trackIndex: Int) async {
    guard let request = rows.first(where: { $0.request.index == trackIndex })?.request else { return }
    let term = (searchTerms[trackIndex] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return }
    let client = appleMusic
    let status: ResolvedPlaylistRow.Status
    do {
      let candidates = try await CatalogMatchResolver.search(term, clock: clock) {
        try await client.searchSongs($0, CatalogMatchResolver.searchResultLimit)
      }
      status = switch CatalogMatchScorer.score(request, candidates: candidates) {
      case let .matched(candidate, score): .matched(candidate, score: score)
      case let .ambiguous(candidates): .ambiguous(candidates)
      case .notFound: .notFound(error: nil)
      }
    } catch {
      status = .notFound(error: error.localizedDescription)
    }
    // Look the row up again: the table can change while the search is in flight.
    guard let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }) else { return }
    rows[rowIndex].status = status
    reconcileDuplicates()
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
      case let .matched(value, _), let .duplicate(value, _):
        candidate = value
      case .ambiguous, .notFound:
        continue
      }
      if firstRowByCatalogID[candidate.id] == nil {
        firstRowByCatalogID[candidate.id] = row.request.index
      }
      rows[rowIndex].status = .matched(
        candidate,
        score: CatalogMatchScorer.score(row.request, candidate)
      )
    }

    for rowIndex in rows.indices {
      let row = rows[rowIndex]
      guard !removedTrackIndexes.contains(row.request.index),
        !persistedTrackIndexes.contains(row.request.index)
      else { continue }
      let candidate: CatalogSongCandidate
      switch row.status {
      case let .matched(value, _), let .duplicate(value, _):
        candidate = value
      case .ambiguous, .notFound:
        continue
      }
      if let firstTrackIndex = firstRowByCatalogID[candidate.id] {
        rows[rowIndex].status = .duplicate(candidate, ofTrackIndex: firstTrackIndex)
      } else {
        firstRowByCatalogID[candidate.id] = row.request.index
        rows[rowIndex].status = .matched(
          candidate,
          score: CatalogMatchScorer.score(row.request, candidate)
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
    case let .checkFailed(message):
      "Could not check Apple Music access: \(message)"
    }
  }
}
