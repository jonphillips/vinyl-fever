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
    var arguments: [String] = []
    appendFLACTag("TITLE", value: tags.title, field: .title, tags: tags, to: &arguments)
    appendFLACTag("ALBUM", value: tags.album, field: .album, tags: tags, to: &arguments)
    appendFLACTag("ALBUMSORT", value: tags.sortAlbum, field: .sortAlbum, tags: tags, to: &arguments)
    appendFLACTag("ARTIST", value: tags.artist, field: .artist, tags: tags, to: &arguments)
    appendFLACTag("ALBUMARTIST", value: tags.albumArtist, field: .albumArtist, tags: tags, to: &arguments)
    appendFLACTag("GROUPING", value: tags.grouping, field: .grouping, tags: tags, to: &arguments)
    appendFLACTag(
      "COMPILATION",
      value: tags.isCompilation == true ? "1" : nil,
      field: .isCompilation,
      tags: tags,
      to: &arguments
    )
    appendFLACTag(
      "TRACKNUMBER",
      value: tags.trackNumber.map(String.init),
      field: .trackNumber,
      tags: tags,
      to: &arguments
    )
    appendFLACTag(
      "TRACKTOTAL",
      value: (tags.trackTotal ?? (tags.trackNumber == nil ? nil : trackTotal)).map(String.init),
      field: .trackTotal,
      tags: tags,
      to: &arguments
    )
    appendFLACTag(
      "DISCNUMBER",
      value: tags.discNumber.map(String.init),
      field: .discNumber,
      tags: tags,
      to: &arguments
    )
    return arguments
  }

  private static func appendFLACTag(
    _ key: String,
    value: String?,
    field: ProposedTags.Field,
    tags: ProposedTags,
    to arguments: inout [String]
  ) {
    if let value {
      arguments += ["--remove-tag=\(key)", "--set-tag=\(key)=\(value)"]
    } else if tags.clearedFields.contains(field) {
      arguments.append("--remove-tag=\(key)")
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
    var arguments: [String] = []
    appendFFmpegMetadata("title", value: track.tags.title, field: .title, tags: track.tags, to: &arguments)
    appendFFmpegMetadata("album", value: track.tags.album, field: .album, tags: track.tags, to: &arguments)
    appendFFmpegMetadata("sort_album", value: track.tags.sortAlbum, field: .sortAlbum, tags: track.tags, to: &arguments)
    appendFFmpegMetadata("artist", value: track.tags.artist, field: .artist, tags: track.tags, to: &arguments)
    appendFFmpegMetadata("album_artist", value: track.tags.albumArtist, field: .albumArtist, tags: track.tags, to: &arguments)
    appendFFmpegMetadata("grouping", value: track.tags.grouping, field: .grouping, tags: track.tags, to: &arguments)
    appendFFmpegMetadata(
      "compilation",
      value: track.tags.isCompilation.map { $0 ? "1" : "" },
      field: .isCompilation,
      tags: track.tags,
      to: &arguments
    )
    let trackValue = track.tags.trackNumber.map { "\($0)/\(track.tags.trackTotal ?? track.trackTotal)" }
    appendFFmpegMetadata("track", value: trackValue, field: .trackNumber, tags: track.tags, to: &arguments)
    appendFFmpegMetadata(
      "disc",
      value: track.tags.discNumber.map(String.init),
      field: .discNumber,
      tags: track.tags,
      to: &arguments
    )
    return arguments
  }

  private static func appendFFmpegMetadata(
    _ key: String,
    value: String?,
    field: ProposedTags.Field,
    tags: ProposedTags,
    to arguments: inout [String]
  ) {
    if let value {
      arguments += ["-metadata", "\(key)=\(value)"]
    } else if tags.clearedFields.contains(field) {
      arguments += ["-metadata", "\(key)="]
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
