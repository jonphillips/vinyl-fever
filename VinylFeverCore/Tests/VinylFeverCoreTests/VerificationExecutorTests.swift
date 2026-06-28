import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct VerificationExecutorTests {
  @Test
  func verifiesMatchingOutputFile() async throws {
    let plan = makeConversionPlan(format: .flac)
    let runLog = RunLogRecorder()

    let result = try await withDependencies {
      $0.fileOperationClient.directoryFiles = { url in
        url == plan.outputDirectory ? [plan.tracks[0].verificationFile] : []
      }
      $0.audioMetadataClient.read = { _ in
        matchingTags(for: plan.tracks[0], title: "  The Way It Is  ")
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await VerificationExecutor().verify(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffprobe: "/tools/ffprobe"])
      )
    }

    expectNoDifference(result.didVerify, true)
    expectNoDifference(result.exitSummary, "verified")
    expectNoDifference(result.expectedFileCount, 1)
    expectNoDifference(result.actualFileCount, 1)
    expectNoDifference(result.files.map(\.status), [.read])
  }

  @Test
  func reportsCountMismatch() async throws {
    let plan = makeConversionPlan(format: .flac)

    let result = try await withDependencies {
      $0.fileOperationClient.directoryFiles = { _ in [] }
      $0.audioMetadataClient.read = { _ in matchingTags(for: plan.tracks[0]) }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await VerificationExecutor().verify(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffprobe: "/tools/ffprobe"])
      )
    }

    expectNoDifference(result.didVerify, false)
    expectNoDifference(result.expectedFileCount, 1)
    expectNoDifference(result.actualFileCount, 0)
    expectNoDifference(result.exitSummary, "expected 1, found 0")
  }

  @Test
  func reportsTagMismatch() async throws {
    let plan = makeConversionPlan(format: .flac)

    let result = try await withDependencies {
      $0.fileOperationClient.directoryFiles = { _ in [plan.tracks[0].verificationFile] }
      $0.audioMetadataClient.read = { _ in
        matchingTags(for: plan.tracks[0], title: "Mandolin Rain")
      }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await VerificationExecutor().verify(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffprobe: "/tools/ffprobe"])
      )
    }

    expectNoDifference(result.didVerify, false)
    expectNoDifference(
      result.files[0].mismatches,
      [.title(expected: "The Way It Is", actual: "Mandolin Rain")]
    )
    expectNoDifference(result.exitSummary, "1 of 1 failed")
  }

  @Test
  func reportsZeroDuration() async throws {
    let plan = makeConversionPlan(format: .flac)

    let result = try await withDependencies {
      $0.fileOperationClient.directoryFiles = { _ in [plan.tracks[0].verificationFile] }
      $0.audioMetadataClient.read = { _ in
        matchingTags(for: plan.tracks[0], durationSeconds: 0)
      }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await VerificationExecutor().verify(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffprobe: "/tools/ffprobe"])
      )
    }

    expectNoDifference(result.didVerify, false)
    expectNoDifference(result.files[0].mismatches, [.durationNotPositive(0)])
  }

  @Test
  func verifiesMP3WorkingFilesWithoutConversion() async throws {
    let plan = makeConversionPlan(format: .mp3)

    let result = try await withDependencies {
      $0.fileOperationClient.directoryFiles = { url in
        url == plan.workingDirectory ? [plan.tracks[0].workingFile] : []
      }
      $0.audioMetadataClient.read = { request in
        expectNoDifference(request.url, plan.tracks[0].workingFile)
        expectNoDifference(request.format, .mp3)
        return matchingTags(for: plan.tracks[0])
      }
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await VerificationExecutor().verify(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffprobe: "/tools/ffprobe"])
      )
    }

    expectNoDifference(plan.requiresConversion, false)
    expectNoDifference(result.didVerify, true)
  }
}

private func matchingTags(
  for track: ConversionTrackPlan,
  title: String? = nil,
  durationSeconds: Double = 12
) -> AudioTags {
  AudioTags(
    title: title ?? track.tags.title,
    artist: track.tags.artist,
    album: track.tags.album,
    sortAlbum: track.tags.sortAlbum,
    albumArtist: track.tags.albumArtist,
    trackNumber: track.tags.trackNumber,
    trackTotal: track.trackTotal,
    discNumber: track.tags.discNumber,
    durationSeconds: durationSeconds,
    hasAudioStream: true,
    hasEmbeddedArtwork: true
  )
}
