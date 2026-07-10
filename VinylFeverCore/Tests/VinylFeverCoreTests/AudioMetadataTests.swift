import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite struct AudioMetadataTests {
  @Test
  func constructsReadOnlyMetadataCommands() throws {
    let toolPaths = AudioToolPaths(paths: [
      .metaflac: "/tools/metaflac",
      .ffprobe: "/tools/ffprobe",
    ])
    let flacURL = URL(fileURLWithPath: "/Shows/1996/01.flac")
    let mp3URL = URL(fileURLWithPath: "/Shows/1996/01.mp3")

    expectNoDifference(
      try AudioMetadataCommands.flacTagExport(url: flacURL, toolPaths: toolPaths),
      ScriptCommand(
        tool: .metaflac,
        executableURL: URL(fileURLWithPath: "/tools/metaflac"),
        arguments: ["--export-tags-to=-", "/Shows/1996/01.flac"]
      )
    )
    expectNoDifference(
      try AudioMetadataCommands.flacStreamInfo(url: flacURL, toolPaths: toolPaths).arguments,
      ["--show-total-samples", "--show-sample-rate", "/Shows/1996/01.flac"]
    )
    expectNoDifference(
      try AudioMetadataCommands.flacPictureList(url: flacURL, toolPaths: toolPaths).arguments,
      ["--list", "--block-type=PICTURE", "/Shows/1996/01.flac"]
    )
    expectNoDifference(
      try AudioMetadataCommands.ffprobeJSON(url: mp3URL, toolPaths: toolPaths).arguments,
      [
        "-v",
        "error",
        "-show_format",
        "-show_streams",
        "-of",
        "json",
        "/Shows/1996/01.mp3",
      ]
    )
  }

  @Test
  func parsesFLACTagsDurationArtworkAndMultiValues() {
    let tags = FLACMetadataParser.parse(
      tagsOutput: """
        TITLE=Mandolin Rain
        ARTIST=Bruce Hornsby
        ARTIST=The Range
        ALBUM=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)
        ALBUMARTIST=Bruce Hornsby
        COMMENT=Transferred from the source tape
        TRACKNUMBER=02/12
        DISCNUMBER=1
        """,
      streamInfoOutput: """
        12348000
        44100
        """,
      pictureListOutput: """
        METADATA block #2
          type: 3 (Cover (front))
          MIME type: image/jpeg
        """
    )

    expectNoDifference(
      tags,
      AudioTags(
        title: "Mandolin Rain",
        artist: "Bruce Hornsby / The Range",
        album: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        albumArtist: "Bruce Hornsby",
        comments: "Transferred from the source tape",
        trackNumber: 2,
        trackTotal: 12,
        discNumber: 1,
        durationSeconds: 280,
        hasAudioStream: true,
        hasEmbeddedArtwork: true
      )
    )
  }

  @Test
  func parsesMissingFLACTagsAndNoArtwork() {
    let tags = FLACMetadataParser.parse(
      tagsOutput: "",
      streamInfoOutput: "",
      pictureListOutput: ""
    )

    expectNoDifference(tags, AudioTags())
  }

  @Test
  func parsesZeroSampleFLACAsAudioStreamWithZeroDuration() {
    let tags = FLACMetadataParser.parse(
      tagsOutput: "",
      streamInfoOutput: """
        0
        44100
        """,
      pictureListOutput: ""
    )

    expectNoDifference(
      tags,
      AudioTags(
        durationSeconds: 0,
        hasAudioStream: true
      )
    )
  }

  @Test
  func combinedOutputTextSeparatesStdoutAndStderr() {
    let command = ScriptCommand(
      tool: .ffprobe,
      executableURL: URL(fileURLWithPath: "/tools/ffprobe"),
      arguments: ["--version"]
    )
    let result = ScriptResult(
      command: command,
      exitCode: 1,
      standardOutput: Data("stdout".utf8),
      standardError: Data("stderr".utf8)
    )

    expectNoDifference(result.combinedOutputText, "stdout\nstderr")
  }

  @Test
  func parsesFFProbeJSON() throws {
    let json = Data(
      """
      {
        "streams": [
          {
            "codec_type": "audio",
            "duration": "215.500000"
          },
          {
            "codec_type": "video",
            "disposition": { "attached_pic": 1 }
          }
        ],
        "format": {
          "duration": "216.000000",
          "tags": {
            "title": "Every Little Kiss",
            "artist": "Bruce Hornsby and The Range",
            "album": "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
            "album_artist": "Bruce Hornsby",
            "comment": "Transferred from the source tape",
            "track": "03/10",
            "disc": "1"
          }
        }
      }
      """.utf8
    )

    expectNoDifference(
      try FFProbeMetadataParser.parse(json),
      AudioTags(
        title: "Every Little Kiss",
        artist: "Bruce Hornsby and The Range",
        album: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        albumArtist: "Bruce Hornsby",
        comments: "Transferred from the source tape",
        trackNumber: 3,
        trackTotal: 10,
        discNumber: 1,
        durationSeconds: 216,
        hasAudioStream: true,
        hasEmbeddedArtwork: true
      )
    )
  }

  @Test
  func audioMetadataClientReadsFLACThroughScriptClient() async throws {
    let recorder = CommandRecorder()
    let toolPaths = AudioToolPaths(paths: [.metaflac: "/tools/metaflac"])
    let file = ScannedAudioFile(
      id: UUID(1),
      url: URL(fileURLWithPath: "/Shows/1996/01.flac"),
      format: .flac,
      sortKey: "01.flac"
    )

    let tags = try await withDependencies {
      $0.scriptClient.run = { command in
        await recorder.append(command)
        switch command.arguments.first {
        case "--export-tags-to=-":
          return ScriptResult(
            command: command,
            exitCode: 0,
            standardOutput: Data("TITLE=The Way It Is\nTRACKNUMBER=1\n".utf8),
            standardError: Data()
          )
        case "--show-total-samples":
          return ScriptResult(
            command: command,
            exitCode: 0,
            standardOutput: Data("44100\n44100\n".utf8),
            standardError: Data()
          )
        case "--list":
          return ScriptResult(command: command, exitCode: 0, standardOutput: Data(), standardError: Data())
        default:
          return ScriptResult(
            command: command,
            exitCode: 64,
            standardOutput: Data(),
            standardError: Data("unexpected command".utf8)
          )
        }
      }
    } operation: {
      try await AudioMetadataClient.liveValue.read(
        AudioMetadataRequest(file: file, toolPaths: toolPaths)
      )
    }

    expectNoDifference(
      tags,
      AudioTags(
        title: "The Way It Is",
        trackNumber: 1,
        durationSeconds: 1,
        hasAudioStream: true
      )
    )
    let recordedArguments = await recorder.snapshot().map(\.arguments.first)
    expectNoDifference(recordedArguments, ["--export-tags-to=-", "--show-total-samples", "--list"])
  }
}

private actor CommandRecorder {
  private var commands: [ScriptCommand] = []

  func append(_ command: ScriptCommand) {
    commands.append(command)
  }

  func snapshot() -> [ScriptCommand] {
    commands
  }
}
