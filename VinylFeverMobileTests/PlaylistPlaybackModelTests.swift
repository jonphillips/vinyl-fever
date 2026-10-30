import Dependencies
import Foundation
import MusicKit
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistPlaybackModelTests {
  @Test @MainActor
  func libraryResolutionPrecedesCatalogAndMatchesCaseAndDiacritics() async throws {
    var catalogSearches = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { _ in [try song("Café", "Bánd", id: "i.library")] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in
        catalogSearches += 1
        return []
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: [(title: "Cafe", artist: "Band")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(model.resolvedSongs.values.first?.id.rawValue == "i.library")
    #expect(catalogSearches == 0)
  }

  @Test @MainActor
  func catalogSearchUsesTitleAndArtistAndIsLimitedToFive() async throws {
    var search: (String, Int)?
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { _ in [] }
      dependencies.playlistMusicClient.catalogSongs = { term, limit in
        search = (term, limit)
        return [try song("The Song", "The Band", id: "catalog")]
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: [(title: "The Song", artist: "The Band")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(model.resolvedSongs.values.first?.id.rawValue == "catalog")
    #expect(search?.0 == "The Song The Band")
    #expect(search?.1 == 5)
  }

  @Test @MainActor
  func missingSongsAreMarkedNotFound() async {
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { _ in [] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in [] }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: [(title: "Unknown", artist: "Artist")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(model.resolvedSongs.isEmpty)
    #expect(model.notFoundSongIDs.count == 1)
  }

  @Test @MainActor
  func stagedPlaylistTracksResolveBeforeLibrarySearch() async throws {
    let stagedSong = try song("Song", "Artist", id: "i.staged")
    let staged = try musicPlaylist("Staged", id: "p.staged", songs: [stagedSong])
    var librarySearches = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [try musicPlaylist("Staged", id: "p.staged")] }
      dependencies.playlistMusicClient.playlistDetails = { _ in staged }
      dependencies.playlistMusicClient.librarySongs = { _ in
        librarySearches += 1
        return []
      }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in [] }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(name: "Staged", tracks: [(title: "Song", artist: "Artist")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(model.resolvedSongs.values.first?.id.rawValue == "i.staged")
    #expect(librarySearches == 0)
  }

  @Test @MainActor
  func unresolvedStagedPlaylistLookupIsAwaitedBeforeResolvingRows() async throws {
    let stagedSong = try song("Song", "Artist", id: "i.staged")
    let staged = try musicPlaylist("Staged", id: "p.staged", songs: [stagedSong])
    let gate = PlaylistLookupGate()
    var librarySearches = 0
    let model = withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { await gate.fetch() }
      dependencies.playlistMusicClient.playlistDetails = { _ in staged }
      dependencies.playlistMusicClient.librarySongs = { _ in
        librarySearches += 1
        return []
      }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in [] }
    }) {
      PlaylistPlaybackModel()
    }
    let shelf = stagedPlaylist(name: "Staged", tracks: [(title: "Song", artist: "Artist")])
    await model.prepare(shelf)
    await gate.waitUntilStarted()
    let resolving = Task { await model.resolveSongs(through: 0) }
    await gate.release([try musicPlaylist("Staged", id: "p.staged")])
    await resolving.value

    #expect(model.resolvedSongs.values.first?.id.rawValue == "i.staged")
    #expect(librarySearches == 0)
  }

  @Test @MainActor
  func duplicatePlaylistNamesSkipDetailsAndResolveFromLibrary() async throws {
    let duplicateA = try musicPlaylist("Staged", id: "p.a")
    let duplicateB = try musicPlaylist("Staged", id: "p.b")
    var detailsReads = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [duplicateA, duplicateB] }
      dependencies.playlistMusicClient.playlistDetails = { _ in
        detailsReads += 1
        return duplicateA
      }
      dependencies.playlistMusicClient.librarySongs = { title in [try song(title, "Artist", id: "i.library")] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in [] }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(name: "Staged", tracks: [(title: "Song", artist: "Artist")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(detailsReads == 0)
    #expect(model.matchedPlaylist == nil)
    #expect(model.resolvedSongs.values.first?.id.rawValue == "i.library")
  }

  @Test @MainActor
  func missingStagedPlaylistFallsBackToLibraryAndCatalog() async throws {
    var catalogSearches = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { _ in [] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in
        catalogSearches += 1
        return [try song("Song", "Artist", id: "catalog")]
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(name: "Deleted playlist", tracks: [(title: "Song", artist: "Artist")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(catalogSearches == 1)
    #expect(model.resolvedSongs.values.first?.id.rawValue == "catalog")
  }

  @Test @MainActor
  func resolveThroughFourRequestsExactlyFourOfTwentySongs() async throws {
    var librarySearches = 0
    let tracks = (0..<20).map { (title: "Song \($0)", artist: "Artist") }
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { title in
        librarySearches += 1
        return [try song(title, "Artist", id: "i.\(title)")]
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: tracks))
      await model.resolveSongs(through: 3)
      return model
    }

    #expect(librarySearches == 4)
    #expect(model.resolvedSongs.count == 4)
  }

  @Test @MainActor
  func changingPlaylistThenPlayingQueuesTheNewPlaylist() async throws {
    var queuedIDs: [String] = []
    await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { title in
        [try song(title, "Artist", id: "i.\(title)")]
      }
      dependencies.playlistMusicClient.playSongs = { songs, _ in
        queuedIDs = songs.map { $0.id.rawValue }
      }
    }) {
      let model = PlaylistPlaybackModel()
      let first = stagedPlaylist(tracks: [(title: "A", artist: "Artist")])
      let second = stagedPlaylist(name: "Second", recordedAt: 2, tracks: [
        (title: "B", artist: "Artist"), (title: "C", artist: "Artist"),
      ])
      await model.prepare(first)
      await model.prepare(second)
      await model.play(second.songs[0].id)
      return model
    }

    #expect(queuedIDs == ["i.B", "i.C"])
  }

  @Test @MainActor
  func matchedPlaylistPlayOnlyResolvesTheTappedEntry() async throws {
    let musicSongs = try (0..<20).map { try song("Song \($0)", "Artist", id: "i.\($0)") }
    let detail = try musicPlaylist("Staged", id: "p.staged", songs: musicSongs)
    var librarySearches = 0
    var catalogSearches = 0
    var playedEntry: String?
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [try musicPlaylist("Staged", id: "p.staged")] }
      dependencies.playlistMusicClient.playlistDetails = { _ in detail }
      dependencies.playlistMusicClient.librarySongs = { _ in
        librarySearches += 1
        return []
      }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in
        catalogSearches += 1
        return []
      }
      dependencies.playlistMusicClient.playPlaylist = { _, entry in playedEntry = entry.title }
    }) {
      let model = PlaylistPlaybackModel()
      let shelf = stagedPlaylist(name: "Staged", tracks: musicSongs.enumerated().map {
        (title: $0.element.title, artist: $0.element.artistName)
      })
      await model.prepare(shelf)
      await model.play(shelf.songs[12].id)
      return model
    }

    #expect(playedEntry == "Song 12")
    #expect(model.resolvedSongs.count == 1)
    #expect(librarySearches == 0)
    #expect(catalogSearches == 0)
  }

  @Test @MainActor
  func fallbackPlayQueuesSongsInLedgerOrderAndStartsAtTappedSong() async throws {
    var queuedIDs: [String] = []
    var startingID: String?
    await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.librarySongs = { title in [try song(title, "Artist", id: "i.\(title)")] }
      dependencies.playlistMusicClient.playSongs = { songs, startingSong in
        queuedIDs = songs.map { $0.id.rawValue }
        startingID = startingSong.id.rawValue
      }
    }) {
      let model = PlaylistPlaybackModel()
      let shelf = stagedPlaylist(tracks: [
        (title: "First", artist: "Artist"),
        (title: "Second", artist: "Artist"),
        (title: "Third", artist: "Artist"),
      ])
      await model.prepare(shelf)
      await model.play(shelf.songs[1].id)
      return model
    }

    #expect(queuedIDs == ["i.First", "i.Second", "i.Third"])
    #expect(startingID == "i.Second")
  }

  @Test @MainActor
  func soundsLikePlaysAfterSkippingOrStartsAnEmptyQueue() async throws {
    var hasCurrentEntry = true
    var actions: [String] = []
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.hasCurrentEntry = { hasCurrentEntry }
      dependencies.playlistMusicClient.librarySongs = { title in [try song(title, "Artist", id: title)] }
      dependencies.playlistMusicClient.insertSong = { _, skip in actions.append(skip ? "insert-skip" : "insert-next") }
      dependencies.playlistMusicClient.play = { actions.append("play") }
      dependencies.playlistMusicClient.playSongs = { _, _ in actions.append("queue-and-play") }
    }) {
      let model = PlaylistPlaybackModel()
      await model.playLike(RecommendationLike(artist: "Artist", title: "Like"), afterCurrent: true)
      hasCurrentEntry = false
      await model.playLike(RecommendationLike(artist: "Artist", title: "Empty"), afterCurrent: true)
      await model.playLike(RecommendationLike(artist: "Artist", title: "Next"), afterCurrent: false)
      return model
    }

    #expect(actions == ["insert-skip", "play", "queue-and-play", "insert-next"])
    #expect(model.errorMessage == nil)
  }

  @Test @MainActor
  func nowPlayingSongIDFollowsTheInjectedPlayerStream() async {
    let first = FeedbackSong(title: "First", artist: "Artist")
    let second = FeedbackSong(title: "Second", artist: "Artist")
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.playlists = { [] }
      dependencies.playlistMusicClient.currentEntry = {
        AsyncStream { continuation in
          continuation.yield(first)
          continuation.yield(second)
          continuation.finish()
        }
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: [
        (title: "First", artist: "Artist"), (title: "Second", artist: "Artist"),
      ]))
      await model.observeCurrentEntry()
      return model
    }

    #expect(model.nowPlayingSongID?.hasSuffix("|1") == true)
  }

  @Test @MainActor
  func differentLibraryAndCatalogIDsMatchByTitleAndArtist() {
    let library = FeedbackSong(title: "Café", artist: "Bánd", catalogID: "i.library")
    let catalog = FeedbackSong(title: "Cafe", artist: "Band", catalogID: "catalog")
    #expect(MusicFeedback.matches(library, catalog))
  }

  @Test @MainActor
  func unauthorizedDoesNotResolveOrExposePlayback() async {
    var searches = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { false }
      dependencies.playlistMusicClient.librarySongs = { _ in
        searches += 1
        return []
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(stagedPlaylist(tracks: [(title: "Song", artist: "Artist")]))
      await model.resolveSongs(through: 0)
      return model
    }

    #expect(!model.isAuthorized)
    #expect(searches == 0)
    #expect(model.resolvedSongs.isEmpty)
  }

  private func song(_ title: String, _ artist: String, id: String) throws -> Song {
    let type = id.hasPrefix("i.") ? "library-songs" : "songs"
    let data = try JSONSerialization.data(withJSONObject: [
      "id": id,
      "type": type,
      "attributes": ["name": title, "artistName": artist],
    ])
    return try JSONDecoder().decode(Song.self, from: data)
  }

  private func musicPlaylist(_ name: String, id: String, songs: [Song] = []) throws -> Playlist {
    let trackData = songs.map { item -> [String: Any] in
      let type = item.id.rawValue.hasPrefix("i.") ? "library-songs" : "songs"
      return [
        "id": item.id.rawValue,
        "type": type,
        "attributes": ["name": item.title, "artistName": item.artistName],
      ]
    }
    let data = try JSONSerialization.data(withJSONObject: [
      "id": id,
      "type": "library-playlists",
      "attributes": ["name": name],
      "relationships": ["tracks": ["data": trackData]],
    ])
    return try JSONDecoder().decode(Playlist.self, from: data)
  }

  private func stagedPlaylist(
    name: String? = nil,
    recordedAt: TimeInterval = 1,
    tracks: [(title: String, artist: String)]
  ) -> PlaylistShelfPlaylist {
    let batch = RecommendationBatch(
      recordedAt: Date(timeIntervalSince1970: recordedAt), host: "Test", playlist: name,
      tracks: tracks.map { track in
        RecommendationTrack(artist: track.artist, title: track.title, familiar: false, reasons: [], artistKnown: true)
      }
    )
    return PlaylistShelf.make(from: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
      now: Date(timeIntervalSince1970: recordedAt + 1), calendar: .current, timeZone: .current)[0]
  }
}

private actor PlaylistLookupGate {
  private var continuation: CheckedContinuation<[Playlist], Never>?
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var started = false

  func fetch() async -> [Playlist] {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      started = true
      startedContinuation?.resume()
      startedContinuation = nil
    }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func release(_ playlists: [Playlist]) {
    continuation?.resume(returning: playlists)
    continuation = nil
  }
}
