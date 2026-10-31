import Dependencies
import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistProgressModelTests {
  @Test
  func listeningLogReaderLoadsEligiblePollerMonths() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fetchedAt = Date(timeIntervalSince1970: 1_798_732_800) // 2026-12-01 UTC
    let fetch = ListeningFetch(poller: UUID(), host: "Mac", fetchedAt: fetchedAt, outcome: .plays,
      newCount: 1, pagesRead: 1, items: [.init(kind: .song, id: "one", title: "Song", artist: "Artist")])
    let stream = root.appending(path: "Listening/fetches/one", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
    let logData = try ListeningLogCodec.encode(fetch)
    try Data().write(to: stream.appendingPathComponent(".2026-12.jsonl.icloud"))

    let plays = try PlaylistListeningLogReader.read(folder: root, from: Date(timeIntervalSince1970: 1_798_732_800),
      now: Date(timeIntervalSince1970: 1_801_411_200), startDownload: { _ in }, coordinatedRead: {
        guard $0.lastPathComponent == "2026-12.jsonl" else { throw CocoaError(.fileNoSuchFile) }
        return logData
      })
    #expect(plays.count == 1)
    #expect(plays.first?.item.id == "one")
  }

  @Test @MainActor
  func refreshBuildsStatusesAndACompleteBarFromTheReads() async {
    let playlist = fixture()
    let model = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = {
        [KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers")]
      }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.tracks = { _ in [KeepLibraryTrack(title: "Kept", artist: "Artist")] }
      dependencies.playlistTasteNotesClient.read = { emptyNotes() }
      dependencies.playlistListeningLogClient.read = { _, _ in [play("Played", end: 101)] }
    }) { PlaylistProgressModel() }

    await model.refresh([playlist])

    let progress = model.results[playlist.id]
    #expect(model.isAvailable)
    #expect(progress?.songs["kept"] == .kept(in: ["Vinyl Fever Keepers"]))
    #expect(progress?.songs["played"] == .passed(withFeedback: false))
    #expect(progress?.songs["unheard"] == .notHeard)
    #expect(progress?.counts == PlaylistProgressCounts(kept: 1, passedWithFeedback: 0, passedWithoutFeedback: 1, notHeard: 1))
  }

  @Test @MainActor
  func savedNoteAndKeepRecomputeTheSongAndPlaylistCounts() async {
    let playlist = fixture()
    let model = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = {
        [KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers")]
      }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.tracks = { _ in [] }
      dependencies.playlistTasteNotesClient.read = { emptyNotes() }
      dependencies.playlistListeningLogClient.read = { _, _ in [] }
    }) { PlaylistProgressModel() }
    await model.refresh([playlist])
    model.updateSavedNotes([TasteNote(notedAt: date(101), note: "Loved it", source: "playlist", title: "Unheard", artist: "Artist")])

    #expect(model.results[playlist.id]?.songs["unheard"] == .passed(withFeedback: true))
    #expect(model.results[playlist.id]?.counts.passedWithFeedback == 1)
    model.updateSavedKeeps(["played": ["Vinyl Fever Keepers"]])
    #expect(model.results[playlist.id]?.songs["played"] == .kept(in: ["Vinyl Fever Keepers"]))
    #expect(model.results[playlist.id]?.counts.kept == 1)
    #expect(model.results[playlist.id]?.counts.songCount == 3)
  }

  @Test @MainActor
  func unavailableEvidenceHidesEveryStatus() async {
    let playlist = fixture()
    let denied = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { false }
    }) { PlaylistProgressModel() }
    await denied.refresh([playlist])
    #expect(!denied.isAvailable)
    #expect(denied.results.isEmpty)

    let failedRoles = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.keepLibraryClient.readRoles = { throw CocoaError(.fileReadUnknown) }
    }) { PlaylistProgressModel() }
    await failedRoles.refresh([playlist])
    #expect(!failedRoles.isAvailable)
    #expect(failedRoles.results.isEmpty)

    let failedKeepers = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = {
        [KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers")]
      }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.tracks = { _ in throw CocoaError(.fileReadUnknown) }
    }) { PlaylistProgressModel() }
    await failedKeepers.refresh([playlist])
    #expect(!failedKeepers.isAvailable)
    #expect(failedKeepers.results.isEmpty)

    let failedLog = withDependencies({ dependencies in
      dependencies.date.now = date(101)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.playlistTasteNotesClient.read = { emptyNotes() }
      dependencies.playlistListeningLogClient.read = { _, _ in throw CocoaError(.fileReadUnknown) }
    }) { PlaylistProgressModel() }
    await failedLog.refresh([playlist])
    #expect(!failedLog.isAvailable)
    #expect(failedLog.results.isEmpty)
    #expect(failedLog.hasUnreadableListeningLog)
  }

  private func fixture() -> PlaylistShelfPlaylist {
    let songs = ["kept", "played", "unheard"].map { id in
      PlaylistShelfSong(id: id, title: id.capitalized, artist: "Artist", album: nil, year: nil,
        familiarity: "New to you", why: nil, like: [])
    }
    let batch = RecommendationBatch(recordedAt: date(100), host: "Test", playlist: "Test",
      tracks: songs.map { RecommendationTrack(artist: $0.artist, title: $0.title, familiar: false, reasons: [], artistKnown: true) })
    return PlaylistShelfPlaylist(id: "playlist", batch: batch, stagedDate: "today", songCount: 3,
      newSongCount: 3, songs: songs)
  }

  private func roles() throws -> PlaylistRoles {
    PlaylistRoles(updatedAt: date(100), playlists: [
      PlaylistRoleEntry(persistentID: "keepers", name: "Vinyl Fever Keepers", role: .keepers),
    ])
  }

  private func emptyNotes() -> PlaylistTasteNotesFolderRead {
    PlaylistTasteNotesFolderRead(result: TasteNotesCodec.readFiles([]), unreadableFileCount: 0, totalFileCount: 0)
  }

  private func play(_ title: String, end: TimeInterval) -> ListeningPlay {
    ListeningPlay(item: .init(kind: .song, id: title, title: title, artist: "Artist"),
      windowStart: date(end - 1), windowEnd: date(end), poller: UUID())
  }

  private func date(_ value: TimeInterval) -> Date { Date(timeIntervalSince1970: value) }
}
