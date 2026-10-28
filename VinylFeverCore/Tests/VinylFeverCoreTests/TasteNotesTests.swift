import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct TasteNotesTests {
  @Test("question state is derived across hosts, expires, and keeps only three newest open")
  func questionState() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func q(_ id: String, _ age: TimeInterval) -> TasteNote {
      TasteNote(notedAt: now.addingTimeInterval(-age), note: "Which contrast?", source: "chat", kind: "question", id: id,
        about: TasteNote.About(songs: [.init(artist: "A", title: "B")]))
    }
    let old = q("old", 60)
    let a = q("a", 50), b = q("b", 40), c = q("c", 30), d = q("d", 20)
    let answer = TasteNote(notedAt: now, note: "The vocals", source: "chat", kind: "answer", id: "answer", answers: "a")
    let skipped = TasteNote(notedAt: now, note: "not now", source: "chat", kind: "answer", id: "skip", answers: "b", skipped: true)
    let open = TasteNotesCodec.openQuestions(in: [old, a, b, c, d, answer, skipped], now: now)
    #expect(open.map(\.id) == ["d", "c", "old"])
    #expect(!d.isTimeOnly)
    #expect(TasteNotesCodec.openQuestions(in: [q("fourth", 10), q("third", 20), q("second", 30), q("first", 40)], now: now).map(\.id) == ["fourth", "third", "second"])
    #expect(TasteNotesCodec.openQuestions(in: [q("expired", 21 * 86_400)], now: now).isEmpty)
    let acrossHosts = TasteNotesCodec.readFiles([try TasteNotesCodec.encode(a), try TasteNotesCodec.encode(answer)])
    #expect(TasteNotesCodec.openQuestions(in: acrossHosts.notes, now: now).isEmpty)
    let copy = try TasteNotesCodec.encode(d)
    #expect(TasteNotesCodec.readFiles([copy, copy]).notes.count == 1)
    let legacy = Data(#"{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T10:30:35-04:00","title":"White Knight","artist":"Cats in Space","note":"Has a rock opera vibe","source":"current-song"}"#.utf8)
    let read = TasteNotesCodec.readFiles([legacy])
    #expect(read.notes.first?.resolvedKind == "note")
    #expect(read.notes.first?.id == nil)
  }

  @Test("reader handles VF Note line shapes, conflict copies, deduplication and incomplete tails")
  func readsShortcutNotes() throws {
    let whiteKnight = #"{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T10:30:35-04:00","title":"White Knight","artist":"Cats in Space","album":"White Knight - Single","playCount":0,"releaseDate":"2026-10-16T08:00:00-04:00","duration":"4:42","note":"Has a rock opera vibe","source":"current-song","device":"Jon’s iPhone 17 Pro"}"#
    let shack = #"{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T11:30:00-04:00","title":"Natalie's Party","artist":"Shack","album":"HMS Fable","playCount":1,"note":"Great chorus","source":"current-song","device":"Jon’s iPhone 17 Pro"}"#
    let timeOnly = #"{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T10:57:23-04:00","title":"","artist":"","playCount":0,"duration":"00:00","note":"Couldn't catch that","source":"shazam"}"#
    let cancelled = #"{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T10:57:23-04:00","title":"","artist":"","playCount":0,"duration":"00:00","note":"","source":"shazam"}"#
    let future = #"{"format":"vf-taste-note","version":2,"notedAt":"2026-10-22T12:00:00-04:00","title":"Future","artist":"Artist","note":"skip","source":"chat"}"#
    let unknown = #"{"format":"other","version":1,"notedAt":"2026-10-22T12:00:00-04:00","title":"Unknown","artist":"Artist","note":"skip","source":"chat"}"#
    let first = Data((whiteKnight + "\n" + timeOnly + "\n" + cancelled + "\n" + shack + "\n" + future + "\n" + "{\"partial\":" ).utf8)
    let conflict = Data((whiteKnight + "\n" + unknown + "\n").utf8)

    let result = TasteNotesCodec.readFiles([first, conflict])
    #expect(result.filesRead == 2)
    #expect(result.skippedLines == 3)
    #expect(result.notes.count == 3)
    #expect(result.notes.map(\.title) == ["Natalie's Party", "", "White Knight"])
    #expect(result.notes[1].isTimeOnly)
    #expect(result.notes[1].firstHearing == nil)
    #expect(result.notes.last?.note == "Has a rock opera vibe")
    #expect(result.notes.last?.device == "Jon’s iPhone 17 Pro")
    #expect(result.notes.last?.firstHearing == true)
    #expect(TasteNotesCodec.readFiles([Data(whiteKnight.utf8)]).notes.count == 1)
  }

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
