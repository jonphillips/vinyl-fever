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
    let song: Song?
    if case let .song(value)? = entry?.item {
      song = value
    } else {
      song = nil
    }

    var recentSongs: [ProbeRecord.RecentSong] = []
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recentSongs = try await request.response().items.map {
        ProbeRecord.RecentSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch {
      // Keep the player snapshot even when recently played is unavailable.
    }

    let filename = ProbeRecord.filename(for: UIDevice.current.name)
    let record = ProbeRecord(
      time: now,
      device: UIDevice.current.name,
      startedFrom: nil,
      player: ProbeRecord.Player(
        playbackStatus: String(describing: player.state.playbackStatus),
        playbackTime: player.playbackTime.isFinite ? player.playbackTime : nil,
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
      folderWriteSucceeded: true,
      folderWriteError: nil
    )

    do {
      let folder = try ProbeBookmarkStore.resolve()
      guard folder.startAccessingSecurityScopedResource() else {
        throw ProbeBookmarkError.folderNotSelected
      }
      defer { folder.stopAccessingSecurityScopedResource() }
      try Self.append(try ProbeRecord.encodeLine(record), to: folder.appendingPathComponent("Probes", isDirectory: true).appendingPathComponent(filename))
      return .result(dialog: "Probe recorded on \(UIDevice.current.name).")
    } catch {
      return .result(dialog: "Probe could not write: \(error.localizedDescription)")
    }
  }

  private static func append(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
      do {
        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
          let handle = try FileHandle(forWritingTo: coordinatedURL)
          defer { try? handle.close() }
          try handle.seekToEnd()
          try handle.write(contentsOf: data)
        } else {
          try data.write(to: coordinatedURL, options: .atomic)
        }
      } catch {
        writeError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
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
