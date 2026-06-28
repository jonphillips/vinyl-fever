import Foundation

public enum AudioTaggingCommands {
  public static func plan(
    for track: ApplyTrackPlan,
    toolPaths: AudioToolPaths
  ) throws -> TaggingCommandPlan {
    switch track.sourceFile.format {
    case .flac:
      try flacPlan(for: track, toolPaths: toolPaths)
    case .mp3:
      try ffmpegPlan(for: track, format: .mp3, toolPaths: toolPaths)
    case .m4a:
      try ffmpegPlan(for: track, format: .m4a, toolPaths: toolPaths)
    }
  }

  private static func flacPlan(
    for track: ApplyTrackPlan,
    toolPaths: AudioToolPaths
  ) throws -> TaggingCommandPlan {
    let path = track.workingFile.path(percentEncoded: false)
    var tagArguments = flacTagArguments(tags: track.tags, trackTotal: track.trackTotal)
    tagArguments.append(path)

    var steps = [
      TaggingCommandStep(
        command: ScriptCommand(
          tool: .metaflac,
          executableURL: try toolPaths.executableURL(for: .metaflac),
          arguments: tagArguments
        ),
        allowsFailure: false
      ),
    ]

    if let coverURL = track.coverURL {
      steps.append(
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .metaflac,
            executableURL: try toolPaths.executableURL(for: .metaflac),
            arguments: ["--remove", "--block-type=PICTURE", path]
          ),
          allowsFailure: true
        )
      )
      steps.append(
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .metaflac,
            executableURL: try toolPaths.executableURL(for: .metaflac),
            arguments: [
              "--import-picture-from=\(coverURL.path(percentEncoded: false))",
              path,
            ]
          ),
          allowsFailure: false
        )
      )
    }

    return TaggingCommandPlan(steps: steps, replacement: nil)
  }

  private static func flacTagArguments(tags: ProposedTags, trackTotal: Int) -> [String] {
    [
      ("TITLE", tags.title),
      ("ALBUM", tags.album),
      ("ALBUMSORT", tags.sortAlbum),
      ("ARTIST", tags.artist),
      ("ALBUMARTIST", tags.albumArtist),
      ("TRACKNUMBER", String(tags.trackNumber)),
      ("TRACKTOTAL", String(trackTotal)),
      ("DISCNUMBER", String(tags.discNumber)),
    ].flatMap { key, value in
      ["--remove-tag=\(key)", "--set-tag=\(key)=\(value)"]
    }
  }

  private static func ffmpegPlan(
    for track: ApplyTrackPlan,
    format: AudioFormat,
    toolPaths: AudioToolPaths
  ) throws -> TaggingCommandPlan {
    let temporaryURL = tagTemporaryURL(for: track.workingFile, format: format)
    let arguments: [String]
    switch format {
    case .mp3:
      arguments = mp3Arguments(for: track, outputURL: temporaryURL)
    case .m4a:
      arguments = m4aArguments(for: track, outputURL: temporaryURL)
    case .flac:
      preconditionFailure("FLAC tagging is handled by metaflac.")
    }

    return TaggingCommandPlan(
      steps: [
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .ffmpeg,
            executableURL: try toolPaths.executableURL(for: .ffmpeg),
            arguments: arguments
          ),
          allowsFailure: false
        ),
      ],
      replacement: TaggingReplacement(source: temporaryURL, destination: track.workingFile)
    )
  }

  private static func mp3Arguments(for track: ApplyTrackPlan, outputURL: URL) -> [String] {
    var arguments = ffmpegPrefix(for: track)
    if track.coverURL != nil {
      arguments += ["-map", "0:a:0", "-map", "1:v:0"]
    } else {
      arguments += ["-map", "0:a:0", "-map", "0:v:0?"]
    }
    arguments += [
      "-c:a", "copy",
      "-c:v", "mjpeg",
      "-id3v2_version", "3",
    ]
    arguments += metadataArguments(for: track)
    arguments += [
      "-metadata:s:v", "title=Album cover",
      "-metadata:s:v", "comment=Cover (front)",
      outputURL.path(percentEncoded: false),
    ]
    return arguments
  }

  private static func m4aArguments(for track: ApplyTrackPlan, outputURL: URL) -> [String] {
    var arguments = ffmpegPrefix(for: track)
    if track.coverURL != nil {
      arguments += ["-map", "0:a:0", "-map", "1:v:0"]
    } else {
      arguments += ["-map", "0:a:0", "-map", "0:v:0?"]
    }
    arguments += [
      "-c:a", "copy",
      "-c:v", "mjpeg",
      "-disposition:v:0", "attached_pic",
      "-map_metadata", "0",
    ]
    arguments += metadataArguments(for: track)
    arguments += [
      "-metadata:s:v", "title=Album cover",
      "-metadata:s:v", "comment=Cover (front)",
      "-movflags", "+faststart",
      "-f", "ipod",
      outputURL.path(percentEncoded: false),
    ]
    return arguments
  }

  private static func ffmpegPrefix(for track: ApplyTrackPlan) -> [String] {
    var arguments = [
      "-nostdin",
      "-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-i",
      track.workingFile.path(percentEncoded: false),
    ]
    if let coverURL = track.coverURL {
      arguments += ["-i", coverURL.path(percentEncoded: false)]
    }
    return arguments
  }

  private static func metadataArguments(for track: ApplyTrackPlan) -> [String] {
    [
      ("title", track.tags.title),
      ("album", track.tags.album),
      ("sort_album", track.tags.sortAlbum),
      ("artist", track.tags.artist),
      ("album_artist", track.tags.albumArtist),
      ("track", "\(track.tags.trackNumber)/\(track.trackTotal)"),
      ("disc", String(track.tags.discNumber)),
    ].flatMap { key, value in
      ["-metadata", "\(key)=\(value)"]
    }
  }

  private static func tagTemporaryURL(for url: URL, format: AudioFormat) -> URL {
    URL(fileURLWithPath: url.path(percentEncoded: false) + ".tagtmp.\(format.rawValue)")
  }
}

public struct TaggingCommandPlan: Equatable, Sendable {
  public var steps: [TaggingCommandStep]
  public var replacement: TaggingReplacement?

  public init(steps: [TaggingCommandStep], replacement: TaggingReplacement?) {
    self.steps = steps
    self.replacement = replacement
  }

  public var commands: [ScriptCommand] {
    steps.map(\.command)
  }
}

public struct TaggingCommandStep: Equatable, Sendable {
  public var command: ScriptCommand
  public var allowsFailure: Bool

  public init(command: ScriptCommand, allowsFailure: Bool) {
    self.command = command
    self.allowsFailure = allowsFailure
  }
}

public struct TaggingReplacement: Equatable, Sendable {
  public var source: URL
  public var destination: URL

  public init(source: URL, destination: URL) {
    self.source = source
    self.destination = destination
  }
}
