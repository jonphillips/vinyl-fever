import Foundation
import Testing
@testable import VinylFeverNotes

struct PlaylistProgressTests {
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

  private func playlist(_ songs: [PlaylistShelfSong], at stagedAt: Date? = nil) -> PlaylistShelfPlaylist {
    let stage = stagedAt ?? date(100)
    let tracks = songs.map {
      RecommendationTrack(artist: $0.artist, title: $0.title, familiar: false, reasons: [], artistKnown: true)
    }
    let batch = RecommendationBatch(recordedAt: stage, host: "Test", playlist: "Test", tracks: tracks)
    return PlaylistShelfPlaylist(id: "playlist", batch: batch, stagedDate: "today",
      songCount: songs.count, newSongCount: songs.count, songs: songs)
  }

  private func song(_ id: String) -> PlaylistShelfSong {
    PlaylistShelfSong(id: id, title: id, artist: "Artist", album: nil, year: nil,
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
}
