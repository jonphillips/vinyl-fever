import Dependencies
import Foundation

public struct ConversionExecutor: Sendable {
  @Dependency(\.fileOperationClient) private var fileOperationClient
  @Dependency(\.runLogClient) private var runLogClient
  @Dependency(\.scriptClient) private var scriptClient

  public init() {
  }

  public func convert(_ plan: ConversionPlan, toolPaths: AudioToolPaths) async throws -> ConversionResult {
    let conversionTracks = plan.convertibleTracks
    let commands = try commandPlans(for: conversionTracks, toolPaths: toolPaths)
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .convert,
        command: commandText(for: conversionTracks, commands: commands)
      )
    )

    do {
      try Task.checkCancellation()
      try validateOutputDestinations(in: plan)

      guard !conversionTracks.isEmpty else {
        let closedRun = try await close(run: run, exitSummary: "no conversion needed")
        return ConversionResult(run: closedRun, convertedTracks: [], exitSummary: "no conversion needed")
      }

      let conflicts = try await existingOutputDestinations(in: conversionTracks)
      if !conflicts.isEmpty {
        return try await recordConflictResult(run: run, tracks: conversionTracks, conflicts: conflicts)
      }

      try await fileOperationClient.createDirectory(plan.outputDirectory)
      var convertedTracks: [ConvertedTrack] = []
      for track in conversionTracks {
        try Task.checkCancellation()
        let outcome = await convert(track: track, command: commands[track.id])
        convertedTracks.append(outcome)
        try await append(outcome: outcome, run: run)
      }

      let exitSummary = exitSummary(for: convertedTracks)
      let closedRun = try await close(run: run, exitSummary: exitSummary)
      return ConversionResult(run: closedRun, convertedTracks: convertedTracks, exitSummary: exitSummary)
    } catch is CancellationError {
      _ = try? await close(run: run, exitSummary: "cancelled")
      throw CancellationError()
    } catch {
      _ = try? await close(run: run, exitSummary: error.localizedDescription)
      throw error
    }
  }

  private func commandPlans(
    for tracks: [ConversionTrackPlan],
    toolPaths: AudioToolPaths
  ) throws -> [ConversionTrackPlan.ID: ScriptCommand] {
    try Dictionary(
      uniqueKeysWithValues: tracks.map { track in
        (track.id, try AudioConversionCommands.alacCommand(for: track, toolPaths: toolPaths))
      }
    )
  }

  private func validateOutputDestinations(in plan: ConversionPlan) throws {
    var outputPath = plan.outputDirectory
      .standardizedFileURL
      .path(percentEncoded: false)
    if outputPath.hasSuffix("/") {
      outputPath.removeLast()
    }
    for track in plan.convertibleTracks {
      let destinationPath = track.outputFile.standardizedFileURL.path(percentEncoded: false)
      guard destinationPath.hasPrefix(outputPath + "/") else {
        throw ConversionExecutionError.destinationOutsideOutput(
          destination: track.outputFile,
          outputDirectory: plan.outputDirectory
        )
      }
    }
  }

  private func existingOutputDestinations(in tracks: [ConversionTrackPlan]) async throws -> [URL] {
    var conflicts: [URL] = []
    for track in tracks {
      if try await fileOperationClient.fileExists(track.outputFile) {
        conflicts.append(track.outputFile)
      }
    }
    return conflicts
  }

  private func recordConflictResult(
    run: RunRecord,
    tracks: [ConversionTrackPlan],
    conflicts: [URL]
  ) async throws -> ConversionResult {
    let conflictSet = Set(conflicts.map { $0.standardizedFileURL.path(percentEncoded: false) })
    let convertedTracks = tracks.map { track in
      let destinationPath = track.outputFile.standardizedFileURL.path(percentEncoded: false)
      let note =
        if conflictSet.contains(destinationPath) {
          "Output already exists."
        } else {
          "Skipped because another output already exists."
        }
      return ConvertedTrack(
        id: track.id,
        sourceURL: track.workingFile,
        outputURL: track.outputFile,
        status: .skipped,
        note: note
      )
    }
    for outcome in convertedTracks {
      try await append(outcome: outcome, run: run)
    }
    let exitSummary = "\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")"
    let closedRun = try await close(run: run, exitSummary: exitSummary)
    return ConversionResult(run: closedRun, convertedTracks: convertedTracks, exitSummary: exitSummary)
  }

  private func convert(
    track: ConversionTrackPlan,
    command: ScriptCommand?
  ) async -> ConvertedTrack {
    do {
      guard let command else {
        throw ConversionExecutionError.missingConversionCommand(track.workingFile)
      }
      let result = try await scriptClient.run(command)
      guard result.isSuccessful else {
        throw ConversionExecutionError.commandFailed(
          tool: command.tool,
          exitCode: result.exitCode,
          output: result.combinedOutputText
        )
      }
      return ConvertedTrack(
        id: track.id,
        sourceURL: track.workingFile,
        outputURL: track.outputFile,
        status: .created,
        note: "Converted to ALAC."
      )
    } catch is CancellationError {
      return ConvertedTrack(
        id: track.id,
        sourceURL: track.workingFile,
        outputURL: track.outputFile,
        status: .failed,
        note: "Conversion was cancelled."
      )
    } catch {
      return ConvertedTrack(
        id: track.id,
        sourceURL: track.workingFile,
        outputURL: track.outputFile,
        status: .failed,
        note: error.localizedDescription
      )
    }
  }

  private func append(outcome: ConvertedTrack, run: RunRecord) async throws {
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: outcome.sourceURL.path(percentEncoded: false),
        producedPath: outcome.outputURL.path(percentEncoded: false),
        status: outcome.status,
        note: outcome.note
      )
    )
  }

  private func close(run: RunRecord, exitSummary: String) async throws -> RunRecord {
    try await runLogClient.close(
      RunLogCloseRequest(runID: run.id, exitSummary: exitSummary)
    )
  }

  private func exitSummary(for convertedTracks: [ConvertedTrack]) -> String {
    let failedCount = convertedTracks.count { $0.status == .failed }
    let skippedCount = convertedTracks.count { $0.status == .skipped }
    if failedCount == 0 && skippedCount == 0 {
      return "ok"
    }
    var parts: [String] = []
    if failedCount > 0 {
      parts.append("\(failedCount) of \(convertedTracks.count) failed")
    }
    if skippedCount > 0 {
      parts.append("\(skippedCount) skipped")
    }
    return parts.joined(separator: ", ")
  }

  private func commandText(
    for tracks: [ConversionTrackPlan],
    commands: [ConversionTrackPlan.ID: ScriptCommand]
  ) -> String {
    let lines = tracks.compactMap { track in
      commands[track.id]?.commandLine
    }
    guard !lines.isEmpty else {
      return "No FLAC files require ALAC conversion."
    }
    return lines.joined(separator: "\n")
  }
}

public enum ConversionExecutionError: LocalizedError, Equatable, Sendable {
  case commandFailed(tool: AudioTool, exitCode: Int32, output: String)
  case destinationOutsideOutput(destination: URL, outputDirectory: URL)
  case missingConversionCommand(URL)

  public var errorDescription: String? {
    switch self {
    case let .commandFailed(tool, exitCode, output):
      let detail = output
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
      if let detail {
        return "\(tool.displayName) exited \(exitCode): \(detail)"
      }
      return "\(tool.displayName) exited \(exitCode)."
    case let .destinationOutsideOutput(destination, outputDirectory):
      return
        "\(destination.path(percentEncoded: false)) is outside \(outputDirectory.path(percentEncoded: false))."
    case let .missingConversionCommand(url):
      return "No conversion command was built for \(url.path(percentEncoded: false))."
    }
  }
}
