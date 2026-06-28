import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct ApplyIntegrationTests {
  @Test
  func realToolIntegrationCopiesTagsAndEmbedsCoverForGeneratedFLAC() async throws {
    guard
      let ffmpegURL = firstExecutable(named: "ffmpeg"),
      let metaflacURL = firstExecutable(named: "metaflac")
    else {
      return
    }

    let root = try temporaryDirectory()
    let sourceURL = root.appendingPathComponent("source.flac")
    let coverURL = root.appendingPathComponent("front.jpg")
    _ = try runProcess(
      executableURL: ffmpegURL,
      arguments: [
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "anullsrc=channel_layout=mono:sample_rate=44100",
        "-t",
        "0.1",
        "-c:a",
        "flac",
        sourceURL.path(percentEncoded: false),
      ]
    )
    _ = try runProcess(
      executableURL: ffmpegURL,
      arguments: [
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=c=red:s=32x32",
        "-frames:v",
        "1",
        coverURL.path(percentEncoded: false),
      ]
    )

    let showPlan = ShowPlan(
      folder: ScannedShowFolder(
        root: root,
        audioFiles: [
          ScannedAudioFile(id: UUID(1), url: sourceURL, format: .flac, sortKey: "source.flac"),
        ],
        setlistCandidates: [],
        coverCandidates: [coverURL]
      ),
      setlist: SetlistDraft(
        tags: standardShowTags,
        tracks: [
          SetlistTrack(id: UUID(101), title: "The Way It Is"),
        ]
      ),
      metadata: ShowMetadata(
        tags: standardShowTags,
        source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true)
      )
    )
    let runLog = RunLogRecorder()
    let applyPlan = ApplyPlan(showPlan: showPlan, showRoot: root, coverURL: coverURL)

    let result = try await withDependencies {
      $0.fileOperationClient.fileExists = { url in
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }
      $0.fileOperationClient.createDirectory = { url in
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      }
      $0.fileOperationClient.copyFile = { source, destination in
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
          throw FileOperationError.destinationExists(destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
      }
      $0.fileOperationClient.replaceFile = { source, destination in
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
      }
      $0.scriptClient.run = { command in
        let output = try runProcess(executableURL: command.executableURL, arguments: command.arguments)
        return ScriptResult(
          command: command,
          exitCode: output.exitCode,
          standardOutput: output.standardOutput,
          standardError: output.standardError
        )
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await ApplyExecutor().apply(
        applyPlan,
        toolPaths: AudioToolPaths(paths: [.metaflac: metaflacURL.path(percentEncoded: false)])
      )
    }

    let workingURL = root
      .appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
      .appendingPathComponent("01 - The Way It Is.flac")
    let tagOutput = try runProcess(
      executableURL: metaflacURL,
      arguments: ["--export-tags-to=-", workingURL.path(percentEncoded: false)]
    )
    let pictureOutput = try runProcess(
      executableURL: metaflacURL,
      arguments: ["--list", "--block-type=PICTURE", workingURL.path(percentEncoded: false)]
    )
    let tags = FLACMetadataParser.parse(
      tagsOutput: String(data: tagOutput.standardOutput, encoding: .utf8) ?? "",
      streamInfoOutput: "",
      pictureListOutput: String(data: pictureOutput.standardOutput, encoding: .utf8) ?? ""
    )

    expectNoDifference(result.exitSummary, "ok")
    expectNoDifference(FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)), true)
    expectNoDifference(FileManager.default.fileExists(atPath: workingURL.path(percentEncoded: false)), true)
    expectNoDifference(tags.title, "The Way It Is")
    expectNoDifference(tags.album, "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)")
    expectNoDifference(tags.artist, "Bruce Hornsby and The Range")
    expectNoDifference(tags.albumArtist, "Bruce Hornsby")
    expectNoDifference(tags.trackNumber, 1)
    expectNoDifference(tags.trackTotal, 1)
    expectNoDifference(tags.discNumber, 1)
    expectNoDifference(tags.hasEmbeddedArtwork, true)
  }
}
