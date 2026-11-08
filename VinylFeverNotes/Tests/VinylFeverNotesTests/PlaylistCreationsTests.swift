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
