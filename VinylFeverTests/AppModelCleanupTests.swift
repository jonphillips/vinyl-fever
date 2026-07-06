import Dependencies
import Foundation
import Testing
import VinylFeverCore

@testable import VinylFever

/// Covers the terminal "Clean Up Files" action: which folders it removes and the
/// `isShowComplete` gate that keeps it from firing before Music holds the tracks.
@MainActor
@Suite
struct AppModelCleanupTests {
  @Test
  func removesWorkingAndOutputWhenResolved() async {
    let recorder = RemovedURLs()
    let root = URL(filePath: "/tmp/vinyl-fever-show", directoryHint: .isDirectory)

    // Constructed inside `withDependencies` so the model captures the stubbed
    // `removeItem` for the lifetime of the call below.
    let model = withDependencies {
      $0.fileOperationClient.removeItem = { await recorder.append($0) }
    } operation: {
      AppModel()
    }
    model.scannedShowFolder = Self.folder(at: root)
    model.libraryReadState = .completed(Self.resolvedResolution())
    #expect(model.isShowComplete)

    await model.cleanUpProducedFolders()

    let removed = await recorder.urls
    #expect(
      removed == [
        root.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true),
        root.appendingPathComponent(ConversionPlan.outputDirectoryName, isDirectory: true),
      ]
    )
    #expect(model.didCleanUpProducedFolders)
  }

  @Test
  func doesNothingUntilTheShowIsResolved() async {
    let recorder = RemovedURLs()
    let root = URL(filePath: "/tmp/vinyl-fever-show", directoryHint: .isDirectory)

    let model = withDependencies {
      $0.fileOperationClient.removeItem = { await recorder.append($0) }
    } operation: {
      AppModel()
    }
    model.scannedShowFolder = Self.folder(at: root)
    // libraryReadState stays `.idle`, so the pipeline never reaches `.resolved`.
    #expect(!model.isShowComplete)

    await model.cleanUpProducedFolders()

    let removed = await recorder.urls
    #expect(removed.isEmpty)
    #expect(!model.didCleanUpProducedFolders)
  }

  // MARK: - Fixtures

  private static func folder(at root: URL) -> ScannedShowFolder {
    ScannedShowFolder(root: root, audioFiles: [], setlistCandidates: [], coverCandidates: [])
  }

  /// A library read where every produced file resolved — the terminal state that unlocks
  /// cleanup (`didResolveAll == true`).
  private static func resolvedResolution() -> LibraryResolutionResult {
    LibraryResolutionResult(
      albumTitle: "Test Album",
      libraryTracks: [ImportedTrackRef(id: "library-track-1")],
      trackResolutions: [
        LibraryTrackResolution(
          id: UUID(),
          producedFile: URL(filePath: "/tmp/vinyl-fever-show/Output/01 Song.m4a"),
          expectedAlbum: "Test Album",
          expectedTitle: "Song",
          expectedTrackNumber: 1,
          libraryRef: ImportedTrackRef(id: "library-track-1")
        )
      ]
    )
  }
}

/// Sendable sink for the `removeItem` calls the model makes.
private actor RemovedURLs {
  var urls: [URL] = []
  func append(_ url: URL) { urls.append(url) }
}
