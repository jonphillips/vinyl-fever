import Dependencies
import Foundation
import Observation
import VinylFeverNotes

struct PlaylistListeningLogClient {
  var read: @Sendable (Date, Date) async throws -> [ListeningPlay]
}

extension PlaylistListeningLogClient: TestDependencyKey {
  static var testValue: Self { Self(read: { _, _ in [] }) }
}

private enum PlaylistListeningLogClientKey: DependencyKey {
  static let liveValue = PlaylistListeningLogClient { oldestDate, now in
    try await Task.detached {
      try ProbeBookmarkStore.withFolder { folder in
        try PlaylistListeningLogReader.read(folder: folder, from: oldestDate, now: now)
      }
    }.value
  }
}

extension DependencyValues {
  var playlistListeningLogClient: PlaylistListeningLogClient {
    get { self[PlaylistListeningLogClientKey.self] }
    set { self[PlaylistListeningLogClientKey.self] = newValue }
  }
}

@MainActor
@Observable
final class PlaylistProgressModel {
  private(set) var results: [String: PlaylistProgressResult] = [:]
  private(set) var isAvailable = false
  private(set) var isLoading = false
  private(set) var hasUnreadableListeningLog = false

  @ObservationIgnored @Dependency(\.keepLibraryClient) private var keepClient
  @ObservationIgnored @Dependency(\.playlistTasteNotesClient) private var notesClient
  @ObservationIgnored @Dependency(\.playlistListeningLogClient) private var logClient
  @ObservationIgnored @Dependency(\.date.now) private var now

  private var playlists: [PlaylistShelfPlaylist] = []
  private var index: PlaylistProgressIndex?

  func refresh(_ playlists: [PlaylistShelfPlaylist]) async {
    self.playlists = playlists
    hasUnreadableListeningLog = false
    guard keepClient.isAuthorized() else {
      isAvailable = false
      index = nil
      results = [:]
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let library = try await keepClient.libraryPlaylists()
      let roles = try await keepClient.readRoles()
      let names = Set(roles?.playlists.filter { $0.role == .keepers }.map(\.name)
        ?? library.map(\.name).filter { $0 == "Vinyl Fever Keepers" || $0.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil })
      var readKeepers: [PlaylistKeeperTracks] = []
      for libraryPlaylist in library where names.contains(libraryPlaylist.name) {
        let tracks = try await keepClient.tracks(libraryPlaylist.id)
        readKeepers.append(PlaylistKeeperTracks(name: libraryPlaylist.name,
          tracks: tracks.map { PlaylistTrackIdentity(title: $0.title, artist: $0.artist) }))
      }
      let noteRead = try await notesClient.read()
      guard noteRead.unreadableFileCount == 0 else { throw PlaylistProgressReadError.incompleteNotes }
      let oldest = playlists.map(\.batch.recordedAt).min() ?? now
      let readPlays: [ListeningPlay]
      do {
        readPlays = try await logClient.read(oldest, now)
      } catch {
        hasUnreadableListeningLog = true
        throw error
      }

      let notes = TasteNotesCodec.uniqueNewestFirst(noteRead.result.notes)
      let calculation = await Task.detached(priority: .userInitiated) {
        var index = PlaylistProgressIndex(playlists: playlists, keepers: readKeepers,
          plays: readPlays, notes: notes)
        let results = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, index.result(for: $0)) })
        return (index, results)
      }.value
      index = calculation.0
      results = calculation.1
      isAvailable = true
    } catch {
      isAvailable = false
      index = nil
      results = [:]
    }
  }

  func updateSavedNotes(_ notes: [TasteNote]) {
    guard isAvailable, var index else { return }
    index.addNotes(TasteNotesCodec.uniqueNewestFirst(notes), playlists: playlists)
    self.index = index
    recompute()
  }

  func updateSavedKeeps(_ keptPlaylistsBySong: [String: [String]]) {
    guard isAvailable, var index else { return }
    for playlist in playlists {
      for song in playlist.songs {
        guard let names = keptPlaylistsBySong[song.id] else { continue }
        for name in names {
          index.addKeeper(name: name, artist: song.artist, title: song.title)
        }
      }
    }
    self.index = index
    recompute()
  }

  private func recompute() {
    guard var index else { return }
    results = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, index.result(for: $0)) })
    self.index = index
  }
}

private enum PlaylistProgressReadError: Error {
  case incompleteNotes
}
