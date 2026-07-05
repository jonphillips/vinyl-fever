import AppKit
import Foundation
import VinylFeverCore

extension ScriptClient {
  static var liveValue: Self {
    Self { command in
      try await LiveProcessRunner().run(command)
    }
  }
}

extension ToolPathClient {
  static var liveValue: Self {
    Self { overrides in
      try await LiveToolPathResolver().resolveTools(overrides: overrides)
    }
  }
}

extension FileOperationClient {
  static var liveValue: Self {
    Self(
      fileExists: { url in
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      },
      createDirectory: { url in
        try FileManager.default.createDirectory(
          at: url,
          withIntermediateDirectories: true
        )
      },
      directoryFiles: { url in
        let contents = try FileManager.default.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )
        return try contents.filter { file in
          let resourceValues = try file.resourceValues(forKeys: [.isDirectoryKey])
          return resourceValues.isDirectory != true
        }
      },
      copyFile: { source, destination in
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
          throw FileOperationError.destinationExists(destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
      },
      replaceFile: { source, destination in
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else {
          throw FileOperationError.replacementSourceMissing(source)
        }
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
      },
      removeItem: { url in
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
          return
        }
        try FileManager.default.removeItem(at: url)
      },
      writeData: { data, destination in
        try data.write(to: destination, options: [.atomic])
      },
      reveal: { url in
        await MainActor.run {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        }
      }
    )
  }
}

private struct LiveToolPathResolver: Sendable {
  func resolveTools(overrides: ToolPathOverrides) async throws -> [ToolStatus] {
    let environmentPath = ProcessInfo.processInfo.environment["PATH"]
    let resolver = ToolPathResolver(
      environmentPath: environmentPath,
      isExecutableFile: { path in
        FileManager.default.isExecutableFile(atPath: path)
      }
    )

    return try await withThrowingTaskGroup(of: ToolStatus.self) { group in
      for tool in AudioTool.allCases {
        group.addTask {
          try Task.checkCancellation()
          let resolution = resolver.resolve(tool: tool, overrides: overrides)
          guard let resolvedPath = resolution.resolvedPath else {
            return resolution.status(version: nil)
          }

          do {
            let output = try await Self.runVersionCommand(tool: tool, resolvedPath: resolvedPath)
            return resolution.status(version: tool.parseVersion(from: output))
          } catch {
            return resolution.status(
              version: nil,
              errorMessage: "Version check failed: \(error.localizedDescription)"
            )
          }
        }
      }

      var statuses: [AudioTool: ToolStatus] = [:]
      for try await status in group {
        statuses[status.tool] = status
      }

      return AudioTool.allCases.compactMap { statuses[$0] }
    }
  }

  private static func runVersionCommand(tool: AudioTool, resolvedPath: String) async throws -> String {
    let command = ScriptCommand(
      tool: tool,
      executableURL: URL(fileURLWithPath: resolvedPath),
      arguments: tool.versionArguments
    )
    let result = try await LiveProcessRunner().run(command)
    let output = result.combinedOutputText
    guard result.isSuccessful else {
      throw ToolVersionError(
        executableName: tool.executableName,
        exitCode: result.exitCode,
        output: output
      )
    }
    return output
  }
}

private struct ToolVersionError: LocalizedError {
  var executableName: String
  var exitCode: Int32
  var output: String

  var errorDescription: String? {
    let detail = output
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first(where: { !$0.isEmpty })
    if let detail {
      return "\(executableName) exited \(exitCode): \(detail)"
    }
    return "\(executableName) exited \(exitCode)"
  }
}

private struct LiveProcessRunner: Sendable {
  func run(_ command: ScriptCommand) async throws -> ScriptResult {
    let process = Process()
    process.executableURL = command.executableURL
    process.arguments = command.arguments
    if let workingDirectory = command.workingDirectory {
      process.currentDirectoryURL = workingDirectory
    }
    if !command.environment.isEmpty {
      process.environment = ProcessInfo.processInfo.environment.merging(command.environment) { _, new in
        new
      }
    }

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ScriptResult, Error>) in
        // Pipe output is drained through `readabilityHandler` and process exit is
        // observed through `terminationHandler`. Both fire on Dispatch-managed
        // threads, so we never occupy a Swift-concurrency cooperative thread with a
        // blocking `readToEnd()`/`waitUntilExit()` — the source of the intermittent
        // apply-loop stalls. The continuation resumes exactly once, when both pipes
        // have reached EOF and the process has terminated.
        let coordinator = ProcessOutputCoordinator { output, error, exitCode in
          continuation.resume(
            returning: ScriptResult(
              command: command,
              exitCode: exitCode,
              standardOutput: output,
              standardError: error
            )
          )
        }

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
          let data = handle.availableData
          if data.isEmpty {
            handle.readabilityHandler = nil
            coordinator.finishStandardOutput()
          } else {
            coordinator.appendStandardOutput(data)
          }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
          let data = handle.availableData
          if data.isEmpty {
            handle.readabilityHandler = nil
            coordinator.finishStandardError()
          } else {
            coordinator.appendStandardError(data)
          }
        }
        process.terminationHandler = { process in
          coordinator.finish(exitCode: process.terminationStatus)
        }

        do {
          try process.run()
        } catch {
          standardOutput.fileHandleForReading.readabilityHandler = nil
          standardError.fileHandleForReading.readabilityHandler = nil
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      process.terminate()
    }
  }
}

/// Thread-safe accumulator that resumes a process's continuation once stdout EOF,
/// stderr EOF, and process termination have all been observed. The completion
/// handler is invoked exactly once, outside the lock.
private final class ProcessOutputCoordinator: @unchecked Sendable {
  private let lock = NSLock()
  private var standardOutput = Data()
  private var standardError = Data()
  private var standardOutputFinished = false
  private var standardErrorFinished = false
  private var exitCode: Int32?
  private var didComplete = false
  private let onComplete: @Sendable (Data, Data, Int32) -> Void

  init(onComplete: @escaping @Sendable (Data, Data, Int32) -> Void) {
    self.onComplete = onComplete
  }

  func appendStandardOutput(_ data: Data) {
    lock.lock()
    standardOutput.append(data)
    lock.unlock()
  }

  func appendStandardError(_ data: Data) {
    lock.lock()
    standardError.append(data)
    lock.unlock()
  }

  func finishStandardOutput() {
    completeIfReady { $0.standardOutputFinished = true }
  }

  func finishStandardError() {
    completeIfReady { $0.standardErrorFinished = true }
  }

  func finish(exitCode: Int32) {
    completeIfReady { $0.exitCode = exitCode }
  }

  private func completeIfReady(_ mutate: (ProcessOutputCoordinator) -> Void) {
    lock.lock()
    mutate(self)
    guard !didComplete,
      standardOutputFinished,
      standardErrorFinished,
      let exitCode
    else {
      lock.unlock()
      return
    }
    didComplete = true
    let output = standardOutput
    let error = standardError
    lock.unlock()
    onComplete(output, error, exitCode)
  }
}
