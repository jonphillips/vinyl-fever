import Foundation
import VinylFeverCore

extension ToolPathClient {
  static var liveValue: Self {
    Self { overrides in
      try await LiveToolPathResolver().resolveTools(overrides: overrides)
    }
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
            let output = try Self.runVersionCommand(tool: tool, resolvedPath: resolvedPath)
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

  private static func runVersionCommand(tool: AudioTool, resolvedPath: String) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: resolvedPath)
    process.arguments = tool.versionArguments

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let output = Self.string(from: standardOutput) + Self.string(from: standardError)
    guard process.terminationStatus == 0 else {
      throw ToolVersionError(
        executableName: tool.executableName,
        exitCode: process.terminationStatus,
        output: output
      )
    }
    return output
  }

  private static func string(from pipe: Pipe) -> String {
    String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
