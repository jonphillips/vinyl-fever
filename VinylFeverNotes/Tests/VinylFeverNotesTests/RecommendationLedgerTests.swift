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

  @Test("playlist shelf carries chat writeups and marks the first song in each section run")
  func playlistShelfChatWriteups() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let batch = RecommendationBatch(recordedAt: date, host: "Mac", playlist: "Grouped", tracks: [
      RecommendationTrack(artist: "A", title: "One", familiar: false, reasons: [], artistKnown: true,
        tag: " Strong bet ", details: [" Scotland ", " "], story: " A paragraph "),
      RecommendationTrack(artist: "A", title: "Two", familiar: false, reasons: [], artistKnown: true, section: "A"),
      RecommendationTrack(artist: "A", title: "Three", familiar: false, reasons: [], artistKnown: true, section: "A"),
      RecommendationTrack(artist: "A", title: "Four", familiar: false, reasons: [], artistKnown: true, section: "B"),
      RecommendationTrack(artist: "A", title: "Five", familiar: false, reasons: [], artistKnown: true, section: "A"),
    ])
    let shelf = try #require(PlaylistShelf.make(from: RecommendationLedgerReadResult(
      batches: [batch], skippedLines: 0), now: date, calendar: .current, timeZone: .current).first)
    #expect(shelf.songs[0].tag == "Strong bet")
    #expect(shelf.songs[0].details == ["Scotland"])
    #expect(shelf.songs[0].story == "A paragraph")
    #expect(shelf.songs.map(\.sectionHeading) == [nil, "A", nil, "B", "A"])
  }

  @Test("playlist paragraphs prefer the chat story for familiar songs and fall back to why")
  func playlistParagraph() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let batch = RecommendationBatch(recordedAt: date, host: "Mac", playlist: "Familiar", tracks: [
      RecommendationTrack(artist: "Owned Artist", title: "Known Song", familiar: true, reasons: ["owned"],
        artistKnown: true, why: "A short reason.", story: "The full chat paragraph."),
      RecommendationTrack(artist: "Other Artist", title: "Another Song", familiar: true, reasons: ["owned"],
        artistKnown: true, why: "Only the short reason."),
    ])
    let songs = try #require(PlaylistShelf.make(from: RecommendationLedgerReadResult(
      batches: [batch], skippedLines: 0), now: date, calendar: .current, timeZone: .current).first?.songs)
    #expect(songs[0].familiarity == "In your library")
    #expect(songs[0].paragraph == "The full chat paragraph.")
    #expect(songs[1].paragraph == "Only the short reason.")
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

  @Test("a pre-writeups ledger line decodes without the optional chat fields")
  func legacyLedgerLineCompatibility() throws {
    let line = #"{"format":"vf-recommendation-batch","version":1,"kind":"staged-playlist","source":"chat","recordedAt":"2026-10-30T12:00:00.000Z","host":"Mac","playlist":"Power Pop","tracks":[{"artist":"The Records","title":"Starry Eyes","album":"Shades in Bed","year":1979,"familiar":false,"reasons":[],"artistKnown":true,"why":"A bright chorus.","like":[{"artist":"The Records","title":"Radio Heart","from":"Keepers","found":"library"}]}]}"#
    let result = RecommendationLedgerCodec.readFiles([Data((line + "\n").utf8)])
    let track = try #require(result.batches.first?.tracks.first)
    #expect(result.skippedLines == 0)
    #expect(track.why == "A bright chorus.")
    #expect(track.like == [RecommendationLike(artist: "The Records", title: "Radio Heart",
      from: "Keepers", found: "library")])
    #expect(track.tag == nil)
    #expect(track.details == nil)
    #expect(track.story == nil)
    #expect(track.section == nil)
  }

  @Test("encoding without chat writeups preserves the pre-change track key set")
  func recommendationTrackLegacyKeySet() throws {
    let track = RecommendationTrack(artist: "The Records", title: "Starry Eyes", album: "Shades in Bed",
      year: 1979, familiar: false, reasons: ["owned"], artistKnown: true,
      why: "A bright chorus.",
      like: [RecommendationLike(artist: "Another Artist", title: "Another Song")],
      heardBeforePick: false, picked: true, upload: true)
    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
      host: "Mac", playlist: "Power Pop", tracks: [track])
    let object = try #require(JSONSerialization.jsonObject(with: RecommendationLedgerCodec.encode(batch))
      as? [String: Any])
    let tracks = try #require(object["tracks"] as? [[String: Any]])
    #expect(tracks[0].keys.sorted() == [
      "album", "artist", "artistKnown", "familiar", "heardBeforePick", "like", "picked",
      "reasons", "title", "upload", "why", "year",
    ])
  }

  @Test("staged playlist headers attribute Jon's request only when a description is recorded")
  func playlistRequestHeader() {
    let stagedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let attributed = RecommendationBatch(recordedAt: stagedAt, host: "Mac", playlist: "Selections",
      tracks: [], request: "Find 15 discoveries, please.", description: "Bright songs for late nights.")
    let legacy = RecommendationBatch(recordedAt: stagedAt, host: "Mac", playlist: "Old batch",
      tracks: [], request: "Find 10 songs Jon has not heard.")

    #expect(PlaylistRequestHeader.forBatch(attributed) == .jonWords)
    #expect(PlaylistRequestHeader.forBatch(legacy) == .unattributed)
  }

  @Test("ledger lines decode with and without description")
  func ledgerLineDescriptionCompatibility() throws {
    let stagedAt = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
    let attributed = RecommendationBatch(recordedAt: stagedAt, host: "Jon MBP", playlist: "2023 Selections",
      tracks: [], request: "Find me 15 new discoveries…", description: "Bright new discoveries for the season.")
    let legacy = RecommendationBatch(recordedAt: stagedAt, host: "Jon MBP",
      playlist: "Sam Fender — Manchester 2027 Catch-Up", tracks: [
        RecommendationTrack(artist: "Sam Fender", title: "Fixture Track", familiar: false, reasons: [], artistKnown: true),
      ],
      request: "Find 10 Sam Fender songs Jon has not listened to yet …")
    let ledger = RecommendationLedgerCodec.readFiles([
      try RecommendationLedgerCodec.encode(attributed) + RecommendationLedgerCodec.encode(legacy),
    ])
    let batches = ledger.batches
    #expect(batches.count == 2)
    #expect(batches[0].description == "Bright new discoveries for the season.")
    #expect(PlaylistRequestHeader.forBatch(batches[0]) == .jonWords)
    #expect(batches[1].description == nil)
    #expect(PlaylistRequestHeader.forBatch(batches[1]) == .unattributed)
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
