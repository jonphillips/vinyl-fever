import AppIntents
import Foundation
import MusicKit
import UIKit
import VinylFeverNotes

struct WhyThisSongIntent: AppIntent {
  static let title: LocalizedStringResource = "Why This Song"
  static let description = IntentDescription("Hear why Vinyl Fever recommended the current song.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let instant = Date()
    let player = SystemMusicPlayer.shared
    let entry = player.queue.currentEntry
    let currentSong: Song?
    if case let .song(song)? = entry?.item { currentSong = song } else { currentSong = nil }
    let entrySong = entry.map {
      FeedbackSong(title: $0.title, artist: currentSong?.artistName ?? "", album: currentSong?.albumTitle,
        catalogID: currentSong?.id.rawValue)
    }
    var recent: [FeedbackSong] = []
    var recentlyPlayedError: String?
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recent = try await request.response().items.map {
        FeedbackSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch { recentlyPlayedError = error.localizedDescription }
    let playbackStatus = String(describing: player.state.playbackStatus)
    let identification = MusicFeedback.identify(
      entry: entrySong, playbackStatus: playbackStatus, recentlyPlayed: recent
    )
    let selected: FeedbackSong?
    if identification.isTrusted, let entrySong {
      selected = entrySong
    } else {
      let options = identification.choices.map { IntentChoiceOption(title: "\($0.title) by \($0.artist)") }
        + [IntentChoiceOption(title: "None of these")]
      do {
        let choice = try await requestChoice(between: options, dialog: "Which song?")
        let index = options.firstIndex(of: choice)
        selected = index.flatMap { $0 < identification.choices.count ? identification.choices[$0] : nil }
      } catch { return .result(dialog: "No song picked.") }
    }
    guard let selected else { return .result(dialog: "No song picked.") }

    let deviceName = await UIDevice.current.name
    do {
      let result = try ProbeBookmarkStore.withFolder { folder in
        let read = RecommendationLedgerFolderReader.read(folder: folder)
        let answer = WhyThisSong.answer(
          for: selected, ledger: read.ledger, unreadableFileCount: read.unreadableFileCount
        )
        let calendar = Calendar.current
        let text = WhyThisSong.spokenText(
          for: selected, answer: answer, now: instant, calendar: calendar, timeZone: .current
        )
        let batch: RecommendationBatch?
        switch answer {
        case let .withReason(found, _), let .stagedWithoutReason(found, _): batch = found
        case .notRecommended, .recommendationsUnavailable: batch = nil
        }
        let record = ProbeRecord(
          time: instant,
          device: deviceName,
          startedFrom: nil,
          player: ProbeRecord.Player(
            playbackStatus: playbackStatus,
            playbackTime: player.playbackTime.isFinite ? player.playbackTime : nil,
            currentEntry: entry.map {
              ProbeRecord.Entry(title: $0.title, artist: currentSong?.artistName,
                album: currentSong?.albumTitle, catalogID: currentSong?.id.rawValue)
            },
            entryMissing: entry == nil,
            itemMissing: entry != nil && currentSong == nil
          ),
          recentlyPlayed: recent.map {
            ProbeRecord.RecentSong(title: $0.title, artist: $0.artist, catalogID: $0.catalogID ?? "")
          },
          recentlyPlayedError: recentlyPlayedError,
          previousWriteFailure: nil,
          staleReason: identification.staleReason?.rawValue,
          offeredChoices: identification.choices.map { "\($0.title) by \($0.artist)" },
          askedSong: ProbeRecord.Entry(title: selected.title, artist: selected.artist,
            album: selected.album, catalogID: selected.catalogID),
          recommendationAnswerKind: Self.kind(answer),
          recommendationRecordedAt: batch?.recordedAt,
          recommendationPlaylist: batch?.playlist,
          recommendationFilesRead: read.filesRead,
          recommendationFilesUnreadable: read.unreadableFileCount
        )
        let evidenceURL = folder.appendingPathComponent("Probes", isDirectory: true)
          .appendingPathComponent(ProbeRecord.whyFilename(for: deviceName))
        try ProbeLogWriter().write(record, to: evidenceURL)
        return text
      }
      return .result(dialog: IntentDialog(stringLiteral: result))
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      return .result(dialog: "Open Vinyl Fever to grant folder access.")
    } catch {
      return .result(dialog: "The recommendation answer could not be saved: \(error.localizedDescription)")
    }
  }

  private static func kind(_ answer: WhyThisSongAnswer) -> String {
    switch answer {
    case .withReason: "withReason"
    case .stagedWithoutReason: "stagedWithoutReason"
    case .notRecommended: "notRecommended"
    case .recommendationsUnavailable: "recommendationsUnavailable"
    }
  }
}
