import Dependencies
import DependenciesMacros
import MusicKit
import VinylFeverNotes

@DependencyClient
struct PlaylistMusicClient {
  var isAuthorized: @MainActor @Sendable () -> Bool = { false }
  var playlists: @MainActor @Sendable () async throws -> [Playlist]
  var playlistDetails: @MainActor @Sendable (Playlist) async throws -> Playlist
  var librarySongs: @MainActor @Sendable (String) async throws -> [Song]
  var catalogSongs: @MainActor @Sendable (String, Int) async throws -> [Song]
  var playPlaylist: @MainActor @Sendable (Playlist, Song) async throws -> Void
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
    playPlaylist: { playlist, song in
      guard let entries = playlist.entries,
        let entry = entries.first(where: { entry in
          guard case let .song(candidate)? = entry.item else { return false }
          return MusicFeedback.matches(
            FeedbackSong(title: candidate.title, artist: candidate.artistName),
            FeedbackSong(title: song.title, artist: song.artistName)
          )
        })
      else { throw PlaylistMusicError.playlistEntryNotFound }
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

enum PlaylistMusicError: Error {
  case playlistEntryNotFound
}
