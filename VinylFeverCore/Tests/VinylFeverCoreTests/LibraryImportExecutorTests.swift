import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct LibraryImportExecutorTests {
  // A short deadline / tiny interval keeps the poll loop instant in tests without a clock
  // dependency; success cases resolve on the first read and never sleep.
  private static let fastImporter = MusicWatchFolderImporter(
    deadline: .milliseconds(20),
    pollInterval: .milliseconds(1)
  )
  private static let watchFolder = URL(filePath: "/tmp/AutomaticallyAdd")

  @Test
  func dropsProducedFilesAndRecordsOutcomes() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    let music = MusicAppRecorder(
      albumReads: [
        [],
        [libraryRef(for: plan.tracks[0])],
      ]
    )

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor(importer: Self.fastImporter)
        .importToLibrary(plan, watchFolder: Self.watchFolder)
    }

    expectNoDifference(result.run.kind, .importLibrary)
    expectNoDifference(result.exitSummary, "imported")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.tracks.map(\.status), [.imported])

    let dropped = await music.droppedFiles()
    let outcomes = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))
    expectNoDifference(dropped, [DroppedBatch(urls: [plan.tracks[0].verificationFile], folder: Self.watchFolder)])
    expectNoDifference(
      outcomes,
      [
        RunOutcomeSnapshot(
          status: .created,
          producedPath: plan.tracks[0].verificationFile.path(percentEncoded: false),
          note: "Imported as Music item music-1."
        ),
      ]
    )
  }

  @Test
  func dropsWorkingFilesWhenNoConversionIsRequired() async throws {
    let plan = makeConversionPlan(format: .mp3)
    let music = MusicAppRecorder(
      albumReads: [
        [],
        [libraryRef(for: plan.tracks[0])],
      ]
    )

    _ = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await LibraryImportExecutor(importer: Self.fastImporter)
        .importToLibrary(plan, watchFolder: Self.watchFolder)
    }

    let dropped = await music.droppedFiles()
    expectNoDifference(dropped.map(\.urls), [[plan.tracks[0].workingFile]])
  }

  @Test
  func surfacesAlreadyPresentFilesWithoutDroppingAgain() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    let music = MusicAppRecorder(
      albumReads: [
        [libraryRef(for: plan.tracks[0])],
      ]
    )

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor(importer: Self.fastImporter)
        .importToLibrary(plan, watchFolder: Self.watchFolder)
    }

    expectNoDifference(result.exitSummary, "already present")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.tracks.map(\.status), [.alreadyPresent])
    let dropped = await music.droppedFiles()
    expectNoDifference(dropped, [])

    let outcomes = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))
    expectNoDifference(
      outcomes,
      [
        RunOutcomeSnapshot(
          status: .skipped,
          producedPath: plan.tracks[0].verificationFile.path(percentEncoded: false),
          note: "Already present as Music item music-1."
        ),
      ]
    )
  }

  @Test
  func recordsFilesMusicHasNotYetIngestedAsDropped() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    // Every poll read comes back empty — Music has not ingested the drop yet.
    let music = MusicAppRecorder(albumReads: [[]])

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor(importer: Self.fastImporter)
        .importToLibrary(plan, watchFolder: Self.watchFolder)
    }

    // The file was copied into the watch folder, so the import succeeded even though the poll
    // never confirmed ingest — Music imports the folder on its own schedule.
    expectNoDifference(result.exitSummary, "dropped (awaiting Music)")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.tracks.map(\.status), [.dropped])

    let dropped = await music.droppedFiles()
    expectNoDifference(dropped.map(\.urls), [[plan.tracks[0].verificationFile]])
  }
}

private struct DroppedBatch: Equatable, Sendable {
  var urls: [URL]
  var folder: URL
}

private actor MusicAppRecorder {
  private var albumReads: [[ImportedTrackRef]]
  private var lastRead: [ImportedTrackRef] = []
  private var dropped: [DroppedBatch] = []

  init(albumReads: [[ImportedTrackRef]]) {
    self.albumReads = albumReads
  }

  func readAlbumTracks(_ request: MusicAlbumReadRequest) -> [ImportedTrackRef] {
    _ = request
    guard !albumReads.isEmpty else {
      return lastRead
    }
    lastRead = albumReads.removeFirst()
    return lastRead
  }

  func importViaWatchFolder(_ urls: [URL], _ folder: URL) {
    dropped.append(DroppedBatch(urls: urls, folder: folder))
  }

  func droppedFiles() -> [DroppedBatch] {
    dropped
  }
}

private func libraryRef(for track: ConversionTrackPlan) -> ImportedTrackRef {
  ImportedTrackRef(
    id: "music-\(track.tags.trackNumber ?? 0)",
    title: track.tags.title,
    album: track.tags.album,
    trackNumber: track.tags.trackNumber,
    durationSeconds: 12,
    location: track.verificationFile
  )
}
