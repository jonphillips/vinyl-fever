import Dependencies
import Foundation

public struct ApplyExecutor: Sendable {
  @Dependency(\.fileOperationClient) private var fileOperationClient
  @Dependency(\.runLogClient) private var runLogClient
  @Dependency(\.scriptClient) private var scriptClient

  public init() {
  }

  public func apply(_ plan: ApplyPlan, toolPaths: AudioToolPaths) async throws -> ApplyResult {
    let taggingPlans = try taggingPlans(for: plan, toolPaths: toolPaths)
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .apply,
        command: commandText(for: plan, taggingPlans: taggingPlans)
      )
    )

    do {
      try Task.checkCancellation()
      try validateWorkingDestinations(in: plan)

      let conflicts = try await existingWorkingDestinations(in: plan)
      if !conflicts.isEmpty {
        let result = try await recordConflictResult(run: run, plan: plan, conflicts: conflicts)
        return result
      }

      try await fileOperationClient.createDirectory(plan.workingDirectory)
      var appliedTracks: [AppliedTrack] = []
      for track in plan.tracks {
        try Task.checkCancellation()
        let outcome = await apply(track: track, taggingPlan: taggingPlans[track.id])
        appliedTracks.append(outcome)
        try await append(outcome: outcome, run: run)
      }

      let exitSummary = exitSummary(for: appliedTracks)
      let closedRun = try await close(run: run, exitSummary: exitSummary)
      return ApplyResult(run: closedRun, appliedTracks: appliedTracks, exitSummary: exitSummary)
    } catch is CancellationError {
      _ = try? await close(run: run, exitSummary: "cancelled")
      throw CancellationError()
    } catch {
      _ = try? await close(run: run, exitSummary: error.localizedDescription)
      throw error
    }
  }

  private func taggingPlans(
    for plan: ApplyPlan,
    toolPaths: AudioToolPaths
  ) throws -> [ApplyTrackPlan.ID: TaggingCommandPlan] {
    try Dictionary(
      uniqueKeysWithValues: plan.tracks.map { track in
        (track.id, try AudioTaggingCommands.plan(for: track, toolPaths: toolPaths))
      }
    )
  }

  private func validateWorkingDestinations(in plan: ApplyPlan) throws {
    var workingPath = plan.workingDirectory
      .standardizedFileURL
      .path(percentEncoded: false)
    if workingPath.hasSuffix("/") {
      workingPath.removeLast()
    }
    for track in plan.tracks {
      let destinationPath = track.workingFile.standardizedFileURL.path(percentEncoded: false)
      guard destinationPath.hasPrefix(workingPath + "/") else {
        throw ApplyExecutionError.destinationOutsideWorking(
          destination: track.workingFile,
          workingDirectory: plan.workingDirectory
        )
      }
    }
  }

  private func existingWorkingDestinations(in plan: ApplyPlan) async throws -> [URL] {
    var conflicts: [URL] = []
    for track in plan.tracks {
      if try await fileOperationClient.fileExists(track.workingFile) {
        conflicts.append(track.workingFile)
      }
    }
    return conflicts
  }

  private func recordConflictResult(
    run: RunRecord,
    plan: ApplyPlan,
    conflicts: [URL]
  ) async throws -> ApplyResult {
    let conflictSet = Set(conflicts.map { $0.standardizedFileURL.path(percentEncoded: false) })
    let appliedTracks = plan.tracks.map { track in
      let destinationPath = track.workingFile.standardizedFileURL.path(percentEncoded: false)
      let note =
        if conflictSet.contains(destinationPath) {
          "Destination already exists."
        } else {
          "Skipped because another destination already exists."
        }
      return AppliedTrack(
        id: track.id,
        sourceURL: track.sourceFile.url,
        workingURL: track.workingFile,
        status: .skipped,
        note: note
      )
    }
    for outcome in appliedTracks {
      try await append(outcome: outcome, run: run)
    }
    let exitSummary = "\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s")"
    let closedRun = try await close(run: run, exitSummary: exitSummary)
    return ApplyResult(run: closedRun, appliedTracks: appliedTracks, exitSummary: exitSummary)
  }

  private func apply(
    track: ApplyTrackPlan,
    taggingPlan: TaggingCommandPlan?
  ) async -> AppliedTrack {
    do {
      try await fileOperationClient.copyFile(track.sourceFile.url, track.workingFile)
      guard let taggingPlan else {
        throw ApplyExecutionError.missingTaggingPlan(track.workingFile)
      }
      try await run(taggingPlan)
      return AppliedTrack(
        id: track.id,
        sourceURL: track.sourceFile.url,
        workingURL: track.workingFile,
        status: .created,
        note: "Copied and tagged."
      )
    } catch is CancellationError {
      return AppliedTrack(
        id: track.id,
        sourceURL: track.sourceFile.url,
        workingURL: track.workingFile,
        status: .failed,
        note: "Apply was cancelled."
      )
    } catch {
      return AppliedTrack(
        id: track.id,
        sourceURL: track.sourceFile.url,
        workingURL: track.workingFile,
        status: .failed,
        note: error.localizedDescription
      )
    }
  }

  private func run(_ taggingPlan: TaggingCommandPlan) async throws {
    for step in taggingPlan.steps {
      let result = try await scriptClient.run(step.command)
      if !result.isSuccessful && !step.allowsFailure {
        throw ApplyExecutionError.commandFailed(
          tool: step.command.tool,
          exitCode: result.exitCode,
          output: result.combinedOutputText
        )
      }
    }

    if let replacement = taggingPlan.replacement {
      try await fileOperationClient.replaceFile(replacement.source, replacement.destination)
    }
  }

  private func append(outcome: AppliedTrack, run: RunRecord) async throws {
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: outcome.sourceURL.path(percentEncoded: false),
        producedPath: outcome.workingURL.path(percentEncoded: false),
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

  private func exitSummary(for appliedTracks: [AppliedTrack]) -> String {
    let failedCount = appliedTracks.count { $0.status == .failed }
    let skippedCount = appliedTracks.count { $0.status == .skipped }
    if failedCount == 0 && skippedCount == 0 {
      return "ok"
    }
    var parts: [String] = []
    if failedCount > 0 {
      parts.append("\(failedCount) of \(appliedTracks.count) failed")
    }
    if skippedCount > 0 {
      parts.append("\(skippedCount) skipped")
    }
    return parts.joined(separator: ", ")
  }

  private func commandText(
    for plan: ApplyPlan,
    taggingPlans: [ApplyTrackPlan.ID: TaggingCommandPlan]
  ) -> String {
    plan.tracks.flatMap { track -> [String] in
      var lines = [
        "copy \(track.sourceFile.url.path(percentEncoded: false)) -> \(track.workingFile.path(percentEncoded: false))",
      ]
      if let taggingPlan = taggingPlans[track.id] {
        lines += taggingPlan.commands.map(\.commandLine)
        if let replacement = taggingPlan.replacement {
          lines.append(
            "replace \(replacement.source.path(percentEncoded: false)) -> \(replacement.destination.path(percentEncoded: false))"
          )
        }
      }
      return lines
    }
    .joined(separator: "\n")
  }
}

public enum ApplyExecutionError: LocalizedError, Equatable, Sendable {
  case commandFailed(tool: AudioTool, exitCode: Int32, output: String)
  case destinationOutsideWorking(destination: URL, workingDirectory: URL)
  case missingTaggingPlan(URL)

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
    case let .destinationOutsideWorking(destination, workingDirectory):
      return
        "\(destination.path(percentEncoded: false)) is outside \(workingDirectory.path(percentEncoded: false))."
    case let .missingTaggingPlan(url):
      return "No tagging command was built for \(url.path(percentEncoded: false))."
    }
  }
}
