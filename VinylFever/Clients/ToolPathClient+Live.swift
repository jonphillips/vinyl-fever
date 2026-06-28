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

    try process.run()
    do {
      return try await withTaskCancellationHandler {
        try await collectResult(
          for: process,
          command: command,
          standardOutput: standardOutput,
          standardError: standardError
        )
      } onCancel: {
        process.terminate()
      }
    } catch {
      if process.isRunning {
        process.terminate()
      }
      throw error
    }
  }

  private func collectResult(
    for process: Process,
    command: ScriptCommand,
    standardOutput: Pipe,
    standardError: Pipe
  ) async throws -> ScriptResult {
    try await withThrowingTaskGroup(of: ProcessEvent.self) { group in
      group.addTask {
        .standardOutput(try standardOutput.fileHandleForReading.readToEnd() ?? Data())
      }
      group.addTask {
        .standardError(try standardError.fileHandleForReading.readToEnd() ?? Data())
      }
      group.addTask {
        process.waitUntilExit()
        return .exit(process.terminationStatus)
      }

      var output = Data()
      var error = Data()
      var exitCode: Int32?
      for try await event in group {
        switch event {
        case let .standardOutput(data):
          output = data
        case let .standardError(data):
          error = data
        case let .exit(status):
          exitCode = status
        }
      }

      return ScriptResult(
        command: command,
        exitCode: exitCode ?? process.terminationStatus,
        standardOutput: output,
        standardError: error
      )
    }
  }
}

private enum ProcessEvent: Sendable {
  case standardOutput(Data)
  case standardError(Data)
  case exit(Int32)
}
