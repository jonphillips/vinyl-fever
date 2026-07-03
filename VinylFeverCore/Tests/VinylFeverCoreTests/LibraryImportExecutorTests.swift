import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct LibraryImportExecutorTests {
  @Test
  func importsProducedFilesAndRecordsOutcomes() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    let music = MusicAppRecorder(
      albumReads: [
        [],
        [libraryRef(for: plan.tracks[0])],
      ],
      addResult: .success([])
    )

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { request in
        try await music.readAlbumTracks(request)
      }
      $0.musicAppClient.add = { urls in
        try await music.add(urls)
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor().importToLibrary(plan)
    }

    expectNoDifference(result.run.kind, .importLibrary)
    expectNoDifference(result.exitSummary, "imported")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.tracks.map(\.status), [.imported])

    let addedURLs = await music.addedURLs()
    let outcomes = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))
    expectNoDifference(addedURLs, [[plan.tracks[0].verificationFile]])
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
  func importsWorkingFilesWhenNoConversionIsRequired() async throws {
    let plan = makeConversionPlan(format: .mp3)
    let music = MusicAppRecorder(
      albumReads: [
        [],
        [libraryRef(for: plan.tracks[0])],
      ],
      addResult: .success([])
    )

    _ = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { request in
        try await music.readAlbumTracks(request)
      }
      $0.musicAppClient.add = { urls in
        try await music.add(urls)
      }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await LibraryImportExecutor().importToLibrary(plan)
    }

    let addedURLs = await music.addedURLs()
    expectNoDifference(addedURLs, [[plan.tracks[0].workingFile]])
  }

  @Test
  func surfacesAlreadyPresentFilesWithoutAddingAgain() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    let music = MusicAppRecorder(
      albumReads: [
        [libraryRef(for: plan.tracks[0])],
      ],
      addResult: .failure(MusicAppRecorderError.addFailed)
    )

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { request in
        try await music.readAlbumTracks(request)
      }
      $0.musicAppClient.add = { urls in
        try await music.add(urls)
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor().importToLibrary(plan)
    }

    expectNoDifference(result.exitSummary, "already present")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.tracks.map(\.status), [.alreadyPresent])
    let addedURLs = await music.addedURLs()
    expectNoDifference(addedURLs, [])

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
  func recordsFailedAddsAndContinuesTheRun() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()
    let music = MusicAppRecorder(
      albumReads: [
        [],
        [],
      ],
      addResult: .failure(MusicAppRecorderError.addFailed)
    )

    let result = try await withDependencies {
      $0.musicAppClient.readAlbumTracks = { request in
        try await music.readAlbumTracks(request)
      }
      $0.musicAppClient.add = { urls in
        try await music.add(urls)
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await LibraryImportExecutor().importToLibrary(plan)
    }

    expectNoDifference(result.exitSummary, "1 of 1 failed")
    expectNoDifference(result.didSucceed, false)
    expectNoDifference(result.tracks.map(\.status), [.failed("Music add failed.")])

    let outcomes = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))
    expectNoDifference(
      outcomes,
      [
        RunOutcomeSnapshot(
          status: .failed,
          producedPath: nil,
          note: "Music add failed."
        ),
      ]
    )
  }
}

private actor MusicAppRecorder {
  private var albumReads: [[ImportedTrackRef]]
  private let addResult: Result<[ImportedTrackRef], Error>
  private var added: [[URL]] = []

  init(albumReads: [[ImportedTrackRef]], addResult: Result<[ImportedTrackRef], Error>) {
    self.albumReads = albumReads
    self.addResult = addResult
  }

  func readAlbumTracks(_ request: MusicAlbumReadRequest) throws -> [ImportedTrackRef] {
    _ = request
    guard !albumReads.isEmpty else {
      return []
    }
    return albumReads.removeFirst()
  }

  func add(_ urls: [URL]) throws -> [ImportedTrackRef] {
    added.append(urls)
    return try addResult.get()
  }

  func addedURLs() -> [[URL]] {
    added
  }
}

private enum MusicAppRecorderError: LocalizedError {
  case addFailed

  var errorDescription: String? {
    switch self {
    case .addFailed:
      "Music add failed."
    }
  }
}

private func libraryRef(for track: ConversionTrackPlan) -> ImportedTrackRef {
  ImportedTrackRef(
    id: "music-\(track.tags.trackNumber)",
    title: track.tags.title,
    album: track.tags.album,
    trackNumber: track.tags.trackNumber,
    durationSeconds: 12,
    location: track.verificationFile
  )
}
