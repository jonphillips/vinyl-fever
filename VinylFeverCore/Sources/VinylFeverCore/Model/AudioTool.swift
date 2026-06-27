import Foundation

public enum AudioTool: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
  case metaflac
  case ffmpeg
  case ffprobe

  public var id: Self { self }

  public var executableName: String {
    rawValue
  }

  public var displayName: String {
    switch self {
    case .metaflac:
      "metaflac"
    case .ffmpeg:
      "ffmpeg"
    case .ffprobe:
      "ffprobe"
    }
  }

  public var installHint: String {
    switch self {
    case .metaflac:
      "brew install flac"
    case .ffmpeg, .ffprobe:
      "brew install ffmpeg"
    }
  }

  public var versionArguments: [String] {
    switch self {
    case .metaflac:
      ["--version"]
    case .ffmpeg, .ffprobe:
      ["-version"]
    }
  }

  public func parseVersion(from output: String) -> String? {
    guard let line = output
      .split(whereSeparator: \.isNewline)
      .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
      .first(where: { !$0.isEmpty })
    else {
      return nil
    }

    if let copyrightRange = line.range(of: " Copyright") {
      return String(line[..<copyrightRange.lowerBound])
    }
    return line
  }
}
