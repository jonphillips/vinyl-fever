import Foundation

public struct ToolPathResolver: Sendable {
  public static let defaultSearchDirectories = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
  ]

  public var searchDirectories: [String]
  public var environmentPath: String?
  public var isExecutableFile: @Sendable (String) -> Bool

  public init(
    searchDirectories: [String] = Self.defaultSearchDirectories,
    environmentPath: String? = nil,
    isExecutableFile: @escaping @Sendable (String) -> Bool
  ) {
    self.searchDirectories = searchDirectories
    self.environmentPath = environmentPath
    self.isExecutableFile = isExecutableFile
  }

  public func resolve(tool: AudioTool, overrides: ToolPathOverrides) -> ToolPathResolution {
    if let overridePath = overrides.path(for: tool) {
      guard isExecutableFile(overridePath) else {
        return ToolPathResolution(
          tool: tool,
          resolvedPath: nil,
          source: .userOverride,
          issue: .overrideNotExecutable(path: overridePath)
        )
      }

      return ToolPathResolution(
        tool: tool,
        resolvedPath: overridePath,
        source: .userOverride,
        issue: nil
      )
    }

    for directory in searchDirectories {
      let candidate = Self.executablePath(tool.executableName, in: directory)
      if isExecutableFile(candidate) {
        return ToolPathResolution(
          tool: tool,
          resolvedPath: candidate,
          source: .discovered(directory: directory),
          issue: nil
        )
      }
    }

    for directory in pathDirectories {
      let candidate = Self.executablePath(tool.executableName, in: directory)
      if isExecutableFile(candidate) {
        return ToolPathResolution(
          tool: tool,
          resolvedPath: candidate,
          source: .pathEnvironment(directory: directory),
          issue: nil
        )
      }
    }

    return ToolPathResolution(
      tool: tool,
      resolvedPath: nil,
      source: .missing,
      issue: .notFound
    )
  }

  private var pathDirectories: [String] {
    environmentPath?
      .split(separator: ":")
      .map(String.init)
      .filter { !$0.isEmpty } ?? []
  }

  private static func executablePath(_ executableName: String, in directory: String) -> String {
    var directory = directory
    while directory.hasSuffix("/") {
      directory.removeLast()
    }
    return "\(directory)/\(executableName)"
  }
}

public struct ToolPathResolution: Equatable, Sendable {
  public var tool: AudioTool
  public var resolvedPath: String?
  public var source: ToolStatus.Source
  public var issue: Issue?

  public init(
    tool: AudioTool,
    resolvedPath: String?,
    source: ToolStatus.Source,
    issue: Issue?
  ) {
    self.tool = tool
    self.resolvedPath = resolvedPath
    self.source = source
    self.issue = issue
  }

  public func status(version: String?, errorMessage: String? = nil) -> ToolStatus {
    ToolStatus(
      tool: tool,
      resolvedPath: resolvedPath,
      version: version,
      source: source,
      errorMessage: errorMessage ?? issue?.message(for: tool)
    )
  }

  public enum Issue: Equatable, Sendable {
    case overrideNotExecutable(path: String)
    case notFound

    public func message(for tool: AudioTool) -> String {
      switch self {
      case let .overrideNotExecutable(path):
        "Override path is not executable: \(path)"
      case .notFound:
        "Not found. \(tool.installHint)."
      }
    }
  }
}
