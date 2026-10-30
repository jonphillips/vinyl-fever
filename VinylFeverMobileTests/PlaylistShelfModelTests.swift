import Dependencies
import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistShelfModelTests {
  @Test @MainActor
  func loadedAndPartlyUnreadable() async {
    let batch = RecommendationBatch(recordedAt: .now, host: "Test", playlist: "Power Pop", tracks: [
      RecommendationTrack(artist: "Band", title: "Song", familiar: false, reasons: [], artistKnown: true),
    ])
    let model = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 0)
      dependencies.playlistShelfClient.read = {
        RecommendationLedgerFolderRead(
          ledger: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0),
          filesRead: 1,
          unreadableFileCount: 1,
          totalFileCount: 2
        )
      }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      return model
    }

    #expect(model.playlists.map { $0.batch.playlist } == ["Power Pop"])
    #expect(model.hasUnreadableFiles)
    #expect(!model.requiresFolderAccess)
    #expect(model.selectedPlaylistID == model.playlists.first?.id)
  }

  @Test @MainActor
  func noFolderAccessShowsSetupAndNothingStagedIsDistinct() async {
    let noAccess = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 0)
      dependencies.playlistShelfClient.read = { throw ProbeBookmarkError.folderNotSelected }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      return model
    }
    #expect(noAccess.requiresFolderAccess)
    #expect(noAccess.playlists.isEmpty)
    noAccess.setupButtonTapped()
    #expect(noAccess.destination == PlaylistShelfModel.Destination.setup)

    let empty = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 0)
      dependencies.playlistShelfClient.read = {
        RecommendationLedgerFolderRead(
          ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0),
          filesRead: 0,
          unreadableFileCount: 0,
          totalFileCount: 0
        )
      }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      return model
    }
    #expect(!empty.requiresFolderAccess)
    #expect(empty.playlists.isEmpty)
    #expect(!empty.hasUnreadableFiles)
  }

  @Test @MainActor
  func pullToRefreshReadsAgain() async {
    let counter = ReadCounter()
    let model = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 0)
      dependencies.playlistShelfClient.read = {
        await counter.increment()
        return RecommendationLedgerFolderRead(
          ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0),
          filesRead: 0,
          unreadableFileCount: 0,
          totalFileCount: 0
        )
      }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      await model.refresh()
      return model
    }
    #expect(await counter.value == 2)
    #expect(!model.isLoading)
  }
}

private actor ReadCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}
