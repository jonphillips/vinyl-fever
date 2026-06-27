import Foundation

public struct ToolStatus: Equatable, Identifiable, Sendable {
  public var id: AudioTool
  public var resolvedPath: String?
  public var version: String?
  public var source: Source
  public var errorMessage: String?

  public init(
    tool: AudioTool,
    resolvedPath: String?,
    version: String?,
    source: Source,
    errorMessage: String? = nil
  ) {
    self.id = tool
    self.resolvedPath = resolvedPath
    self.version = version
    self.source = source
    self.errorMessage = errorMessage
  }

  public static func missing(tool: AudioTool) -> Self {
    Self(
      tool: tool,
      resolvedPath: nil,
      version: nil,
      source: .missing,
      errorMessage: "Not found. \(tool.installHint)."
    )
  }

  public var isAvailable: Bool {
    resolvedPath != nil
  }

  public var tool: AudioTool {
    id
  }

  public enum Source: Equatable, Sendable {
    case discovered(directory: String)
    case pathEnvironment(directory: String)
    case userOverride
    case missing

    public var displayName: String {
      switch self {
      case .discovered:
        "Discovered"
      case .pathEnvironment:
        "PATH"
      case .userOverride:
        "Override"
      case .missing:
        "Missing"
      }
    }
  }
}
