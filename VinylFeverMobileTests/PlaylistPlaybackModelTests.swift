import Dependencies
import MusicKit
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistPlaybackModelTests {
  @Test @MainActor
  func libraryResolutionPrecedesCatalogAndMatchesCaseAndDiacritics() async {
    var catalogSearches = 0
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.librarySongs = { _ in [song("Café", "Bánd", id: "library")] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in
        catalogSearches += 1
        return []
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(playlist([("Cafe", "Band")]))
      return model
    }

    #expect(model.resolvedSongs.values.first?.id.rawValue == "library")
    #expect(catalogSearches == 0)
  }

  @Test @MainActor
  func catalogSearchUsesTitleAndArtistAndIsLimitedToFive() async {
    var search: (String, Int)?
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.librarySongs = { _ in [] }
      dependencies.playlistMusicClient.catalogSongs = { term, limit in
        search = (term, limit)
        return [song("The Song", "The Band", id: "catalog")]
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(playlist([("The Song", "The Band")]))
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
      dependencies.playlistMusicClient.librarySongs = { _ in [] }
      dependencies.playlistMusicClient.catalogSongs = { _, _ in [] }
    }) {
      let model = PlaylistPlaybackModel()
      await model.prepare(playlist([("Unknown", "Artist")]))
      return model
    }

    #expect(model.resolvedSongs.isEmpty)
    #expect(model.notFoundSongIDs.count == 1)
  }

  @Test @MainActor
  func playQueuesResolvedSongsInLedgerOrderStartingAtTappedSong() async {
    var queuedIDs: [String] = []
    var startingID: String?
    let entries = [("First", "Artist"), ("Second", "Artist"), ("Third", "Artist")]
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.librarySongs = { title in
        [song(title, "Artist", id: title)]
      }
      dependencies.playlistMusicClient.playSongs = { songs, startingSong in
        queuedIDs = songs.map { $0.id.rawValue }
        startingID = startingSong.id.rawValue
      }
    }) {
      let model = PlaylistPlaybackModel()
      let staged = playlist(entries)
      await model.prepare(staged)
      await model.play(staged.songs[1].id)
      return model
    }

    #expect(queuedIDs == ["First", "Second", "Third"])
    #expect(startingID == "Second")
    #expect(model.errorMessage == nil)
  }

  @Test @MainActor
  func soundsLikeTapSkipsAndPlayNextOnlyInserts() async {
    var actions: [(String, Bool)] = []
    let model = await withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.librarySongs = { title in
        [song(title, "Artist", id: title)]
      }
      dependencies.playlistMusicClient.insertSong = { song, skip in
        actions.append((song.id.rawValue, skip))
      }
    }) {
      let model = PlaylistPlaybackModel()
      await model.playLike(RecommendationLike(artist: "Artist", title: "Like Song"), afterCurrent: true)
      await model.playLike(RecommendationLike(artist: "Artist", title: "Next Song"), afterCurrent: false)
      return model
    }

    #expect(actions.map(\.0) == ["Like Song", "Next Song"])
    #expect(actions.map(\.1) == [true, false])
    #expect(model.errorMessage == nil)
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
      await model.prepare(playlist([("Song", "Artist")]))
      return model
    }

    #expect(!model.isAuthorized)
    #expect(searches == 0)
    #expect(model.resolvedSongs.isEmpty)
  }

  private func song(_ title: String, _ artist: String, id: String) -> Song {
    Song(id: MusicItemID(id), title: title, artistName: artist)
  }

  private func playlist(_ songs: [(String, String)]) -> PlaylistShelfPlaylist {
    let batch = RecommendationBatch(
      recordedAt: Date(timeIntervalSince1970: 1), host: "Test", playlist: nil,
      tracks: songs.map { artist, title in
        RecommendationTrack(artist: artist, title: title, familiar: false, reasons: [], artistKnown: true)
      }
    )
    return PlaylistShelf.make(from: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
      now: Date(timeIntervalSince1970: 2), calendar: .current, timeZone: .current)[0]
  }
}
