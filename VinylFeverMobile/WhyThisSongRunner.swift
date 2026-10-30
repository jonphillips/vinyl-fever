import Foundation
import VinylFeverNotes

struct WhyThisSongRunner {
  typealias FolderAccess = ((URL) throws -> String) throws -> String

  var folderAccess: FolderAccess = { body in try ProbeBookmarkStore.withFolder(body) }
  var ledgerReader: (URL) -> RecommendationLedgerFolderRead = { RecommendationLedgerFolderReader.read(folder: $0) }
  var evidenceWriter: (ProbeRecord, URL) throws -> Void = { record, url in
    try ProbeLogWriter().write(record, to: url)
  }

  func run(
    song: FeedbackSong,
    probe: ProbeRecord,
    deviceName: String,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) -> String {
    do {
      return try folderAccess { folder in
        let read = ledgerReader(folder)
        let answer = WhyThisSong.answer(
          for: song, ledger: read.ledger, unreadableFileCount: read.unreadableFileCount
        )
        let text = WhyThisSong.spokenText(
          for: song, answer: answer, now: now, calendar: calendar, timeZone: timeZone
        )
        let batch: RecommendationBatch?
        switch answer {
        case let .withReason(found, _), let .stagedWithoutReason(found, _), let .notPicked(found, _):
          batch = found
        case .notRecommended, .recommendationsUnavailable:
          batch = nil
        }
        var evidence = probe
        evidence.askedSong = ProbeRecord.Entry(
          title: song.title, artist: song.artist, album: song.album, catalogID: song.catalogID
        )
        evidence.recommendationAnswerKind = Self.kind(answer)
        evidence.recommendationRecordedAt = batch?.recordedAt
        evidence.recommendationPlaylist = batch?.playlist
        evidence.recommendationFilesRead = read.filesRead
        evidence.recommendationFilesUnreadable = read.unreadableFileCount
        let evidenceURL = folder.appendingPathComponent("Probes", isDirectory: true)
          .appendingPathComponent(ProbeRecord.whyFilename(for: deviceName))
        try? evidenceWriter(evidence, evidenceURL)
        return text
      }
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      return "Open Vinyl Fever to grant folder access."
    } catch {
      return "Open Vinyl Fever to grant folder access."
    }
  }

  private static func kind(_ answer: WhyThisSongAnswer) -> String {
    switch answer {
    case .withReason: "withReason"
    case .stagedWithoutReason: "stagedWithoutReason"
    case .notPicked: "notPicked"
    case .notRecommended: "notRecommended"
    case .recommendationsUnavailable: "recommendationsUnavailable"
    }
  }
}
