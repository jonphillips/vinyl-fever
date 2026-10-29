import Foundation
import VinylFeverNotes

enum FeedbackNoteSaver {
  typealias FolderAccess = ((URL) throws -> Bool) throws -> Bool

  static let folderGrantMessage = "Open Vinyl Fever to grant folder access."
  static let savedMessage = "Saved your note."
  static let evidenceFailureMessage = "Saved your note, but couldn't save its diagnostic record."

  static func save(
    note: TasteNote,
    evidence: ProbeRecord,
    deviceName: String,
    defaults: UserDefaults = .standard,
    folderAccess: FolderAccess
  ) -> String {
    do {
      let evidenceWritten = try folderAccess { folder in
        let notesFolder = folder.appendingPathComponent("Taste Intelligence", isDirectory: true)
        try TasteNotesCodec.appendFeedbackNote(note, device: deviceName, folder: notesFolder)
        do {
          let evidenceURL = folder.appendingPathComponent("Probes", isDirectory: true)
            .appendingPathComponent(ProbeRecord.feedbackFilename(for: deviceName))
          try ProbeLogWriter(defaults: defaults).write(evidence, to: evidenceURL)
          return true
        } catch {
          return false
        }
      }
      FeedbackLastNote.save(note: note, defaults: defaults)
      return evidenceWritten ? savedMessage : evidenceFailureMessage
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      return folderGrantMessage
    } catch {
      return "The note could not be saved: \(error.localizedDescription)"
    }
  }
}

struct FeedbackLastNote: Codable {
  var title: String?
  var artist: String?
  var notedAt: Date
  var source: String

  static func save(note: TasteNote, defaults: UserDefaults = .standard) {
    let value = FeedbackLastNote(title: note.title, artist: note.artist, notedAt: note.notedAt, source: note.source)
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "feedback-last-note") }
  }

  static func load(defaults: UserDefaults = .standard) -> FeedbackLastNote? {
    guard let data = defaults.data(forKey: "feedback-last-note") else { return nil }
    return try? JSONDecoder().decode(FeedbackLastNote.self, from: data)
  }
}
