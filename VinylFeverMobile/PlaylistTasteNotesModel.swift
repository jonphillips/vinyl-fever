import Dependencies
import DependenciesMacros
import Foundation
import MusicKit
import Observation
import UIKit
import VinylFeverNotes

@DependencyClient
struct PlaylistTasteNotesClient {
  var read: @Sendable () async throws -> PlaylistTasteNotesFolderRead
  var save: @Sendable (TasteNote, String) async throws -> Void
  var deviceName: @Sendable () async -> String = { "device" }
}

extension PlaylistTasteNotesClient: TestDependencyKey {
  static var testValue: Self { Self() }
}

private enum PlaylistTasteNotesClientKey: DependencyKey {
  static let liveValue = PlaylistTasteNotesClient(
    read: {
      try await Task.detached {
        try ProbeBookmarkStore.withFolder { folder in PlaylistTasteNotesFolderReader.read(folder: folder) }
      }.value
    },
    save: { note, device in
      try ProbeBookmarkStore.withFolder { folder in
        let tasteFolder = folder.appendingPathComponent("Taste Intelligence", isDirectory: true)
        try TasteNotesCodec.appendFeedbackNote(note, device: device, folder: tasteFolder)
      }
    },
    deviceName: { await MainActor.run { UIDevice.current.name } }
  )
}

extension DependencyValues {
  var playlistTasteNotesClient: PlaylistTasteNotesClient {
    get { self[PlaylistTasteNotesClientKey.self] }
    set { self[PlaylistTasteNotesClientKey.self] = newValue }
  }
}

@MainActor
@Observable
final class PlaylistTasteNotesModel {
  enum Destination: Hashable, Identifiable {
    case note
    var id: Self { self }
  }

  private(set) var notes: [TasteNote] = []
  private(set) var hasUnreadableFiles = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var errorMessage: String?
  var destination: Destination?
  var draft = ""
  private(set) var currentSong: FeedbackSong?
  private var sessionSavedNotes: [TasteNote] = []

  @ObservationIgnored
  @Dependency(\.playlistTasteNotesClient) private var client
  @ObservationIgnored
  @Dependency(\.date.now) private var now

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let read = try await client.read()
      notes = TasteNotesCodec.uniqueNewestFirst(read.result.notes + sessionSavedNotes)
      hasUnreadableFiles = read.totalFileCount > 0 && read.unreadableFileCount > 0
      errorMessage = nil
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      notes = TasteNotesCodec.uniqueNewestFirst(sessionSavedNotes)
      hasUnreadableFiles = false
      errorMessage = nil
    } catch {
      hasUnreadableFiles = true
      errorMessage = error.localizedDescription
    }
  }

  func notes(for song: PlaylistShelfSong) -> [TasteNote] {
    PlaylistTasteNotes.matching(notes, title: song.title, artist: song.artist)
  }

  func noteButtonTapped(for song: PlaylistShelfSong, resolvedSong: Song?) {
    currentSong = FeedbackSong(
      title: song.title,
      artist: song.artist,
      album: song.album,
      catalogID: resolvedSong?.id.rawValue,
      playCount: resolvedSong?.playCount,
      releaseDate: resolvedSong?.releaseDate.map { ISO8601DateFormatter().string(from: $0) },
      duration: resolvedSong?.duration.map(Self.durationString)
    )
    draft = ""
    errorMessage = nil
    destination = .note
  }

  func cancel() {
    guard !isSaving else { return }
    destination = nil
    currentSong = nil
    draft = ""
  }

  func save() async {
    guard !isSaving else { return }
    guard let note = MusicFeedback.makeNote(draft, selected: currentSong, source: "playlist", at: now,
      device: await client.deviceName()) else {
      cancel()
      return
    }
    isSaving = true
    defer { isSaving = false }
    do {
      try await client.save(note, note.device ?? "device")
      sessionSavedNotes.append(note)
      notes = TasteNotesCodec.uniqueNewestFirst(notes + [note])
      destination = nil
      currentSong = nil
      draft = ""
      errorMessage = nil
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      errorMessage = FeedbackNoteSaver.folderGrantMessage
    } catch {
      errorMessage = "The note could not be saved: \(error.localizedDescription)"
    }
  }

  private static func durationString(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.rounded()))
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }
}
