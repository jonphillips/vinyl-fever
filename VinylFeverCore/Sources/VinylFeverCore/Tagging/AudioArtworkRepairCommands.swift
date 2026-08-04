import Foundation

/// Commands that repair an app-owned staged copy when its embedded artwork prevents ffmpeg from
/// rewriting its tags. The command copies only the audio stream and container-level metadata, so
/// the replacement has no attached-picture stream while the original dropped file is untouched.
public enum AudioArtworkRepairCommands {
  public static func stripEmbeddedArtwork(
    from sourceURL: URL,
    to replacementURL: URL,
    format: AudioFormat,
    toolPaths: AudioToolPaths
  ) throws -> ScriptCommand {
    guard format == .mp3 || format == .m4a else {
      throw AudioArtworkRepairError.unsupportedFormat(format)
    }

    var arguments = [
      "-nostdin",
      "-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-i",
      sourceURL.path(percentEncoded: false),
      "-map",
      "0:a?",
      "-map_metadata",
      "0",
      "-c",
      "copy",
    ]
    if format == .m4a {
      arguments += ["-movflags", "use_metadata_tags"]
    }
    arguments.append(replacementURL.path(percentEncoded: false))

    return ScriptCommand(
      tool: .ffmpeg,
      executableURL: try toolPaths.executableURL(for: .ffmpeg),
      arguments: arguments
    )
  }
}

public enum AudioArtworkRepairError: LocalizedError, Equatable, Sendable {
  case unsupportedFormat(AudioFormat)
  case commandFailed(tool: AudioTool, exitCode: Int32, output: String)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedFormat(format):
      return "Removing embedded artwork is not supported for .\(format.rawValue) files."
    case let .commandFailed(tool, exitCode, output):
      let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
      if detail.isEmpty {
        return "\(tool.displayName) exited \(exitCode)."
      }
      return "\(tool.displayName) exited \(exitCode): \(detail)"
    }
  }
}
