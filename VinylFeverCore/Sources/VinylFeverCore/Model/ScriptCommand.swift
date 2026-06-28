import Foundation

public struct ScriptCommand: Equatable, Sendable {
  public var tool: AudioTool
  public var executableURL: URL
  public var arguments: [String]
  public var environment: [String: String]
  public var workingDirectory: URL?

  public init(
    tool: AudioTool,
    executableURL: URL,
    arguments: [String],
    environment: [String: String] = [:],
    workingDirectory: URL? = nil
  ) {
    self.tool = tool
    self.executableURL = executableURL
    self.arguments = arguments
    self.environment = environment
    self.workingDirectory = workingDirectory
  }

  public var argv: [String] {
    [executableURL.path(percentEncoded: false)] + arguments
  }

  public var commandLine: String {
    argv.map(Self.shellEscaped).joined(separator: " ")
  }

  private static func shellEscaped(_ value: String) -> String {
    guard !value.isEmpty else {
      return "''"
    }

    let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_:=-+.,")
    if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
      return value
    }

    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

public struct ScriptResult: Equatable, Sendable {
  public var command: ScriptCommand
  public var exitCode: Int32
  public var standardOutput: Data
  public var standardError: Data

  public init(
    command: ScriptCommand,
    exitCode: Int32,
    standardOutput: Data,
    standardError: Data
  ) {
    self.command = command
    self.exitCode = exitCode
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  public var isSuccessful: Bool {
    exitCode == 0
  }

  public var standardOutputText: String {
    String(data: standardOutput, encoding: .utf8) ?? ""
  }

  public var standardErrorText: String {
    String(data: standardError, encoding: .utf8) ?? ""
  }

  public var combinedOutputText: String {
    if standardOutputText.isEmpty {
      return standardErrorText
    }
    if standardErrorText.isEmpty {
      return standardOutputText
    }
    return standardOutputText + "\n" + standardErrorText
  }
}

public struct AudioToolPaths: Equatable, Sendable {
  public var paths: [AudioTool: String]

  public init(paths: [AudioTool: String]) {
    self.paths = paths
  }

  public init(statuses: [ToolStatus]) {
    self.paths = Dictionary(
      uniqueKeysWithValues: statuses.compactMap { status in
        status.resolvedPath.map { (status.tool, $0) }
      }
    )
  }

  public func path(for tool: AudioTool) throws -> String {
    guard let path = paths[tool] else {
      throw AudioMetadataError.missingTool(tool)
    }
    return path
  }

  public func executableURL(for tool: AudioTool) throws -> URL {
    URL(fileURLWithPath: try path(for: tool))
  }
}
