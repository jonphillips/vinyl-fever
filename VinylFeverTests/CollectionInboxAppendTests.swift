import Dependencies
import Foundation
import Testing
import VinylFeverCore

@testable import VinylFever

/// M10 · S1 wiring: dropping loose songs onto a compilation album stages them into the
/// app-owned Inbox and drives the existing append rail, and a certified append drains that
/// album's staged copies while a folder-picked append never does.
@MainActor
@Suite
struct CollectionInboxAppendTests {
  /// A dropped file is copied into the album's Inbox (original preserved) and the append rail
  /// is pointed at the Inbox folder — i.e. `stageDroppedFilesForAppend` reaches
  /// `buildCompilationAppendPlan` with the staging directory as its source folder.
  @Test
  func stagingADropPointsTheAppendRailAtTheInboxFolder() async throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inboxRoot = temp.appendingPathComponent("Inbox", isDirectory: true)

    let source = temp.appendingPathComponent("one-hit-wonder.m4a")
    try Data("audio".utf8).write(to: source)

    let album = Self.album()
    let model = withDependencies {
      $0.collectionInboxClient = .live(root: inboxRoot)
      // Keep the plan build cheap and device-free: no files scanned means no metadata read.
      $0.fileSystemClient.scanAudioFolder = { _ in [] }
    } operation: {
      AppModel()
    }

    await model.stageDroppedFilesForAppend(entry: album, files: [source])

    let expectedInbox = inboxRoot.appendingPathComponent(album.id.uuidString, isDirectory: true)
    #expect(model.compilationAppendFolder?.standardizedFileURL == expectedInbox.standardizedFileURL)
    #expect(model.compilationAppendAlbumID == album.id)
    // The original is untouched and a copy now lives in the Inbox.
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    #expect(
      FileManager.default.fileExists(
        atPath: expectedInbox.appendingPathComponent("one-hit-wonder.m4a").path(percentEncoded: false)
      )
    )
  }

  /// The certify-success cleanup drains the album's Inbox when the append was sourced from that
  /// album's staging folder.
  @Test
  func certifiedInboxAppendDrainsThatAlbum() {
    let drained = DrainRecorder()
    let inboxRoot = URL(filePath: "/tmp/vinyl-fever-inbox-test", directoryHint: .isDirectory)
    let album = Self.album()

    let model = withDependencies {
      $0.collectionInboxClient.stagingDirectory = { id in
        inboxRoot.appendingPathComponent(id.uuidString, isDirectory: true)
      }
      $0.collectionInboxClient.drain = { drained.record($0) }
    } operation: {
      AppModel()
    }

    let plan = CompilationApplyPlan(
      entry: album,
      sourceRoot: inboxRoot.appendingPathComponent(album.id.uuidString, isDirectory: true),
      tracks: []
    )
    model.drainInboxIfStaged(plan: plan)

    #expect(drained.ids == [album.id])
  }

  /// A folder-picked append (source is the user's own folder, not the Inbox) never drains.
  @Test
  func folderPickedAppendNeverDrains() {
    let drained = DrainRecorder()
    let inboxRoot = URL(filePath: "/tmp/vinyl-fever-inbox-test", directoryHint: .isDirectory)
    let album = Self.album()

    let model = withDependencies {
      $0.collectionInboxClient.stagingDirectory = { id in
        inboxRoot.appendingPathComponent(id.uuidString, isDirectory: true)
      }
      $0.collectionInboxClient.drain = { drained.record($0) }
    } operation: {
      AppModel()
    }

    let plan = CompilationApplyPlan(
      entry: album,
      sourceRoot: URL(filePath: "/Users/jon/Downloads/loose-songs", directoryHint: .isDirectory),
      tracks: []
    )
    model.drainInboxIfStaged(plan: plan)

    #expect(drained.ids.isEmpty)
  }

  // MARK: - Fixtures

  private static func album() -> CompilationAlbum {
    CompilationAlbum(
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      name: "One-Hit Wonders",
      identity: AlbumIdentity(album: "One-Hit Wonders", albumArtist: "Various Artists")
    )
  }

  private static func makeTempDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("vinyl-fever-inbox-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

/// Sendable sink for the `drain(albumID:)` calls the model makes.
private final class DrainRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _ids: [CompilationAlbum.ID] = []

  func record(_ id: CompilationAlbum.ID) {
    lock.withLock { _ids.append(id) }
  }

  var ids: [CompilationAlbum.ID] {
    lock.withLock { _ids }
  }
}
