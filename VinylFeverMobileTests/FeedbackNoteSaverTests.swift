import Foundation
import Testing
@testable import VinylFeverMobile
import VinylFeverNotes

struct FeedbackNoteSaverTests {
  @Test(arguments: [ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused])
  func missingFolderAccessReturnsGrantMessageWithoutWriting(error: ProbeBookmarkError) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let dialog = FeedbackNoteSaver.save(note: note(), evidence: evidence(), deviceName: "iPad", defaults: defaults) { _ in
      throw error
    }

    #expect(dialog == FeedbackNoteSaver.folderGrantMessage)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    #expect(FeedbackLastNote.load(defaults: defaults) == nil)
  }

  @Test func successWritesOneNoteAndOneEvidenceLineAndUpdatesLastNote() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let dialog = FeedbackNoteSaver.save(note: note(), evidence: evidence(), deviceName: "Jon’s iPad", defaults: defaults) { write in
      try write(root)
    }
    let noteURL = root.appendingPathComponent("Taste Intelligence/notes-feedback-Jon_s_iPad.jsonl")
    let evidenceURL = root.appendingPathComponent("Probes/feedback-Jon-s-iPad.jsonl")

    #expect(dialog == FeedbackNoteSaver.savedMessage)
    #expect(try nonemptyLineCount(at: noteURL) == 1)
    #expect(try nonemptyLineCount(at: evidenceURL) == 1)
    #expect(TasteNotesCodec.readFiles([try Data(contentsOf: noteURL)]).notes == [note()])
    #expect(FeedbackLastNote.load(defaults: defaults)?.title == "Song")
  }

  @Test func evidenceFailureKeepsTheSavedNoteAndReportsTheDiagnosticFailure() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let (defaults, suiteName) = testDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try Data("blocker".utf8).write(to: root.appendingPathComponent("Probes"))

    let dialog = FeedbackNoteSaver.save(note: note(), evidence: evidence(), deviceName: "iPad", defaults: defaults) { write in
      try write(root)
    }
    let noteURL = root.appendingPathComponent("Taste Intelligence/notes-feedback-iPad.jsonl")

    #expect(dialog == FeedbackNoteSaver.evidenceFailureMessage)
    #expect(try nonemptyLineCount(at: noteURL) == 1)
    #expect(FeedbackLastNote.load(defaults: defaults)?.title == "Song")
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func testDefaults() -> (UserDefaults, String) {
    let suiteName = UUID().uuidString
    return (UserDefaults(suiteName: suiteName)!, suiteName)
  }

  private func note() -> TasteNote {
    TasteNote(notedAt: Date(timeIntervalSince1970: 0), note: "Like it", source: "now-playing", title: "Song", artist: "Band")
  }

  private func evidence() -> ProbeRecord {
    ProbeRecord(
      time: Date(timeIntervalSince1970: 0), device: "iPad", startedFrom: nil,
      player: ProbeRecord.Player(playbackStatus: "playing", playbackTime: nil, currentEntry: nil, entryMissing: true, itemMissing: false),
      recentlyPlayed: [], recentlyPlayedError: nil, previousWriteFailure: nil
    )
  }

  private func nonemptyLineCount(at url: URL) throws -> Int {
    try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).count
  }
}
