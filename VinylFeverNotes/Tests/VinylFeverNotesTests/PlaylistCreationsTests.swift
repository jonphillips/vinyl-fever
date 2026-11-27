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

  @Test func needsReviewIsReadableAndUnknownKindsDoNotHideLaterEvents() throws {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let review = PlaylistCreationEvent(kind: .needsReview, host: "stage-host", recordedAt: at,
      playlist: "Power Pop", at: at, writerHost: "Mac",
      skipped: [PlaylistCreationSkippedSong(title: "Unreleased Song", artist: "Band", reason: "not-found")])
    var bytes = Data(#"{"at":"2027-01-15T08:00:00.000Z","format":"vf-playlist-creation","host":"stage-host","kind":"future-kind","playlist":"Power Pop","recordedAt":"2027-01-15T08:00:00.000Z","version":1,"writerHost":"Mac"}"#.utf8)
    bytes.append(0x0A)
    bytes.append(try PlaylistCreationsCodec.encode(review))

    let read = PlaylistCreationsCodec.readFiles([bytes])
    #expect(read.skippedLines == 0)
    #expect(read.unknownKindCount == 1)
    #expect(read.events == [review])
  }

  @Test func terminalEventsOutrankLaterNeedsReviewAndReviewCanExpireIntoArchive() {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let created = PlaylistCreationEvent(kind: .created, host: "Mac", recordedAt: at,
      playlist: "Power Pop", at: at, writerHost: "Mac", musicID: "p.1", songs: 1, skipped: [])
    let laterReview = PlaylistCreationEvent(kind: .needsReview, host: "Mac", recordedAt: at,
      playlist: "Power Pop", at: at.addingTimeInterval(5), writerHost: "Mac",
      skipped: [PlaylistCreationSkippedSong(title: "Song", artist: "Band", reason: "not-found")])
    #expect(PlaylistCreationsCodec.latestEvents([created, laterReview])[
      PlaylistCreationsCodec.batchKey(host: "Mac", recordedAt: at)] == created)

    let batch = RecommendationBatch(recordedAt: at, host: "Mac", playlist: "Power Pop", tracks: [])
    let playlists = PlaylistShelf.make(from: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
      now: at.addingTimeInterval(PlaylistArchive.gracePeriod + 1), calendar: .current, timeZone: .current)
    #expect(PlaylistArchive.archivedPlaylistIDs(from: playlists, libraryPlaylistNames: [],
      creations: [laterReview], now: at.addingTimeInterval(PlaylistArchive.gracePeriod + 1)).contains(playlists[0].id))
  }

  @Test func batchPairingUsesTheLedgerSecond() {
    let first = Date(timeIntervalSince1970: 1_800_000_000.1)
    let second = Date(timeIntervalSince1970: 1_800_000_000.9)
    #expect(PlaylistCreationsCodec.batchKey(host: "Mac", recordedAt: first)
      == PlaylistCreationsCodec.batchKey(host: "Mac", recordedAt: second))
  }
}
