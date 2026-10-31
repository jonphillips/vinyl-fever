import Foundation
import Testing
@testable import VinylFeverNotes

struct PlaylistProgressTests {
  @Test func sharedSongKeyHandlesAppleMusicPunctuationVariants() {
    let pairs = [
      ("You’re Not the One", "You're Not the One"),
      ("Me & Magdalena", "Me and Magdalena"),
      ("Danger! High Voltage!", "Danger! High Voltage"),
    ]
    for (logged, staged) in pairs {
      #expect(ListeningTrackKey.make(artist: "Artist", title: logged)
        == ListeningTrackKey.make(artist: "Artist", title: staged))
      let result = PlaylistProgress.make(playlist: playlist([song(staged)]), keepers: [],
        plays: [play(logged, end: 101)], notes: [])
      #expect(result.songs[staged] == .passed(withFeedback: false))
    }
  }

  @Test func curlyApostropheInKeeperTrackMatchesStraightApostropheInPlaylist() {
    let title = "You're Not the One"
    let keeperTrack = PlaylistTrackIdentity(title: "You’re Not the One", artist: "Artist")
    let result = PlaylistProgress.make(playlist: playlist([song(title)]),
      keepers: [keeper("Vinyl Fever Keepers", [keeperTrack])], plays: [], notes: [])
    #expect(result.songs[title] == .kept(in: ["Vinyl Fever Keepers"]))
  }

  @Test func keeperNamesAreListedAndKeptDoesNotNeedAPlay() {
    let result = PlaylistProgress.make(
      playlist: playlist([song("one")]),
      keepers: [keeper("Vinyl Fever Keepers", [track("one")]), keeper("Selections", [track("one")])],
      plays: [], notes: [])

    #expect(result.songs["one"] == .kept(in: ["Selections", "Vinyl Fever Keepers"]))
    #expect(result.counts.kept == 1)
    #expect(result.counts.heard == 1)
  }

  @Test func playCountsOnlyWhenItsWindowEndsAtOrAfterStaging() {
    let stage = date(100)
    let before = play("one", end: 99)
    let after = play("one", end: 101)
    let beforeResult = PlaylistProgress.make(playlist: playlist([song("one")], at: stage), keepers: [], plays: [before], notes: [])
    let afterResult = PlaylistProgress.make(playlist: playlist([song("one")], at: stage), keepers: [], plays: [after], notes: [])

    #expect(beforeResult.songs["one"] == .notHeard)
    #expect(afterResult.songs["one"] == .passed(withFeedback: false))
  }

  @Test func aNoteAfterStagingMakesAnUnheardSongPassedWithFeedback() {
    let result = PlaylistProgress.make(
      playlist: playlist([song("one")]), keepers: [], plays: [], notes: [note("one", at: 101)])
    #expect(result.songs["one"] == .passed(withFeedback: true))
    #expect(result.counts.passedWithFeedback == 1)
  }

  @Test func aNoteBeforeStagingDoesNotCount() {
    let result = PlaylistProgress.make(
      playlist: playlist([song("one")]), keepers: [], plays: [], notes: [note("one", at: 99)])
    #expect(result.songs["one"] == .notHeard)
  }

  @Test func countsPartitionEverySong() {
    let songs = [song("kept"), song("noted"), song("played"), song("unheard")]
    let result = PlaylistProgress.make(
      playlist: playlist(songs), keepers: [keeper("Keepers", [track("kept")])],
      plays: [play("played", end: 101)], notes: [note("noted", at: 101)])

    #expect(result.counts == PlaylistProgressCounts(kept: 1, passedWithFeedback: 1, passedWithoutFeedback: 1, notHeard: 1))
    #expect(result.counts.songCount == songs.count)
  }

  @Test func indexedResultsMatchThePerPairRuleForDeterministicRandomInputs() {
    var random = ProgressRandom(seed: 0x5eed)
    let titlePool = ["You're Not the One", "Me & Magdalena", "Danger! High Voltage", "Song 4", "Song 5", "Song 6"]
    let artistPool = ["The Records", "Artist & Friends", "Another Artist"]
    let playlists = (0..<5).map { playlistIndex in
      let songs = (0..<20).map { songIndex -> PlaylistShelfSong in
        let title = titlePool[random.next(upperBound: titlePool.count)]
        let artist = artistPool[random.next(upperBound: artistPool.count)]
        return PlaylistShelfSong(id: "p\(playlistIndex)-s\(songIndex)", title: title, artist: artist,
          album: nil, year: nil, familiarity: "New", why: nil, like: [])
      }
      return playlist(songs, at: date(TimeInterval(100 + playlistIndex * 10)), id: "p\(playlistIndex)")
    }
    let keepers = (0..<4).map { keeperIndex in
      PlaylistKeeperTracks(name: "Keeper \(keeperIndex)", tracks: (0..<20).map { _ in
        PlaylistTrackIdentity(title: titlePool[random.next(upperBound: titlePool.count)],
          artist: artistPool[random.next(upperBound: artistPool.count)])
      })
    }
    let plays = (0..<150).map { index in
      let end = TimeInterval(random.next(upperBound: 200))
      return ListeningPlay(item: .init(kind: .song, id: "play-\(index)",
        title: titlePool[random.next(upperBound: titlePool.count)],
        artist: artistPool[random.next(upperBound: artistPool.count)]),
        windowStart: date(end - 1), windowEnd: date(end), poller: UUID())
    }
    let notes = (0..<20).map { index in
      TasteNote(notedAt: date(TimeInterval(random.next(upperBound: 200))), note: "Note \(index)",
        source: "test", title: titlePool[random.next(upperBound: titlePool.count)],
        artist: artistPool[random.next(upperBound: artistPool.count)])
    }
    var index = PlaylistProgressIndex(playlists: playlists, keepers: keepers, plays: plays, notes: notes)

    for playlist in playlists {
      #expect(index.result(for: playlist) == slowResult(playlist: playlist, keepers: keepers, plays: plays, notes: notes))
    }
  }

  @Test("playlist progress indexes evidence at Jon's scale", .enabled(if: ProcessInfo.processInfo.environment["VF_PERF_TESTS"] == "1"))
  func progressAtJonsScale() {
    let titles = (0..<260).map { "Track \($0)" }
    let playlists = (0..<5).map { playlistIndex in
      let count = playlistIndex == 0 ? 200 : 15
      let songs = (0..<count).map { index in
        song(titles[(playlistIndex * 15 + index) % titles.count], id: "p\(playlistIndex)-\(index)")
      }
      return playlist(songs, at: date(100 + TimeInterval(playlistIndex)), id: "p\(playlistIndex)")
    }
    let keepers = (0..<3).map { keeperIndex in
      PlaylistKeeperTracks(name: "Keeper \(keeperIndex)", tracks: (0..<250).map { index in
        PlaylistTrackIdentity(title: titles[(keeperIndex * 250 + index) % titles.count], artist: "Artist \(index % 20)")
      })
    }
    let plays = (0..<1_100).map { index in
      ListeningPlay(item: .init(kind: .song, id: "play-\(index)", title: "Track \(index % 260)",
        artist: "Artist \(index % 20)"), windowStart: date(100), windowEnd: date(200), poller: UUID())
    }
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      var index = PlaylistProgressIndex(playlists: playlists, keepers: keepers, plays: plays, notes: [])
      _ = playlists.map { index.result(for: $0) }
    }
    #expect(elapsed < .milliseconds(50), "Indexed progress took \(elapsed).")
  }

  private func playlist(_ songs: [PlaylistShelfSong], at stagedAt: Date? = nil, id: String = "playlist") -> PlaylistShelfPlaylist {
    let stage = stagedAt ?? date(100)
    let tracks = songs.map {
      RecommendationTrack(artist: $0.artist, title: $0.title, familiar: false, reasons: [], artistKnown: true)
    }
    let batch = RecommendationBatch(recordedAt: stage, host: "Test", playlist: "Test", tracks: tracks)
    return PlaylistShelfPlaylist(id: id, batch: batch, stagedDate: "today",
      songCount: songs.count, newSongCount: songs.count, songs: songs)
  }

  private func song(_ title: String, id: String? = nil) -> PlaylistShelfSong {
    PlaylistShelfSong(id: id ?? title, title: title, artist: "Artist", album: nil, year: nil,
      familiarity: "New to you", why: nil, like: [])
  }

  private func track(_ id: String) -> PlaylistTrackIdentity { .init(title: id, artist: "Artist") }
  private func keeper(_ name: String, _ tracks: [PlaylistTrackIdentity]) -> PlaylistKeeperTracks { .init(name: name, tracks: tracks) }
  private func play(_ id: String, end: TimeInterval) -> ListeningPlay {
    ListeningPlay(item: .init(kind: .song, id: id, title: id, artist: "Artist"),
      windowStart: date(end - 1), windowEnd: date(end), poller: UUID())
  }
  private func note(_ id: String, at instant: TimeInterval) -> TasteNote {
    TasteNote(notedAt: date(instant), note: "A note", source: "test", title: id, artist: "Artist")
  }
  private func date(_ value: TimeInterval) -> Date { Date(timeIntervalSince1970: value) }

  private func slowResult(playlist: PlaylistShelfPlaylist, keepers: [PlaylistKeeperTracks],
    plays: [ListeningPlay], notes: [TasteNote]) -> PlaylistProgressResult {
    var songs: [String: PlaylistSongProgress] = [:]
    var counts = PlaylistProgressCounts(kept: 0, passedWithFeedback: 0, passedWithoutFeedback: 0, notHeard: 0)
    for song in playlist.songs {
      let key = ListeningTrackKey.make(artist: song.artist, title: song.title)
      let keeperNames = Set(keepers.filter { keeper in keeper.tracks.contains { track in
        ListeningTrackKey.make(artist: track.artist, title: track.title) == key
      } }.map(\.name)).sorted()
      let heard = plays.contains { $0.windowEnd >= playlist.batch.recordedAt
        && ListeningTrackKey.make(artist: $0.item.artist, title: $0.item.title) == key }
      let hasNote = notes.contains { note in
        note.notedAt >= playlist.batch.recordedAt
          && !PlaylistTasteNotes.matching([note], title: song.title, artist: song.artist).isEmpty
      }
      if !keeperNames.isEmpty {
        songs[song.id] = .kept(in: keeperNames); counts.kept += 1
      } else if heard || hasNote {
        songs[song.id] = .passed(withFeedback: hasNote)
        if hasNote { counts.passedWithFeedback += 1 } else { counts.passedWithoutFeedback += 1 }
      } else {
        songs[song.id] = .notHeard; counts.notHeard += 1
      }
    }
    return PlaylistProgressResult(songs: songs, counts: counts)
  }
}

private struct ProgressRandom {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next(upperBound: Int) -> Int {
    state = state &* 6_364_136_223_846_793_005 &+ 1
    return Int((state >> 32) % UInt64(upperBound))
  }
}
