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
      dependencies.keepLibraryClient = KeepLibraryClient.testValue
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
    #expect(model.selectedPlaylistID == nil)
  }

  @Test @MainActor
  func refreshKeepsAnExistingSelectionAndClearsOneThatDisappears() async {
    let first = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 2), host: "Test", playlist: "First", tracks: [])
    let second = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 1), host: "Test", playlist: "Second", tracks: [])
    let rows = PlaylistShelf.make(
      from: RecommendationLedgerReadResult(batches: [first, second], skippedLines: 0),
      now: Date(timeIntervalSince1970: 3), calendar: Calendar.current, timeZone: .current
    )
    let model = withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 3)
      dependencies.keepLibraryClient = KeepLibraryClient.testValue
      dependencies.playlistShelfClient.read = {
        RecommendationLedgerFolderRead(
          ledger: RecommendationLedgerReadResult(batches: [first, second], skippedLines: 0),
          filesRead: 1,
          unreadableFileCount: 0,
          totalFileCount: 1
        )
      }
    }) {
      PlaylistShelfModel()
    }

    model.selectedPlaylistID = rows[1].id
    await model.refresh()
    #expect(model.selectedPlaylistID == rows[1].id)

    model.selectedPlaylistID = "removed-playlist"
    await model.refresh()
    #expect(model.selectedPlaylistID == nil)
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
      dependencies.keepLibraryClient = KeepLibraryClient.testValue
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
      dependencies.keepLibraryClient = KeepLibraryClient.testValue
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

  @Test @MainActor
  func archiveCountsAndSegmentSwitchesClearSelectionsOutsideTheSegment() async throws {
    let present = batch(name: "Power Pop", stagedAt: 1_000)
    let archived = batch(name: "Old Mix", stagedAt: 0)
    let recent = batch(name: "Just Staged", stagedAt: 50_000)
    let model = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 100_000)
      dependencies.playlistShelfClient.read = { folderRead([present, archived, recent]) }
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = {
        [KeepLibraryPlaylist(id: "power-pop", name: "Power Pop")]
      }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      return model
    }

    #expect(model.selectedSegment == .active)
    #expect(model.count(in: .active) == 2)
    #expect(model.count(in: .archived) == 1)
    let archivedPlaylist = try #require(model.playlists.first { $0.batch.playlist == "Old Mix" })
    #expect(model.archiveStatusText(for: archivedPlaylist) == "No longer in your Music library.")

    model.selectedPlaylistID = model.displayedPlaylists[0].id
    model.selectSegment(.archived)
    #expect(model.selectedPlaylistID == nil)
    #expect(model.displayedPlaylists.map(\.id) == [archivedPlaylist.id])

    model.selectedPlaylistID = archivedPlaylist.id
    model.selectSegment(.active)
    #expect(model.selectedPlaylistID == nil)
  }

  @Test @MainActor
  func anEmptyArchiveSegmentShowsItsGuidanceAndLibraryReadFailureKeepsAllActive() async {
    let oldPlaylist = batch(name: "Old Mix", stagedAt: 0)
    let model = await withDependencies({ dependencies in
      dependencies.date.now = Date(timeIntervalSince1970: 100_000)
      dependencies.playlistShelfClient.read = { folderRead([oldPlaylist]) }
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { throw CocoaError(.fileReadUnknown) }
    }) {
      let model = PlaylistShelfModel()
      await model.refresh()
      return model
    }

    #expect(model.count(in: .active) == 1)
    #expect(model.count(in: .archived) == 0)
    model.selectSegment(.archived)
    #expect(model.emptyArchiveMessage == "Playlists you delete in Music move here.")
  }

  private func batch(name: String?, stagedAt: TimeInterval) -> RecommendationBatch {
    RecommendationBatch(recordedAt: Date(timeIntervalSince1970: stagedAt), host: "Test",
      playlist: name, tracks: [])
  }

  private func folderRead(_ batches: [RecommendationBatch]) -> RecommendationLedgerFolderRead {
    RecommendationLedgerFolderRead(ledger: RecommendationLedgerReadResult(batches: batches, skippedLines: 0),
      filesRead: batches.count, unreadableFileCount: 0, totalFileCount: batches.count)
  }
}

private actor ReadCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}
