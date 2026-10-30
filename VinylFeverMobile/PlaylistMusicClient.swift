import Dependencies
import DependenciesMacros
import Combine
import MusicKit
import VinylFeverNotes

@DependencyClient
struct PlaylistMusicClient {
  var isAuthorized: @MainActor @Sendable () -> Bool = { false }
  var hasCurrentEntry: @MainActor @Sendable () -> Bool = { false }
  var currentEntry: @MainActor @Sendable () -> AsyncStream<FeedbackSong?> = {
    AsyncStream { $0.finish() }
  }
  var playlists: @MainActor @Sendable () async throws -> [Playlist]
  var playlistDetails: @MainActor @Sendable (Playlist) async throws -> Playlist
  var librarySongs: @MainActor @Sendable (String) async throws -> [Song]
  var catalogSongs: @MainActor @Sendable (String, Int) async throws -> [Song]
  var playPlaylist: @MainActor @Sendable (Playlist, Playlist.Entry) async throws -> Void
  var playSongs: @MainActor @Sendable ([Song], Song) async throws -> Void
  var insertSong: @MainActor @Sendable (Song, Bool) async throws -> Void
  var play: @MainActor @Sendable () async throws -> Void
}

extension PlaylistMusicClient: TestDependencyKey {
  static var testValue: Self { Self() }
}

private enum PlaylistMusicClientKey: DependencyKey {
  static let liveValue = PlaylistMusicClient(
    isAuthorized: { MusicAuthorization.currentStatus == .authorized },
    hasCurrentEntry: { SystemMusicPlayer.shared.queue.currentEntry != nil },
    currentEntry: {
      AsyncStream { continuation in
        let queue = SystemMusicPlayer.shared.queue
        let observation = Task { @MainActor in
          func currentSong() -> FeedbackSong? {
            guard let entry = queue.currentEntry else { return nil }
            let artist: String
            if case let .song(song)? = entry.item {
              artist = song.artistName
            } else {
              artist = entry.subtitle ?? ""
            }
            return FeedbackSong(title: entry.title, artist: artist)
          }
          continuation.yield(currentSong())
          for await _ in queue.objectWillChange.values {
            await Task.yield()
            continuation.yield(currentSong())
          }
        }
        continuation.onTermination = { _ in observation.cancel() }
      }
    },
    playlists: {
      var request = MusicLibraryRequest<Playlist>()
      request.limit = 1_000
      return Array(try await request.response().items)
    },
    playlistDetails: { playlist in
      try await playlist.with(.entries, .tracks, preferredSource: .library)
    },
    librarySongs: { title in
      var request = MusicLibrarySearchRequest(term: title, types: [Song.self])
      request.limit = 25
      return Array(try await request.response().songs)
    },
    catalogSongs: { term, limit in
      var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
      request.limit = limit
      return Array(try await request.response().songs)
    },
    playPlaylist: { playlist, entry in
      let player = SystemMusicPlayer.shared
      player.queue = MusicPlayer.Queue(playlist: playlist, startingAt: entry)
      try await player.play()
    },
    playSongs: { songs, startingSong in
      let player = SystemMusicPlayer.shared
      player.queue = MusicPlayer.Queue(for: songs, startingAt: startingSong)
      try await player.play()
    },
    insertSong: { song, skip in
      let player = SystemMusicPlayer.shared
      try await player.queue.insert(song, position: .afterCurrentEntry)
      if skip { try await player.skipToNextEntry() }
    },
    play: { try await SystemMusicPlayer.shared.play() }
  )
}

extension DependencyValues {
  var playlistMusicClient: PlaylistMusicClient {
    get { self[PlaylistMusicClientKey.self] }
    set { self[PlaylistMusicClientKey.self] = newValue }
  }
}
