import Foundation
import Testing
import VinylFeverNotes

struct RecommendationLedgerTests {
  @Test("playlist shelf keeps staged batches, reasons, counts, and dates")
  func playlistShelf() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
    let recent = RecommendationBatch(recordedAt: ISO8601DateFormatter().date(from: "2026-10-28T12:00:00Z")!,
      host: "Mac", playlist: "Recent", tracks: [
        RecommendationTrack(artist: "New Artist", title: "New song", familiar: false, reasons: [], artistKnown: true,
          why: "Because it sparkles", like: [RecommendationLike(artist: "The Records", title: "Starry Eyes")]),
        RecommendationTrack(artist: "Known Artist", title: "Known song", familiar: true,
          reasons: ["recommended", "noted", "heard", "playlist:curated", "owned", "playlist:keepers"],
          artistKnown: true, why: " "),
        RecommendationTrack(artist: "Playlist Artist", title: "Playlist song", familiar: true,
          reasons: ["playlist:unlabeled"], artistKnown: true),
        RecommendationTrack(artist: "Heard Artist", title: "Heard song", familiar: true,
          reasons: ["heard", "noted"], artistKnown: true),
        RecommendationTrack(artist: "Noted Artist", title: "Noted song", familiar: true,
          reasons: ["noted"], artistKnown: true),
        RecommendationTrack(artist: "Recommended Artist", title: "Recommended song", familiar: true,
          reasons: ["recommended"], artistKnown: true),
        RecommendationTrack(artist: "Unknown Artist", title: "Unknown song", familiar: true,
          reasons: [], artistKnown: true),
        RecommendationTrack(artist: "Reason Artist", title: "Reason only", familiar: true,
          reasons: ["owned"], artistKnown: true, why: "Recorded without a comparison"),
      ], request: "Find more power pop")
    let earlierRecent = RecommendationBatch(recordedAt: ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!,
      host: "Mac", playlist: "Recent", tracks: [])
    let old = RecommendationBatch(recordedAt: ISO8601DateFormatter().date(from: "2025-10-29T12:00:00Z")!,
      host: "Mac", tracks: [RecommendationTrack(artist: "Artist", title: "No reason", familiar: true,
        reasons: [], artistKnown: true)])
    let picks = RecommendationBatch(kind: "new-music-picks", recordedAt: now, host: "Mac", playlist: "Picks", tracks: [])
    let shelf = PlaylistShelf.make(from: RecommendationLedgerReadResult(
      batches: [old, recent, earlierRecent, picks], skippedLines: 0),
      now: now, calendar: calendar, timeZone: calendar.timeZone)

    #expect(shelf.map(\.batch) == [recent, earlierRecent, old])
    #expect(shelf.map(\.batch.playlist) == ["Recent", "Recent", nil])
    #expect(shelf[0].songCount == 8)
    #expect(shelf[0].newSongCount == 1)
    #expect(shelf[0].stagedDate == "October 28")
    #expect(shelf[1].stagedDate == "October 27")
    #expect(shelf[2].stagedDate == "October 29, 2025")
    #expect(shelf[0].songs.map(\.familiarity) == [
      "New to you", "You kept it", "In one of your playlists", "You've heard it",
      "You left a note on it", "Recommended before", "You knew it", "In your library",
    ])
    #expect(shelf[0].songs[0].why == "Because it sparkles")
    #expect(shelf[0].songs[0].like.count == 1)
    #expect(shelf[0].songs[1].why == nil)
    #expect(shelf[0].songs[7].why == "Recorded without a comparison")
    #expect(shelf[0].songs[7].like.isEmpty)
    #expect(PlaylistShelf.noReasonsText(for: shelf[0]) == nil)
    #expect(PlaylistShelf.noReasonsText(for: shelf[2]) == "No reasons were recorded for this playlist.")

    let inserted = RecommendationBatch(
      recordedAt: ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!,
      host: "Another Mac", playlist: "Earlier batch", tracks: [
        RecommendationTrack(artist: "Band", title: "Inserted song", familiar: false, reasons: [], artistKnown: true),
      ])
    let expanded = PlaylistShelf.make(from: RecommendationLedgerReadResult(
      batches: [inserted, old, recent, earlierRecent, picks], skippedLines: 0),
      now: now, calendar: calendar, timeZone: calendar.timeZone)
    for original in shelf {
      let matching = try #require(expanded.first { $0.batch == original.batch })
      #expect(matching.id == original.id)
      #expect(matching.songs.map(\.id) == original.songs.map(\.id))
    }
  }

  @Test("JSONL round-trips and tolerates blank lines, unsupported records, partial tails and no final newline")
  func ledgerCodec() throws {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let batch = RecommendationBatch(recordedAt: instant, host: "Jon MBP", playlist: "Power Pop",
      tracks: [RecommendationTrack(artist: "The Records", title: "Starry Eyes", album: "Shades in Bed",
        year: 1979, familiar: false, reasons: [], artistKnown: true)])
    let encoded = try RecommendationLedgerCodec.encode(batch)
    let decoded = RecommendationLedgerCodec.readFiles([encoded])
    #expect(decoded.batches == [batch])
    let validWithoutNewline = Data(encoded.dropLast())
    let unsupported = Data(#"{"format":"vf-recommendation-batch","version":2}"#.utf8)
    let stream = Data((String(decoding: validWithoutNewline, as: UTF8.self) + "\n\n" +
      String(decoding: unsupported, as: UTF8.self) + "\n{\"partial\":").utf8)
    let result = RecommendationLedgerCodec.readFiles([stream])
    #expect(result.batches == [batch])
    #expect(result.skippedLines == 1)
  }

  @Test("playlist names load from every host and skip batches without a playlist")
  func playlistNamesInFolder() throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "recommendation-playlist-names-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let first = RecommendationBatch(recordedAt: .now, host: "Mac one", playlist: "First batch", tracks: [])
    let second = RecommendationBatch(recordedAt: .now, host: "Mac two", playlist: "Second batch", tracks: [])
    let noPlaylist = RecommendationBatch(recordedAt: .now, host: "Mac two", tracks: [])
    let firstData = try RecommendationLedgerCodec.encode(first)
    let secondData = try RecommendationLedgerCodec.encode(second) + RecommendationLedgerCodec.encode(noPlaylist)
    try firstData.write(to: folder.appending(path: "Mac-one.jsonl"))
    try (secondData + Data("{malformed}\n".utf8)).write(to: folder.appending(path: "Mac-two.jsonl"))

    #expect(try RecommendationLedgerCodec.playlistNames(inFolder: folder) == ["First batch", "Second batch"])
  }
}
