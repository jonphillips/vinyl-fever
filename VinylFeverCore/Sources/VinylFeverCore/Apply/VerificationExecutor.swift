import Dependencies
import Foundation

public struct VerificationExecutor: Sendable {
  @Dependency(\.audioMetadataClient) private var audioMetadataClient
  @Dependency(\.fileOperationClient) private var fileOperationClient
  @Dependency(\.runLogClient) private var runLogClient

  public init() {
  }

  public func verify(_ plan: ConversionPlan, toolPaths: AudioToolPaths) async throws -> VerificationResult {
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .verify,
        command: commandText(for: plan, toolPaths: toolPaths)
      )
    )

    do {
      try Task.checkCancellation()
      let actualFileCount = try await actualVerificationFileCount(for: plan)
      let expectedFileCount = plan.tracks.count
      if actualFileCount != expectedFileCount {
        try await appendCountMismatch(
          run: run,
          plan: plan,
          expected: expectedFileCount,
          actual: actualFileCount
        )
      }

      var fileResults: [VerificationFileResult] = []
      for track in plan.tracks {
        try Task.checkCancellation()
        let result = await verify(track: track, toolPaths: toolPaths)
        fileResults.append(result)
        try await append(result: result, run: run)
      }

      let exitSummary = exitSummary(
        expectedFileCount: expectedFileCount,
        actualFileCount: actualFileCount,
        fileResults: fileResults
      )
      let closedRun = try await close(run: run, exitSummary: exitSummary)
      return VerificationResult(
        run: closedRun,
        expectedFileCount: expectedFileCount,
        actualFileCount: actualFileCount,
        files: fileResults,
        exitSummary: exitSummary
      )
    } catch is CancellationError {
      _ = try? await close(run: run, exitSummary: "cancelled")
      throw CancellationError()
    } catch {
      _ = try? await close(run: run, exitSummary: error.localizedDescription)
      throw error
    }
  }

  private func actualVerificationFileCount(for plan: ConversionPlan) async throws -> Int {
    var count = 0
    for requirement in plan.verificationDirectoryRequirements {
      let files = try await fileOperationClient.directoryFiles(requirement.directory)
      count += files.count { file in
        guard let format = AudioFormat(pathExtension: file.pathExtension) else {
          return false
        }
        return requirement.formats.contains(format)
      }
    }
    return count
  }

  private func verify(
    track: ConversionTrackPlan,
    toolPaths: AudioToolPaths
  ) async -> VerificationFileResult {
    do {
      let tags = try await audioMetadataClient.read(
        AudioMetadataRequest(
          url: track.verificationFile,
          format: track.verificationFormat,
          toolPaths: toolPaths
        )
      )
      let mismatches = AudioTagVerifier.mismatches(
        expected: track.tags,
        trackTotal: track.trackTotal,
        format: track.verificationFormat,
        actual: tags
      )
      return VerificationFileResult(
        id: track.id,
        url: track.verificationFile,
        status: mismatches.isEmpty ? .read : .failed,
        note: mismatches.isEmpty ? "Verified." : mismatches.map(\.message).joined(separator: " "),
        actualTags: tags,
        mismatches: mismatches
      )
    } catch is CancellationError {
      return VerificationFileResult(
        id: track.id,
        url: track.verificationFile,
        status: .failed,
        note: "Verification was cancelled.",
        actualTags: nil,
        mismatches: []
      )
    } catch {
      return VerificationFileResult(
        id: track.id,
        url: track.verificationFile,
        status: .failed,
        note: error.localizedDescription,
        actualTags: nil,
        mismatches: []
      )
    }
  }

  private func appendCountMismatch(
    run: RunRecord,
    plan: ConversionPlan,
    expected: Int,
    actual: Int
  ) async throws {
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: plan.showRoot.path(percentEncoded: false),
        status: .failed,
        note: "Expected \(expected) audio file\(expected == 1 ? "" : "s"), found \(actual)."
      )
    )
  }

  private func append(result: VerificationFileResult, run: RunRecord) async throws {
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: result.url.path(percentEncoded: false),
        status: result.status,
        note: result.note
      )
    )
  }

  private func close(run: RunRecord, exitSummary: String) async throws -> RunRecord {
    try await runLogClient.close(
      RunLogCloseRequest(runID: run.id, exitSummary: exitSummary)
    )
  }

  private func exitSummary(
    expectedFileCount: Int,
    actualFileCount: Int,
    fileResults: [VerificationFileResult]
  ) -> String {
    let failedCount = fileResults.count { !$0.didVerify }
    if expectedFileCount == actualFileCount && failedCount == 0 {
      return "verified"
    }

    var parts: [String] = []
    if expectedFileCount != actualFileCount {
      parts.append("expected \(expectedFileCount), found \(actualFileCount)")
    }
    if failedCount > 0 {
      parts.append("\(failedCount) of \(fileResults.count) failed")
    }
    return parts.joined(separator: ", ")
  }

  private func commandText(for plan: ConversionPlan, toolPaths: AudioToolPaths) -> String {
    let countLines = plan.verificationDirectoryRequirements.map { requirement in
      let formats = requirement.formats
        .map(\.rawValue)
        .sorted()
        .joined(separator: ",")
      return "count \(formats) in \(requirement.directory.path(percentEncoded: false))"
    }
    let metadataLines = plan.tracks.compactMap { track -> String? in
      do {
        switch track.verificationFormat {
        case .flac:
          return try [
            AudioMetadataCommands.flacTagExport(url: track.verificationFile, toolPaths: toolPaths),
            AudioMetadataCommands.flacStreamInfo(url: track.verificationFile, toolPaths: toolPaths),
            AudioMetadataCommands.flacPictureList(url: track.verificationFile, toolPaths: toolPaths),
          ]
          .map(\.commandLine)
          .joined(separator: "\n")
        case .mp3, .m4a:
          let command = try AudioMetadataCommands.ffprobeJSON(
            url: track.verificationFile,
            toolPaths: toolPaths
          )
          return command.commandLine
        }
      } catch {
        return nil
      }
    }
    let lines = countLines + metadataLines
    guard !lines.isEmpty else {
      return "No verification commands could be constructed; one or more tools are missing."
    }
    return lines.joined(separator: "\n")
  }
}
