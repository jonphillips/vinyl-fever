import Dependencies
import DependenciesMacros
import Foundation
import Observation
import VinylFeverNotes

enum PlaylistShelfSegment: String, CaseIterable, Equatable, Identifiable {
  case active
  case archived

  var id: Self { self }
}

@DependencyClient
struct PlaylistShelfClient {
  var read: @Sendable () async throws -> RecommendationLedgerFolderRead
}

extension PlaylistShelfClient: TestDependencyKey {
  static var testValue: Self { Self() }
}

private enum PlaylistShelfClientKey: DependencyKey {
  static let liveValue = PlaylistShelfClient {
    try await Task.detached {
      try ProbeBookmarkStore.withFolder { folder in
        RecommendationLedgerFolderReader.read(folder: folder)
      }
    }.value
  }
}

extension DependencyValues {
  var playlistShelfClient: PlaylistShelfClient {
    get { self[PlaylistShelfClientKey.self] }
    set { self[PlaylistShelfClientKey.self] = newValue }
  }
}

@MainActor
@Observable
final class PlaylistShelfModel {
  enum Destination: Hashable, Identifiable {
    case setup
    var id: Self { self }
  }

  private(set) var playlists: [PlaylistShelfPlaylist] = []
  private(set) var hasUnreadableFiles = false
  private(set) var isLoading = false
  private(set) var requiresFolderAccess = false
  private(set) var libraryPlaylists: [KeepLibraryPlaylist]?
  private(set) var selectedSegment: PlaylistShelfSegment = .active
  var selectedPlaylistID: String?
  var destination: Destination?

  @ObservationIgnored
  @Dependency(\.playlistShelfClient) private var client
  @ObservationIgnored
  @Dependency(\.keepLibraryClient) private var keepClient
  @ObservationIgnored
  @Dependency(\.date.now) private var now

  private var libraryPlaylistNames: [String]? {
    guard let libraryPlaylists else { return nil }
    return libraryPlaylists.map(\.name)
  }

  private var archivedPlaylistIDs: Set<String> {
    PlaylistArchive.archivedPlaylistIDs(from: playlists, libraryPlaylistNames: libraryPlaylistNames, now: now)
  }

  var displayedPlaylists: [PlaylistShelfPlaylist] {
    playlists(in: selectedSegment)
  }

  /// The empty segment's message, only once the ledger has been read with folder access.
  var emptyMessage: String? {
    guard !isLoading, !requiresFolderAccess, displayedPlaylists.isEmpty else { return nil }
    switch selectedSegment {
    case .archived: return "Playlists you delete in Music move here."
    case .active where !playlists.isEmpty: return "No active playlists. Ask the chat for a new one."
    case .active: return "No Vinyl Fever playlists yet. Ask the chat for some."
    }
  }

  func playlists(in segment: PlaylistShelfSegment) -> [PlaylistShelfPlaylist] {
    let archivedIDs = archivedPlaylistIDs
    return playlists.filter { archivedIDs.contains($0.id) == (segment == .archived) }
  }

  func count(in segment: PlaylistShelfSegment) -> Int {
    playlists(in: segment).count
  }

  func isArchived(_ playlist: PlaylistShelfPlaylist) -> Bool {
    archivedPlaylistIDs.contains(playlist.id)
  }

  func archiveStatusText(for playlist: PlaylistShelfPlaylist) -> String? {
    isArchived(playlist) ? "No longer in your Music library." : nil
  }

  func selectSegment(_ segment: PlaylistShelfSegment) {
    let playlistIDs = Set(playlists(in: segment).map(\.id))
    selectedSegment = segment
    if let selectedPlaylistID, !playlistIDs.contains(selectedPlaylistID) {
      self.selectedPlaylistID = nil
    }
  }

  func selectFirstPlaylistIfNeeded() {
    guard selectedPlaylistID == nil else { return }
    selectedPlaylistID = displayedPlaylists.first?.id
  }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await client.read()
      requiresFolderAccess = false
      playlists = PlaylistShelf.make(from: result.ledger, now: now, calendar: .current, timeZone: .current)
      if keepClient.isAuthorized() {
        do {
          libraryPlaylists = try await keepClient.libraryPlaylists()
        } catch {
          libraryPlaylists = nil
        }
      } else {
        libraryPlaylists = nil
      }
      hasUnreadableFiles = result.totalFileCount > 0 && result.unreadableFileCount > 0
      if let selectedPlaylistID, !displayedPlaylists.contains(where: { $0.id == selectedPlaylistID }) {
        self.selectedPlaylistID = nil
      }
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      requiresFolderAccess = true
      playlists = []
      libraryPlaylists = nil
      selectedPlaylistID = nil
      hasUnreadableFiles = false
    } catch {
      requiresFolderAccess = false
      playlists = []
      libraryPlaylists = nil
      selectedPlaylistID = nil
      hasUnreadableFiles = true
    }
  }

  func setupButtonTapped() {
    destination = .setup
  }
}
