import Foundation

public enum AudioConversionCommands {
  public static func alacCommand(
    for track: ConversionTrackPlan,
    toolPaths: AudioToolPaths
  ) throws -> ScriptCommand {
    guard track.action == .convertToALAC else {
      throw AudioConversionCommandError.nonConvertibleTrack(track.workingFile)
    }

    var arguments = [
      "-nostdin",
      "-hide_banner",
      "-loglevel",
      "error",
      "-i",
      track.workingFile.path(percentEncoded: false),
    ]
    if let coverURL = track.coverURL {
      arguments += [
        "-i",
        coverURL.path(percentEncoded: false),
        "-map",
        "0:a:0",
        "-map",
        "1:v:0",
      ]
    } else {
      arguments += [
        "-map",
        "0:a:0",
        "-map",
        "0:v:0?",
      ]
    }

    arguments += [
      "-map_metadata",
      "0",
      "-c:a",
      "alac",
      "-c:v",
      "mjpeg",
      "-disposition:v:0",
      "attached_pic",
    ]
    arguments += metadataArguments(for: track)
    arguments += [
      "-metadata:s:v",
      "title=Album cover",
      "-metadata:s:v",
      "comment=Cover (front)",
      "-movflags",
      "+faststart",
      track.outputFile.path(percentEncoded: false),
    ]

    return ScriptCommand(
      tool: .ffmpeg,
      executableURL: try toolPaths.executableURL(for: .ffmpeg),
      arguments: arguments
    )
  }

  private static func metadataArguments(for track: ConversionTrackPlan) -> [String] {
    [
      ("title", track.tags.title),
      ("album", track.tags.album),
      ("sort_album", track.tags.sortAlbum),
      ("artist", track.tags.artist),
      ("album_artist", track.tags.albumArtist),
      ("track", track.tags.trackNumber.map { "\($0)/\(track.tags.trackTotal ?? track.trackTotal)" }),
      ("disc", track.tags.discNumber.map(String.init)),
    ].flatMap { key, value in
      value.map { ["-metadata", "\(key)=\($0)"] } ?? []
    }
  }
}

public enum AudioConversionCommandError: LocalizedError, Equatable, Sendable {
  case nonConvertibleTrack(URL)

  public var errorDescription: String? {
    switch self {
    case let .nonConvertibleTrack(url):
      return "\(url.path(percentEncoded: false)) does not require ALAC conversion."
    }
  }
}
