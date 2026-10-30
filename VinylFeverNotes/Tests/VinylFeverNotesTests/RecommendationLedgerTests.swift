import Foundation
import Testing
import VinylFeverNotes

struct RecommendationLedgerTests {
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
