import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct WhyThisSongRunnerTests {
  @Test func failingEvidenceWriteStillReturnsTheSpokenAnswer() {
    let runner = WhyThisSongRunner(
      folderAccess: { body in try body(URL(fileURLWithPath: "/tmp/vinyl-fever-test")) },
      ledgerReader: { _ in readResult },
      evidenceWriter: { _, _ in throw CocoaError(.fileWriteUnknown) }
    )
    #expect(runner.run(song: song, probe: probe, deviceName: "iPhone", now: epoch,
      calendar: utcCalendar, timeZone: utc) == spokenAnswer)
  }

  @Test func missingBookmarkReturnsTheFolderGrantMessage() {
    let runner = WhyThisSongRunner(folderAccess: { _ in throw ProbeBookmarkError.folderNotSelected })
    #expect(runner.run(song: song, probe: probe, deviceName: "iPhone", now: epoch,
      calendar: utcCalendar, timeZone: utc) == "Open Vinyl Fever to grant folder access.")
  }

  @Test func evidenceLineAndFilenameAreGolden() throws {
    var capturedData: Data?
    var capturedURL: URL?
    let runner = WhyThisSongRunner(
      folderAccess: { body in try body(URL(fileURLWithPath: "/tmp/vinyl-fever-test")) },
      ledgerReader: { _ in readResult },
      evidenceWriter: { record, url in
        capturedData = try ProbeRecord.encodeLine(record)
        capturedURL = url
      }
    )
    #expect(runner.run(song: song, probe: probe, deviceName: "iPhone", now: epoch,
      calendar: utcCalendar, timeZone: utc) == spokenAnswer)
    #expect(capturedURL?.lastPathComponent == "why-iPhone.jsonl")
    let expected = #"{"askedSong":{"artist":"The Records","title":"Starry Eyes"},"device":"iPhone","player":{"entryMissing":true,"itemMissing":false,"playbackStatus":"playing"},"recentlyPlayed":[],"recommendationAnswerKind":"withReason","recommendationFilesRead":2,"recommendationFilesUnreadable":1,"recommendationPlaylist":"Selections","recommendationRecordedAt":"1970-01-01T00:00:00Z","time":"1970-01-01T00:00:00Z"}"# + "\n"
    #expect(String(decoding: try #require(capturedData), as: UTF8.self) == expected)
  }

  private var song: FeedbackSong { FeedbackSong(title: "Starry Eyes", artist: "The Records") }
  private var epoch: Date { Date(timeIntervalSince1970: 0) }
  private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }
  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
  }
  private var readResult: RecommendationLedgerFolderRead {
    let batch = RecommendationBatch(recordedAt: epoch, host: "Mac", playlist: "Selections", tracks: [
      RecommendationTrack(artist: "The Records", title: "Starry Eyes", familiar: false,
        reasons: [], artistKnown: true, why: "A bright hook."),
    ])
    return RecommendationLedgerFolderRead(
      ledger: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
      filesRead: 2,
      unreadableFileCount: 1
    )
  }
  private var probe: ProbeRecord {
    ProbeRecord(
      time: epoch,
      device: "iPhone",
      startedFrom: nil,
      player: ProbeRecord.Player(playbackStatus: "playing", playbackTime: nil,
        currentEntry: nil, entryMissing: true, itemMissing: false),
      recentlyPlayed: [],
      recentlyPlayedError: nil,
      previousWriteFailure: nil
    )
  }
  private var spokenAnswer: String {
    "Starry Eyes by The Records was in Selections, staged January 1. A bright hook."
  }
}
