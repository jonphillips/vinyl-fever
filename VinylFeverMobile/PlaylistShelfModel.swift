import Dependencies
import DependenciesMacros
import Foundation
import Observation
import VinylFeverNotes

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
  var selectedPlaylistID: String?
  var destination: Destination?

  @ObservationIgnored
  @Dependency(\.playlistShelfClient) private var client
  @ObservationIgnored
  @Dependency(\.date.now) private var now

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await client.read()
      requiresFolderAccess = false
      playlists = PlaylistShelf.make(from: result.ledger, now: now, calendar: .current, timeZone: .current)
      hasUnreadableFiles = result.totalFileCount > 0 && result.unreadableFileCount > 0
      if let selectedPlaylistID, !playlists.contains(where: { $0.id == selectedPlaylistID }) {
        self.selectedPlaylistID = nil
      }
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      requiresFolderAccess = true
      playlists = []
      selectedPlaylistID = nil
      hasUnreadableFiles = false
    } catch {
      requiresFolderAccess = false
      playlists = []
      selectedPlaylistID = nil
      hasUnreadableFiles = true
    }
  }

  func setupButtonTapped() {
    destination = .setup
  }
}
