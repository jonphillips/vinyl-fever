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
      $0.collectionInboxClient.summary = { [] }
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

  /// Confirming an Append Preview must run the already-reviewed plan. Rebuilding here used to
  /// synchronously scan and re-read every staged file before exposing any progress, so the action
  /// could look inert (or stall) even though the preview was ready.
  @Test
  func applyingPreviewDoesNotRebuildIt() async {
    let album = Self.album()
    let sourceFolder = URL(filePath: "/tmp/append-preview")
    let scanRecorder = FolderScanRecorder()
    let run = RunRecord(
      id: UUID(3),
      showRootPath: sourceFolder.path(percentEncoded: false),
      kind: .apply,
      startedAt: .distantPast,
      command: "apply"
    )
    let model = withDependencies {
      $0.fileSystemClient.scanAudioFolder = { folder in
        scanRecorder.record(folder)
        struct UnexpectedRebuild: Error {}
        throw UnexpectedRebuild()
      }
      $0.runLogClient.open = { _ in run }
      $0.runLogClient.close = { request in
        var closed = run
        closed.finishedAt = .distantPast
        closed.exitSummary = request.exitSummary
        return closed
      }
      $0.musicAppClient.requestAutomationPermission = { .denied }
    } operation: {
      AppModel()
    }
    model.compilationAppendFolder = sourceFolder
    model.compilationAppendAlbumID = album.id
    model.compilationApplyPlan = CompilationApplyPlan(
      entry: album,
      sourceRoot: sourceFolder,
      tracks: []
    )

    await withDependencies {
      $0.runLogClient.open = { _ in run }
      $0.runLogClient.close = { request in
        var closed = run
        closed.finishedAt = .distantPast
        closed.exitSummary = request.exitSummary
        return closed
      }
      $0.fileOperationClient.createDirectory = { _ in }
      $0.musicAppClient.requestAutomationPermission = { .denied }
    } operation: {
      await model.applyCurrentCompilationAppend(entry: album)
    }

    #expect(scanRecorder.folders.isEmpty)
    #expect(model.compilationImportState == .permission(.denied))
  }

  /// A staged drop shows up in `inboxSummary` with the right count once refreshed.
  @Test
  func stagingADropIsReflectedInInboxSummary() async throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inboxRoot = temp.appendingPathComponent("Inbox", isDirectory: true)

    let source = temp.appendingPathComponent("one-hit-wonder.m4a")
    try Data("audio".utf8).write(to: source)

    let album = Self.album()
    let model = withDependencies {
      $0.collectionInboxClient = .live(root: inboxRoot)
      $0.fileSystemClient.scanAudioFolder = { _ in [] }
    } operation: {
      AppModel()
    }

    await model.stageDroppedFilesForAppend(entry: album, files: [source])

    #expect(model.inboxSummary == [InboxAlbumSummary(albumID: album.id, fileCount: 1)])
    #expect(
      model.inboxFilesByAlbumID[album.id] == [
        inboxRoot.appendingPathComponent(album.id.uuidString, isDirectory: true)
          .appendingPathComponent("one-hit-wonder.m4a")
          .standardizedFileURL,
      ]
    )
  }

  /// Resuming a staged queue removes stale derived Working copies before rebuilding the Inbox
  /// preview. The source copies remain intact, so a fresh append does not trip destination
  /// conflicts from a prior partial run.
  @Test
  func resumingInboxRebuildsTheQueueAndClearsWorking() async throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inbox = CollectionInboxClient.live(root: temp.appendingPathComponent("Inbox", isDirectory: true))
    let album = Self.album()
    let staging = try inbox.stagingDirectory(album.id)
    let stagedFile = staging.appendingPathComponent("queued.mp3")
    try Data("source".utf8).write(to: stagedFile)
    let working = staging.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
    try Data("derived".utf8).write(to: working.appendingPathComponent("queued.mp3"))
    let model = AppModel()

    await withDependencies {
      $0.collectionInboxClient = inbox
      $0.fileSystemClient.scanAudioFolder = { _ in [] }
      $0.fileOperationClient.removeItem = { url in
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
      }
    } operation: {
      await model.resumeInboxAppend(entry: album)
    }

    #expect(model.compilationAppendFolder?.standardizedFileURL == staging.standardizedFileURL)
    #expect(model.compilationAppendAlbumID == album.id)
    #expect(model.compilationApplyPlan != nil)
    #expect(FileManager.default.fileExists(atPath: stagedFile.path(percentEncoded: false)))
    #expect(!FileManager.default.fileExists(atPath: working.path(percentEncoded: false)))
  }

  /// A manual Clear (drain without appending) zeroes that album out of the summary.
  @Test
  func clearInboxQueueZeroesTheSummary() async throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inboxRoot = temp.appendingPathComponent("Inbox", isDirectory: true)

    let source = temp.appendingPathComponent("one-hit-wonder.m4a")
    try Data("audio".utf8).write(to: source)

    let album = Self.album()
    let model = withDependencies {
      $0.collectionInboxClient = .live(root: inboxRoot)
      $0.fileSystemClient.scanAudioFolder = { _ in [] }
    } operation: {
      AppModel()
    }

    await model.stageDroppedFilesForAppend(entry: album, files: [source])
    #expect(!model.inboxSummary.isEmpty)

    model.clearInboxQueue(albumID: album.id)

    #expect(model.inboxSummary.isEmpty)
    #expect(model.inboxFilesByAlbumID.isEmpty)
  }

  /// A staged album ID with no backing registry entry (a since-deleted album) still surfaces
  /// in `inboxSummary` — the store has no concept of the registry, so orphan detection is the
  /// view's job of resolving the ID, not the model's job of filtering it out.
  @Test
  func refreshInboxSummaryRepresentsAnOrphanedAlbumID() throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inboxRoot = temp.appendingPathComponent("Inbox", isDirectory: true)

    let source = temp.appendingPathComponent("orphan-song.m4a")
    try Data("audio".utf8).write(to: source)

    let orphanedAlbumID = CompilationAlbum.ID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let liveClient = CollectionInboxClient.live(root: inboxRoot)
    _ = try liveClient.stage([source], orphanedAlbumID)

    let model = withDependencies {
      $0.collectionInboxClient = liveClient
    } operation: {
      AppModel()
    }

    model.refreshInboxSummary()

    #expect(model.inboxSummary == [InboxAlbumSummary(albumID: orphanedAlbumID, fileCount: 1)])
    #expect(
      model.inboxFilesByAlbumID[orphanedAlbumID] == [
        inboxRoot.appendingPathComponent(orphanedAlbumID.uuidString, isDirectory: true)
          .appendingPathComponent("orphan-song.m4a")
          .standardizedFileURL,
      ]
    )
  }

  /// The repair rail can only replace the app-owned Inbox copy. On success it discards the
  /// derived Working folder and rebuilds the preview, so a retry cannot conflict with files from
  /// the partial append.
  @Test
  func strippingArtworkRepairsTheStagedCopyAndClearsWorking() async throws {
    let temp = try Self.makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let inbox = CollectionInboxClient.live(root: temp.appendingPathComponent("Inbox", isDirectory: true))
    let album = Self.album()
    let staging = try inbox.stagingDirectory(album.id)
    let stagedFile = staging.appendingPathComponent("broken-cover.mp3")
    try Data("before".utf8).write(to: stagedFile)
    let working = staging.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
    try Data("derived".utf8).write(to: working.appendingPathComponent("broken-cover.mp3"))

    let file = ScannedAudioFile(
      id: UUID(4),
      url: stagedFile,
      format: .mp3,
      sortKey: stagedFile.lastPathComponent
    )
    let plan = CompilationApplyPlan(
      entry: album,
      sourceRoot: staging,
      tracks: [
        CompilationTrackPlan(
          id: file.id,
          sourceFile: file,
          workingFile: working.appendingPathComponent(file.url.lastPathComponent),
          current: AudioTags(),
          proposed: ProposedTags(),
          artwork: .keepExisting,
          fallbackArtworkURL: nil,
          diffs: []
        ),
      ]
    )
    let model = AppModel()
    model.toolStatuses = [
      ToolStatus(tool: .ffmpeg, resolvedPath: "/tools/ffmpeg", version: nil, source: .userOverride),
    ]
    model.compilationAppendFolder = staging
    model.compilationAppendAlbumID = album.id
    model.compilationApplyPlan = plan

    await withDependencies {
      $0.collectionInboxClient = inbox
      $0.fileSystemClient.scanAudioFolder = { _ in [] }
      $0.scriptClient.run = { command in
        let replacement = URL(filePath: try #require(command.arguments.last))
        try Data("after".utf8).write(to: replacement)
        return ScriptResult(command: command, exitCode: 0, standardOutput: Data(), standardError: Data())
      }
      $0.fileOperationClient.replaceFile = { source, destination in
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
      }
      $0.fileOperationClient.removeItem = { url in
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
      }
      $0.uuid = .incrementing
    } operation: {
      await model.stripArtworkFromCurrentCompilationAppend(album: album, file: stagedFile)
    }

    #expect(try Data(contentsOf: stagedFile) == Data("after".utf8))
    #expect(!FileManager.default.fileExists(atPath: working.path(percentEncoded: false)))
    #expect(model.compilationArtworkRepairState == .idle)
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

/// Thread-safe observation for a `@Sendable` dependency closure.
private final class FolderScanRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var _folders: [URL] = []

  func record(_ folder: URL) {
    lock.withLock { _folders.append(folder) }
  }

  var folders: [URL] {
    lock.withLock { _folders }
  }
}
