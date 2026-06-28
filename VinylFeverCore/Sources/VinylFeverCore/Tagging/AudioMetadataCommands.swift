import Foundation

public enum AudioMetadataCommands {
  public static func flacTagExport(url: URL, toolPaths: AudioToolPaths) throws -> ScriptCommand {
    ScriptCommand(
      tool: .metaflac,
      executableURL: try toolPaths.executableURL(for: .metaflac),
      arguments: [
        "--export-tags-to=-",
        url.path(percentEncoded: false),
      ]
    )
  }

  public static func flacStreamInfo(url: URL, toolPaths: AudioToolPaths) throws -> ScriptCommand {
    ScriptCommand(
      tool: .metaflac,
      executableURL: try toolPaths.executableURL(for: .metaflac),
      arguments: [
        "--show-total-samples",
        "--show-sample-rate",
        url.path(percentEncoded: false),
      ]
    )
  }

  public static func flacPictureList(url: URL, toolPaths: AudioToolPaths) throws -> ScriptCommand {
    ScriptCommand(
      tool: .metaflac,
      executableURL: try toolPaths.executableURL(for: .metaflac),
      arguments: [
        "--list",
        "--block-type=PICTURE",
        url.path(percentEncoded: false),
      ]
    )
  }

  public static func ffprobeJSON(url: URL, toolPaths: AudioToolPaths) throws -> ScriptCommand {
    ScriptCommand(
      tool: .ffprobe,
      executableURL: try toolPaths.executableURL(for: .ffprobe),
      arguments: [
        "-v",
        "error",
        "-show_format",
        "-show_streams",
        "-of",
        "json",
        url.path(percentEncoded: false),
      ]
    )
  }
}
