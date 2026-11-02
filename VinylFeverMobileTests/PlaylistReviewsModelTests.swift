import Dependencies
import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistReviewsModelTests {
  @Test @MainActor
  func finishAndReopenAppendJonLinesAndLatestStateWins() async {
    let playlist = makePlaylist()
    let writes = ReviewWriteCounter()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 1_800_000_100)
      dependencies.playlistReviewsClient.deviceName = { "Test iPhone" }
      dependencies.playlistReviewsClient.append = { entry, writer in
        await writes.append(entry, writer: writer)
      }
    }) { PlaylistReviewsModel() }

    await model.finish(playlist)
    #expect(model.finishedEntries[playlist.id]?.kind == .finished)
    await model.reopen(playlist)
    #expect(model.finishedEntries[playlist.id] == nil)
    let saved = await writes.entries
    #expect(saved.map(\.0.kind) == [.finished, .reopened])
    #expect(saved.allSatisfy { $0.0.source == .jon && $0.0.device == "Test iPhone" && $0.1 == "Test iPhone" })
  }

  @Test @MainActor
  func finishCapturesProgressOutcomesAndCounts() async {
    let playlist = makePlaylist()
    let writes = ReviewWriteCounter()
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 1_800_000_100)
      dependencies.playlistReviewsClient.deviceName = { "Test iPhone" }
      dependencies.playlistReviewsClient.append = { entry, writer in await writes.append(entry, writer: writer) }
    }) { PlaylistReviewsModel() }
    let progress = PlaylistProgressResult(
      songs: [playlist.songs[0].id: .kept(in: ["Keepers"])],
      counts: PlaylistProgressCounts(kept: 1, passedWithFeedback: 0, passedWithoutFeedback: 0, notHeard: 0))

    await model.finish(playlist, progress: progress)

    let saved = await writes.entries.first?.0
    #expect(saved?.heard == 1)
    #expect(saved?.kept == 1)
    #expect(saved?.passed == 0)
    #expect(saved?.unheard == 0)
    #expect(saved?.songs == [PlaylistReviewSongOutcome(index: 0, title: "Song", artist: "Artist",
      status: "kept", keptIn: ["Keepers"])])
  }

  @Test @MainActor
  func refreshShowsLatestReviewAndFinishedState() async {
    let playlist = makePlaylist()
    let finished = PlaylistReviewEntry(source: .jon, kind: .finished, host: "Mac",
      recordedAt: playlist.batch.recordedAt, playlistID: playlist.id, playlist: "Playlist",
      at: Date(timeIntervalSince1970: 10), device: "iPhone")
    let review = PlaylistReviewEntry(source: .chat, kind: .review, host: "Mac",
      recordedAt: playlist.batch.recordedAt, playlistID: playlist.id, playlist: "Playlist",
      at: Date(timeIntervalSince1970: 11), text: "The sequence builds well.", heard: 1, kept: 1, passed: 0, unheard: 0)
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 12)
      dependencies.playlistReviewsClient.read = {
        PlaylistReviewsReadResult(entries: [finished, review], skippedLines: 0, filesRead: 1)
      }
      dependencies.playlistReviewsClient.append = { _, _ in }
    }) { PlaylistReviewsModel() }

    await model.refresh()

    #expect(model.finishedEntries[playlist.id] != nil)
    #expect(model.waitingEntries[playlist.id] == nil)
    #expect(model.reviews[playlist.id]?.text == "The sequence builds well.")
    #expect(!model.hasUnreadableFiles)

    await model.finish(playlist)
    #expect(model.entries.count == 3)
    #expect(model.entries.last?.at == Date(timeIntervalSince1970: 12))
    #expect(model.finishedEntries[playlist.id]?.at == Date(timeIntervalSince1970: 12))
    #expect(model.reviews[playlist.id]?.at == Date(timeIntervalSince1970: 11))
    #expect(model.waitingEntries[playlist.id] != nil)
  }

  @Test @MainActor
  func finishedEntryPersistsAndReadsBackFromInjectedFolder() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder) }
    let playlist = makePlaylist()
    let instant = Date(timeIntervalSince1970: 1_800_000_200.25)
    let model = withDependencies({ dependencies in
      dependencies.date.now = instant
      dependencies.playlistReviewsClient.deviceName = { "Test iPhone" }
      dependencies.playlistReviewsClient.read = {
        guard FileManager.default.fileExists(atPath: folder.path) else {
          return PlaylistReviewsReadResult(entries: [], skippedLines: 0, filesRead: 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
          .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return PlaylistReviewsCodec.readFiles(try files.map { try Data(contentsOf: $0) })
      }
      dependencies.playlistReviewsClient.append = { entry, writer in
        try PlaylistReviewsCodec.append(entry, writer: writer, folder: folder)
      }
    }) { PlaylistReviewsModel() }

    await model.finish(playlist)
    await model.refresh()

    #expect(model.finishedEntries[playlist.id]?.at == instant)
    #expect(model.entries.first?.device == "Test iPhone")
    #expect(model.entries.first?.source == .jon)
  }

  private func makePlaylist() -> PlaylistShelfPlaylist {
    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 100), host: "Mac",
      playlist: "Playlist", tracks: [RecommendationTrack(artist: "Artist", title: "Song", familiar: false,
        reasons: [], artistKnown: true)])
    return PlaylistShelf.make(from: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
      now: Date(timeIntervalSince1970: 101), calendar: .current, timeZone: .current)[0]
  }
}

private actor ReviewWriteCounter {
  private(set) var entries: [(PlaylistReviewEntry, String)] = []
  func append(_ entry: PlaylistReviewEntry, writer: String) { entries.append((entry, writer)) }
}
