import Dependencies
import DependenciesMacros
import Foundation
import GRDB
import Observation
import SQLiteData
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
  private(set) var creationEvents: [PlaylistCreationEvent] = []
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
  @ObservationIgnored
  @Dependency(\.mobileCacheDatabase) private var database

  private var didLoadCache = false
  private var shelfCache = MobileShelfCache.empty

  private var libraryPlaylistNames: [String]? {
    guard let libraryPlaylists else { return nil }
    return libraryPlaylists.map(\.name)
  }

  private var archivedPlaylistIDs: Set<String> {
    PlaylistArchive.archivedPlaylistIDs(from: playlists, libraryPlaylistNames: libraryPlaylistNames,
      creations: creationEvents, now: now)
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

  func isNotInMusicYet(_ playlist: PlaylistShelfPlaylist) -> Bool {
    guard keepClient.isAuthorized(), let libraryPlaylistNames,
      let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
      !libraryPlaylistNames.contains(name)
    else { return false }
    let key = PlaylistCreationsCodec.batchKey(host: playlist.batch.host, recordedAt: playlist.batch.recordedAt)
    return PlaylistCreationsCodec.latestEvents(creationEvents)[key]?.kind != .created
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
    loadCacheIfNeeded()
    isLoading = true
    defer { isLoading = false }
    do {
      let result = try await client.read()
      requiresFolderAccess = false
      let merged = ShelfCache.mergeShelf(result, with: shelfCache)
      shelfCache = merged
      playlists = PlaylistShelf.make(
        from: RecommendationLedgerReadResult(batches: merged.batches, skippedLines: 0),
        now: now, calendar: .current, timeZone: .current
      )
      creationEvents = merged.creationEvents
      if let database {
        do {
          try ShelfCache.writeShelf(merged, to: database)
        } catch {
          NSLog("Vinyl Fever mobile shelf cache could not be saved: %@", error.localizedDescription)
        }
      }
      if keepClient.isAuthorized() {
        do {
          libraryPlaylists = try await keepClient.libraryPlaylists()
          if let libraryPlaylists, let database { try ShelfCache.replaceLibrary(libraryPlaylists, to: database) }
        } catch {
          // Keep the last successfully read Music library snapshot.
        }
      } else {
        libraryPlaylists = nil
      }
      hasUnreadableFiles = (result.totalFileCount > 0 && result.unreadableFileCount > 0)
        || result.creations.unreadableFileCount > 0 || result.creations.skippedLines > 0
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
      hasUnreadableFiles = true
    }
  }

  func loadCache() {
    loadCacheIfNeeded()
  }

  private func loadCacheIfNeeded() {
    guard !didLoadCache else { return }
    didLoadCache = true
    guard let database else { return }
    do {
      let cache = try ShelfCache.load(from: database)
      shelfCache = cache
      playlists = PlaylistShelf.make(
        from: RecommendationLedgerReadResult(batches: cache.batches, skippedLines: 0),
        now: now, calendar: .current, timeZone: .current
      )
      creationEvents = cache.creationEvents
      libraryPlaylists = keepClient.isAuthorized() ? cache.libraryPlaylists : nil
    } catch {
      NSLog("Vinyl Fever mobile shelf cache could not be loaded: %@", error.localizedDescription)
    }
  }

  func setupButtonTapped() {
    destination = .setup
  }
}
