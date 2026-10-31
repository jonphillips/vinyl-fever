import Dependencies
import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistTasteNotesModelTests {
  @Test @MainActor
  func savesOneCoordinatedLineAndShowsItUnderTheSong() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let tasteFolder = root.appendingPathComponent("Taste Intelligence", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let saveCount = SaveCounter()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 1_800_000_000.123456)
      dependencies.playlistTasteNotesClient.deviceName = { "Test iPhone" }
      dependencies.playlistTasteNotesClient.save = { note, device in
        await saveCount.increment()
        try TasteNotesCodec.appendFeedbackNote(note, device: device, folder: tasteFolder)
      }
    }) { PlaylistTasteNotesModel() }

    let song = playlistSong()
    model.noteButtonTapped(for: song, resolvedSong: nil)
    model.draft = "  The chorus opens up.  "
    await model.save()

    #expect(await saveCount.value == 1)
    let file = tasteFolder.appendingPathComponent("notes-feedback-Test_iPhone.jsonl")
    let loaded = TasteNotesCodec.readFiles([try Data(contentsOf: file)])
    #expect(loaded.notes.count == 1)
    #expect(loaded.notes.first?.source == "playlist")
    #expect(loaded.notes.first?.note == "  The chorus opens up.  ")
    #expect(model.notes(for: song).map(\.note) == ["  The chorus opens up.  "])
    #expect(model.destination == nil)
  }

  @Test @MainActor
  func emptyAndCancelTextWriteNothing() async {
    let saveCount = SaveCounter()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 100)
      dependencies.playlistTasteNotesClient.deviceName = { "Test" }
      dependencies.playlistTasteNotesClient.save = { _, _ in await saveCount.increment() }
    }) { PlaylistTasteNotesModel() }
    let song = playlistSong()

    model.noteButtonTapped(for: song, resolvedSong: nil)
    await model.save()
    model.noteButtonTapped(for: song, resolvedSong: nil)
    model.draft = "Cancel, cancel!"
    await model.save()

    #expect(await saveCount.value == 0)
    #expect(model.notes.isEmpty)
    #expect(model.destination == nil)
  }

  @Test @MainActor
  func noBookmarkShowsFolderGrantMessageAndWritesNothing() async {
    let saveCount = SaveCounter()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 100)
      dependencies.playlistTasteNotesClient.deviceName = { "Test" }
      dependencies.playlistTasteNotesClient.save = { _, _ in
        await saveCount.increment()
        throw ProbeBookmarkError.folderNotSelected
      }
    }) { PlaylistTasteNotesModel() }
    model.noteButtonTapped(for: playlistSong(), resolvedSong: nil)
    model.draft = "A real note."
    await model.save()

    #expect(await saveCount.value == 1)
    #expect(model.errorMessage == FeedbackNoteSaver.folderGrantMessage)
    #expect(model.destination == .note)
  }

  @Test @MainActor
  func noteSavedDuringInFlightRefreshStaysShown() async {
    let gate = TasteNotesReadGate()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 1_800_000_000.123456)
      dependencies.playlistTasteNotesClient.read = { await gate.read() }
      dependencies.playlistTasteNotesClient.deviceName = { "Test" }
      dependencies.playlistTasteNotesClient.save = { _, _ in }
    }) { PlaylistTasteNotesModel() }

    let refresh = Task { await model.refresh() }
    await gate.waitUntilReadStarts()
    let song = playlistSong()
    model.noteButtonTapped(for: song, resolvedSong: nil)
    model.draft = "Saved during refresh."
    await model.save()
    await gate.resume(with: emptyRead())
    await refresh.value

    #expect(model.notes(for: song).map(\.note) == ["Saved during refresh."])
  }

  @Test @MainActor
  func savedNoteIsNotDuplicatedByLaterRefresh() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 1_800_000_000.123456)
      dependencies.playlistTasteNotesClient.deviceName = { "Test iPhone" }
      dependencies.playlistTasteNotesClient.save = { note, device in
        try TasteNotesCodec.appendFeedbackNote(
          note, device: device, folder: root.appendingPathComponent("Taste Intelligence", isDirectory: true)
        )
      }
      dependencies.playlistTasteNotesClient.read = { PlaylistTasteNotesFolderReader.read(folder: root) }
    }) { PlaylistTasteNotesModel() }

    let song = playlistSong()
    model.noteButtonTapped(for: song, resolvedSong: nil)
    model.draft = "A note saved with fractional time."
    await model.save()
    await model.refresh()

    #expect(model.notes(for: song).count == 1)
    #expect(model.notes(for: song).first?.note == "A note saved with fractional time.")
  }

  @Test @MainActor
  func readsNotesFromMultipleFilesNewestFirst() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let folder = root.appendingPathComponent("Taste Intelligence", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let older = TasteNote(notedAt: Date(timeIntervalSince1970: 1), note: "Older.", source: "picked", title: "Song", artist: "Artist")
    let newer = TasteNote(notedAt: Date(timeIntervalSince1970: 2), note: "Newer.", source: "shortcut", title: "Song", artist: "Artist")
    try TasteNotesCodec.encode(older).write(to: folder.appendingPathComponent("notes-feedback-phone.jsonl"))
    try TasteNotesCodec.encode(newer).write(to: folder.appendingPathComponent("notes-chat-mac.jsonl"))

    let read = PlaylistTasteNotesFolderReader.read(folder: root)
    #expect(read.totalFileCount == 2)
    #expect(read.unreadableFileCount == 0)
    #expect(PlaylistTasteNotes.matching(read.result.notes, title: "Song", artist: "Artist").map(\.note) == ["Newer.", "Older."])
  }

  private func playlistSong() -> PlaylistShelfSong {
    PlaylistShelfSong(id: "one", title: "Song", artist: "Artist", album: "Ledger Album", year: 2023,
      familiarity: "New", why: "A reason.", like: [])
  }

  private func emptyRead() -> PlaylistTasteNotesFolderRead {
    PlaylistTasteNotesFolderRead(
      result: TasteNotesCodec.readFiles([]), unreadableFileCount: 0, totalFileCount: 0
    )
  }
}

private actor SaveCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

private actor TasteNotesReadGate {
  private var continuation: CheckedContinuation<PlaylistTasteNotesFolderRead, Never>?
  private var didStartRead = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func read() async -> PlaylistTasteNotesFolderRead {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      didStartRead = true
      startWaiters.forEach { $0.resume() }
      startWaiters.removeAll()
    }
  }

  func waitUntilReadStarts() async {
    guard !didStartRead else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resume(with result: PlaylistTasteNotesFolderRead) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}
