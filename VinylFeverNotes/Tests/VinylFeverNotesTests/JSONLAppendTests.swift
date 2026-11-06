import Foundation
import Testing
import VinylFeverNotes

struct JSONLAppendTests {
  @Test("creates missing folders and files, then appends without replacing bytes")
  func createsAndAppends() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "recommendations/Jon_MBP.jsonl")
    try JSONLAppend.append(Data("first\n".utf8), to: url)
    try JSONLAppend.append(Data("second\n".utf8), to: url)
    #expect(try String(contentsOf: url, encoding: .utf8) == "first\nsecond\n")
  }

  @Test("wraps folder and target failures with a short path and the failing step")
  func describesFailures() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let folderFile = root.appending(path: "Taste Intelligence/recommendations")
    try FileManager.default.createDirectory(at: folderFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: folderFile)
    let folderTarget = folderFile.appending(path: "Jon_MBP.jsonl")
    do {
      try JSONLAppend.append(Data("line\n".utf8), to: folderTarget)
      Issue.record("append should fail when its parent path is a file")
    } catch {
      #expect(error.localizedDescription.contains("recommendations/Jon_MBP.jsonl (create folder)"))
      #expect(!error.localizedDescription.contains(root.path))
    }

    let target = root.appending(path: "recommendations/Jon_MBP.jsonl", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    do {
      try JSONLAppend.append(Data("line\n".utf8), to: target)
      Issue.record("append should fail when the target is a directory")
    } catch {
      #expect(error.localizedDescription.contains("recommendations/Jon_MBP.jsonl (write)"))
      #expect(!error.localizedDescription.contains(root.path))
    }
  }

  @Test("note, recommendation, and review codecs append readable versioned lines")
  func codecsAppend() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = TasteNote(notedAt: Date(timeIntervalSince1970: 1_800_000_000), note: "A note", source: "chat")
    try TasteNotesCodec.append(note, to: root.appending(path: "notes/Jon.jsonl"))
    #expect(TasteNotesCodec.readFiles([try Data(contentsOf: root.appending(path: "notes/Jon.jsonl"))]).notes == [note])

    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 1_800_000_000), host: "Mac",
      tracks: [RecommendationTrack(artist: "Artist", title: "Song", familiar: false, reasons: [], artistKnown: false)])
    try RecommendationLedgerCodec.append(batch, host: "Mac", folder: root.appending(path: "recommendations"))
    #expect(RecommendationLedgerCodec.readFiles([try Data(contentsOf: root.appending(path: "recommendations/Mac.jsonl"))]).batches == [batch])

    let review = PlaylistReviewEntry(source: .chat, kind: .review, host: "Mac", recordedAt: batch.recordedAt,
      playlistID: "Mac|1", playlist: "Playlist", at: batch.recordedAt, text: "A review",
      heard: 0, kept: 0, passed: 0, unheard: 0)
    try PlaylistReviewsCodec.append(review, writer: "chat-Mac", folder: root.appending(path: "reviews"))
    #expect(PlaylistReviewsCodec.readFiles([try Data(contentsOf: root.appending(path: "reviews/chat-Mac.jsonl"))]).entries == [review])
  }
}
