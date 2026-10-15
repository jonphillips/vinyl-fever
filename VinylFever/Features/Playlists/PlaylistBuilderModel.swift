import Dependencies
import Foundation
import Observation
import VinylFeverCore

@MainActor
@Observable
final class PlaylistBuilderModel {
  @ObservationIgnored @Dependency(\.appleMusicCatalogClient) private var appleMusic
  @ObservationIgnored @Dependency(\.catalogMatchResolver) private var resolver

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
  var createdPlaylist: CreatedPlaylistRef?
  var hasResolvedPaste = false
  var searchTerms: [Int: String] = [:]
  private(set) var removedTrackIndexes: Set<Int> = []
  private(set) var appendedTrackIndexes: Set<Int> = []
  private(set) var createdTrackIndexes: Set<Int> = []

  var visibleRows: [ResolvedPlaylistRow] {
    rows.filter { !removedTrackIndexes.contains($0.request.index) && !appendedTrackIndexes.contains($0.request.index) }
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
  var canCreate: Bool { createdPlaylist == nil && matchedCount > 0 && !isCreating }

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
    hasResolvedPaste = true
  }

  func reSearch(trackIndex: Int) async {
    guard await passGates() else { return }
    guard let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }) else { return }
    let term = (searchTerms[trackIndex] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return }
    operationError = nil
    do {
      let candidates = try await appleMusic.searchSongs(term, CatalogMatchResolver.searchResultLimit)
      switch CatalogMatchScorer.score(rows[rowIndex].request, candidates: candidates) {
      case let .matched(candidate, score): rows[rowIndex].status = .matched(candidate, score: score)
      case let .ambiguous(candidates): rows[rowIndex].status = .ambiguous(candidates)
      case .notFound: rows[rowIndex].status = .notFound(error: nil)
      }
      removeDuplicateIfNeeded(at: rowIndex)
    } catch {
      rows[rowIndex].status = .notFound(error: error.localizedDescription)
      releaseDuplicateRows(of: trackIndex)
    }
  }

  func selectCandidate(_ candidate: CatalogSongCandidate, for trackIndex: Int) {
    guard let rowIndex = rows.firstIndex(where: { $0.request.index == trackIndex }) else { return }
    rows[rowIndex].status = .matched(candidate, score: CatalogMatchScorer.score(rows[rowIndex].request, candidate))
    removeDuplicateIfNeeded(at: rowIndex)
  }

  func remove(trackIndex: Int) {
    removedTrackIndexes.insert(trackIndex)
    releaseDuplicateRows(of: trackIndex)
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
      createdTrackIndexes = Set(visibleRows.compactMap { row in
        if case .matched = row.status { row.request.index } else { nil }
      })
      createdPlaylist = try await appleMusic.createLibraryPlaylist(
        playlistName.trimmingCharacters(in: .whitespacesAndNewlines),
        playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : playlistDescription.trimmingCharacters(in: .whitespacesAndNewlines),
        matched.map(\.id)
      )
    } catch {
      operationError = error.localizedDescription
    }
  }

  func addToCreatedPlaylist(trackIndex: Int) async {
    guard let createdPlaylist,
      let row = visibleRows.first(where: { $0.request.index == trackIndex }),
      case let .matched(candidate, _) = row.status
    else { return }
    operationError = nil
    do {
      try await appleMusic.appendToLibraryPlaylist(createdPlaylist.id, [candidate.id])
      appendedTrackIndexes.insert(trackIndex)
      self.createdPlaylist = CreatedPlaylistRef(
        id: createdPlaylist.id,
        name: createdPlaylist.name,
        trackCount: createdPlaylist.trackCount + 1
      )
    } catch {
      operationError = error.localizedDescription
    }
  }

  func startOver() {
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

  private func removeDuplicateIfNeeded(at rowIndex: Int) {
    guard case let .matched(candidate, _) = rows[rowIndex].status else { return }
    if let first = rows[..<rowIndex].first(where: {
      if case let .matched(existing, _) = $0.status { existing.id == candidate.id } else { false }
    }) {
      rows[rowIndex].status = .duplicate(ofTrackIndex: first.request.index)
    } else {
      releaseDuplicateRows(of: rows[rowIndex].request.index)
    }
  }

  private func releaseDuplicateRows(of trackIndex: Int) {
    for rowIndex in rows.indices {
      if case let .duplicate(ofTrackIndex: duplicateOf) = rows[rowIndex].status,
        duplicateOf == trackIndex {
        rows[rowIndex].status = .notFound(error: "Previously identified as a duplicate. Search again to add this song instead.")
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
