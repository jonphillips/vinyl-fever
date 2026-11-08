import Foundation
import Testing
@testable import VinylFeverNotes

struct PlaylistCreationsTests {
  @Test func createdAndDismissedEventsRoundTripAndLatestWins() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let created = PlaylistCreationEvent(kind: .created, host: "stage-host", recordedAt: at,
      playlist: "Power Pop", at: at.addingTimeInterval(1), writerHost: "Mac",
      musicID: "p.123", songs: 2,
      skipped: [PlaylistCreationSkippedSong(title: "Live Song", artist: "Band", reason: "not-found")])
    let dismissed = PlaylistCreationEvent(kind: .dismissed, host: "stage-host", recordedAt: at,
      playlist: "Power Pop", at: at.addingTimeInterval(2), device: "Phone")
    var bytes = try PlaylistCreationsCodec.encode(created)
    bytes.append(try PlaylistCreationsCodec.encode(dismissed))
    let read = PlaylistCreationsCodec.readFiles([bytes])
    #expect(read.skippedLines == 0)
    #expect(read.events == [created, dismissed])
    #expect(PlaylistCreationsCodec.latestEvents(read.events)[PlaylistCreationsCodec.batchKey(host: "stage-host", recordedAt: at)] == dismissed)
    #expect(String(decoding: try PlaylistCreationsCodec.encode(created), as: UTF8.self) == #"{"at":"2027-01-15T08:00:01.000Z","format":"vf-playlist-creation","host":"stage-host","kind":"created","musicID":"p.123","playlist":"Power Pop","recordedAt":"2027-01-15T08:00:00.000Z","skipped":[{"artist":"Band","reason":"not-found","title":"Live Song"}],"songs":2,"version":1,"writerHost":"Mac"}"# + "\n")
    #expect(String(decoding: try PlaylistCreationsCodec.encode(dismissed), as: UTF8.self) == #"{"at":"2027-01-15T08:00:02.000Z","device":"Phone","format":"vf-playlist-creation","host":"stage-host","kind":"dismissed","playlist":"Power Pop","recordedAt":"2027-01-15T08:00:00.000Z","version":1}"# + "\n")
  }

  @Test func unreadableEventsAreSkippedAndCounted() {
    let read = PlaylistCreationsCodec.readFiles([Data("not json\n".utf8)])
    #expect(read.events.isEmpty)
    #expect(read.skippedLines == 1)
  }

  @Test func batchPairingUsesTheLedgerSecond() {
    let first = Date(timeIntervalSince1970: 1_800_000_000.1)
    let second = Date(timeIntervalSince1970: 1_800_000_000.9)
    #expect(PlaylistCreationsCodec.batchKey(host: "Mac", recordedAt: first)
      == PlaylistCreationsCodec.batchKey(host: "Mac", recordedAt: second))
  }
}
