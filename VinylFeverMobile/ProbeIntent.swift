import AppIntents
import Foundation
import MusicKit
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
      let folder = try ProbeBookmarkStore.resolve()
      guard folder.startAccessingSecurityScopedResource() else {
        throw ProbeBookmarkError.accessRefused
      }
      defer { folder.stopAccessingSecurityScopedResource() }
      try ProbeLogWriter().write(
        record,
        to: folder.appendingPathComponent("Probes", isDirectory: true).appendingPathComponent(filename)
      )
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
  }
}
