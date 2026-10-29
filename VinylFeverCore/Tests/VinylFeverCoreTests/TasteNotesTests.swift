import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct TasteNotesTests {
  @Test("time-only notes suggest nearby listening plays, without identifying the note")
  func timeOnlyCandidates() {
    let notedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let poller = UUID()
    let fetch = ListeningFetch(poller: poller, host: "Fixture", fetchedAt: notedAt.addingTimeInterval(4 * 60),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [
        ListeningItem(kind: .song, id: "private-1", title: "Nearby Song", artist: "Artist", album: "Album"),
      ])
    let checkpoint = ListeningFetch(poller: poller, host: "Fixture", fetchedAt: notedAt.addingTimeInterval(12 * 60),
      outcome: .baseline, pagesRead: 1)
    let far = ListeningFetch(poller: poller, host: "Fixture", fetchedAt: notedAt.addingTimeInterval(20 * 60),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [
        ListeningItem(kind: .song, id: "private-2", title: "Far Song", artist: "Other", album: "Other Album"),
      ])
    let log = ListeningLog(streams: [[fetch, checkpoint, far]], now: notedAt.addingTimeInterval(21 * 60))
    let note = TasteNote(notedAt: notedAt, note: "Couldn't catch that", source: "shazam", title: "", artist: "")

    let candidates = TasteNoteCandidates.forNote(note, log: log)
    #expect(candidates.map(\.title) == ["Nearby Song"])
    #expect(TasteNoteCandidates.forNote(TasteNote(notedAt: notedAt, note: "Known", source: "current-song", title: "Known", artist: "Artist"), log: log).isEmpty)
    #expect(!TasteNote(notedAt: notedAt, note: "Playlist note", source: "chat", playlist: "Selections").isTimeOnly)
    #expect(!String(describing: candidates).contains("private-1"))
  }
}
