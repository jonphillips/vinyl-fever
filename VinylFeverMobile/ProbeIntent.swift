import AppIntents
import Foundation
import MusicKit
import VinylFeverNotes
import UIKit

struct VinylFeverProbeIntent: AppIntent {
  static let title: LocalizedStringResource = "Vinyl Fever Probe"
  static let description = IntentDescription("Record what MusicKit reports about the current song.")
  static let openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let now = Date()
    let player = SystemMusicPlayer.shared
    let entry = player.queue.currentEntry
    let playbackStatus = String(describing: player.state.playbackStatus)
    let playbackTime = player.playbackTime.isFinite ? player.playbackTime : nil
    let song: Song?
    if case let .song(value)? = entry?.item {
      song = value
    } else {
      song = nil
    }
    let deviceName = await UIDevice.current.name

    var recentSongs: [ProbeRecord.RecentSong] = []
    var recentlyPlayedError: String?
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recentSongs = try await request.response().items.map {
        ProbeRecord.RecentSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch {
      recentlyPlayedError = error.localizedDescription
    }

    let filename = ProbeRecord.filename(for: deviceName)
    let record = ProbeRecord(
      time: now,
      device: deviceName,
      startedFrom: nil,
      player: ProbeRecord.Player(
        playbackStatus: playbackStatus,
        playbackTime: playbackTime,
        currentEntry: entry.map {
          ProbeRecord.Entry(
            title: $0.title,
            artist: song?.artistName,
            album: song?.albumTitle,
            catalogID: song?.id.rawValue
          )
        },
        entryMissing: entry == nil,
        itemMissing: entry != nil && song == nil
      ),
      recentlyPlayed: recentSongs,
      recentlyPlayedError: recentlyPlayedError,
      previousWriteFailure: nil
    )

    do {
      _ = try ProbeBookmarkStore.withFolder { folder in
        try ProbeLogWriter().write(
          record,
          to: folder.appendingPathComponent("Probes", isDirectory: true).appendingPathComponent(filename)
        )
      }
      return .result(dialog: "Probe recorded on \(deviceName).")
    } catch {
      ProbeLogWriter.saveFailure(time: now, error: error.localizedDescription)
      return .result(dialog: "Probe could not write: \(error.localizedDescription)")
    }
  }
}

struct VinylFeverShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: VinylFeverProbeIntent(),
      phrases: ["Run a probe in \(.applicationName)"],
      shortTitle: "Probe",
      systemImageName: "waveform.path"
    )
    AppShortcut(
      intent: MusicFeedbackIntent(),
      phrases: ["Music Feedback in \(.applicationName)"],
      shortTitle: "Music Feedback",
      systemImageName: "waveform"
    )
  }
}

struct MusicFeedbackIntent: AppIntent {
  static let title: LocalizedStringResource = "Music Feedback"
  static let description = IntentDescription("Save your thoughts about the song you are hearing.")
  static let openAppWhenRun = false

  @Parameter(title: "Note") var note: String?

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let instant = Date()
    let player = SystemMusicPlayer.shared
    let entry = player.queue.currentEntry
    let currentSong: Song?
    if case let .song(song)? = entry?.item { currentSong = song } else { currentSong = nil }
    let playbackStatus = String(describing: player.state.playbackStatus)
    let entrySong = entry.map {
      FeedbackSong(
        title: $0.title,
        artist: currentSong?.artistName ?? "",
        album: currentSong?.albumTitle,
        catalogID: currentSong?.id.rawValue,
        playCount: currentSong?.playCount,
        releaseDate: currentSong?.releaseDate.map { ISO8601DateFormatter().string(from: $0) },
        duration: currentSong?.duration.map(Self.durationString)
      )
    }

    var recent: [FeedbackSong] = []
    var recentlyPlayedError: String?
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recent = try await request.response().items.map {
        FeedbackSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch {
      recentlyPlayedError = error.localizedDescription
    }
    let identification = MusicFeedback.identify(entry: entrySong, playbackStatus: playbackStatus, recentlyPlayed: recent)
    let deviceName = await UIDevice.current.name

    let selected: FeedbackSong?
    let source: String
    if identification.isTrusted, let entrySong {
      selected = entrySong
      source = "now-playing"
    } else {
      let options = identification.choices.map { IntentChoiceOption(title: "\($0.title) by \($0.artist)") }
        + [IntentChoiceOption(title: "None of these")]
      let option: IntentChoiceOption
      do {
        option = try await requestChoice(between: options, dialog: "Which song?")
      } catch {
        return .result(dialog: "No note saved.")
      }
      let selectedIndex = options.firstIndex(of: option)
      selected = selectedIndex.flatMap { $0 < identification.choices.count ? identification.choices[$0] : nil }
      source = selected == nil ? "time-only" : "picked"
    }

    let prompt: IntentDialog
    if source == "now-playing", let selected {
      prompt = "What do you think of \(selected.title) by \(selected.artist)?"
    } else {
      prompt = "What do you think?"
    }
    let dictatedNote: String
    do {
      dictatedNote = try await $note.requestValue(prompt)
    } catch {
      return .result(dialog: "No note saved.")
    }
    guard let tasteNote = MusicFeedback.makeNote(
      dictatedNote, selected: selected, source: source, at: instant, device: deviceName
    ) else {
      return .result(dialog: "No note saved.")
    }

    do {
      let evidenceWritten = try ProbeBookmarkStore.withFolder { folder in
        let notesFolder = folder.appendingPathComponent("Taste Intelligence", isDirectory: true)
        try TasteNotesCodec.appendFeedbackNote(tasteNote, device: deviceName, folder: notesFolder)
        let record = ProbeRecord(
          time: instant,
          device: deviceName,
          startedFrom: nil,
          player: ProbeRecord.Player(
            playbackStatus: playbackStatus,
            playbackTime: player.playbackTime.isFinite ? player.playbackTime : nil,
            currentEntry: entry.map {
              ProbeRecord.Entry(title: $0.title, artist: currentSong?.artistName, album: currentSong?.albumTitle, catalogID: currentSong?.id.rawValue)
            },
            entryMissing: entry == nil,
            itemMissing: entry != nil && currentSong == nil
          ),
          recentlyPlayed: recent.map { ProbeRecord.RecentSong(title: $0.title, artist: $0.artist, catalogID: $0.catalogID ?? "") },
          recentlyPlayedError: recentlyPlayedError,
          previousWriteFailure: nil,
          staleReason: identification.staleReason?.rawValue,
          offeredChoices: identification.choices.map { "\($0.title) by \($0.artist)" },
          savedSong: selected.map { ProbeRecord.Entry(title: $0.title, artist: $0.artist, album: $0.album, catalogID: $0.catalogID) }
        )
        do {
          try ProbeLogWriter().write(record, to: folder.appendingPathComponent("Probes", isDirectory: true)
            .appendingPathComponent(ProbeRecord.feedbackFilename(for: deviceName)))
          return true
        } catch {
          return false
        }
      }
      FeedbackLastNote.save(note: tasteNote)
      return .result(dialog: evidenceWritten ? "Saved your note." : "Saved your note, but couldn't save its diagnostic record.")
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      return .result(dialog: "Open Vinyl Fever to grant folder access.")
    } catch {
      return .result(dialog: "The note could not be saved: \(error.localizedDescription)")
    }
  }

  private static func durationString(_ duration: TimeInterval) -> String {
    let seconds = Int(duration.rounded())
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
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
