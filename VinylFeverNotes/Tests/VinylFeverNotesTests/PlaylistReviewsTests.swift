import Foundation
import Testing
import VinylFeverNotes

struct PlaylistReviewsTests {
  @Test("New Music week ids use UTC ISO 8601 whole seconds")
  func newMusicWeekID() {
    let date = Date(timeIntervalSince1970: 1_800_000_000.987)
    #expect(PlaylistReviewsCodec.newMusicWeekID(date) == "new-music-week|2027-01-15T08:00:00Z")
  }

  @Test("each playlist review kind round trips as a versioned line")
  func codecRoundTrip() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000.125)
    let entries = [
      PlaylistReviewEntry(source: .jon, kind: .finished, host: "Mac", recordedAt: at,
        playlistID: "Mac|legacy", playlist: "Legacy Playlist", at: at, device: "iPhone"),
      PlaylistReviewEntry(source: .jon, kind: .finished, host: "Mac", recordedAt: at,
        playlistID: "Mac|1", playlist: "Playlist", at: at, device: "iPhone",
        heard: 1, kept: 1, passed: 0, unheard: 0,
        songs: [PlaylistReviewSongOutcome(index: 0, title: "Song", artist: "Artist", status: "kept", keptIn: ["Keepers"])]),
      PlaylistReviewEntry(source: .jon, kind: .reopened, host: "Mac", recordedAt: at,
        playlistID: "Mac|1", playlist: "Playlist", at: at.addingTimeInterval(1), device: "iPhone"),
      PlaylistReviewEntry(source: .chat, kind: .review, host: "Mac", recordedAt: at,
        playlistID: "Mac|1", playlist: "Playlist", at: at.addingTimeInterval(2), text: "A thoughtful arc.",
        heard: 4, kept: 2, passed: 1, unheard: 1),
    ]

    for entry in entries {
      let data = try PlaylistReviewsCodec.encode(entry)
      let result = PlaylistReviewsCodec.readFiles([data])
      #expect(result.entries == [entry])
      #expect(result.skippedLines == 0)
      #expect(String(decoding: data, as: UTF8.self).contains("\"format\":\"vf-playlist-review\""))
      #expect(String(decoding: data, as: UTF8.self).contains("\"version\":1"))
    }
  }

  @Test("latest Jon line wins and unreadable lines are counted")
  func latestJonStateAndUnreadableLines() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let finished = PlaylistReviewEntry(source: .jon, kind: .finished, host: "Mac", recordedAt: at,
      playlistID: "Mac|1", playlist: "Playlist", at: at, device: "iPhone")
    let reopened = PlaylistReviewEntry(source: .jon, kind: .reopened, host: "Mac", recordedAt: at,
      playlistID: "Mac|1", playlist: "Playlist", at: at.addingTimeInterval(1), device: "iPhone")
    let read = PlaylistReviewsCodec.readFiles([
      try PlaylistReviewsCodec.encode(finished) + PlaylistReviewsCodec.encode(reopened) + Data("{bad}\n".utf8),
    ])

    #expect(read.entries == [finished, reopened])
    #expect(read.skippedLines == 1)
    #expect(PlaylistReviewsCodec.latestJonState(in: read.entries)["Mac|1"]?.kind == .reopened)
  }
}
