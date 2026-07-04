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

  @Test
  func realToolIntegrationConvertsFLACToALACAndVerifiesOutput() async throws {
    guard
      let ffmpegURL = firstExecutable(named: "ffmpeg"),
      let metaflacURL = firstExecutable(named: "metaflac"),
      let ffprobeURL = firstExecutable(named: "ffprobe")
    else {
      return
    }

    let root = try temporaryDirectory()
    let sourceURL = root.appendingPathComponent("source.flac")
    let coverURL = root.appendingPathComponent("front.jpg")
    try writeGeneratedAudio(format: .flac, at: sourceURL, ffmpegURL: ffmpegURL)
    try writeGeneratedCover(at: coverURL, ffmpegURL: ffmpegURL)

    let applyPlan = ApplyPlan(
      showPlan: makeSingleFileShowPlan(root: root, sourceURL: sourceURL, format: .flac),
      showRoot: root,
      coverURL: coverURL
    )
    let conversionPlan = ConversionPlan(applyPlan: applyPlan)
    let toolPaths = AudioToolPaths(paths: [
      .metaflac: metaflacURL.path(percentEncoded: false),
      .ffmpeg: ffmpegURL.path(percentEncoded: false),
      .ffprobe: ffprobeURL.path(percentEncoded: false),
    ])

    let result = try await withDependencies {
      $0.fileOperationClient = realFileOperationClient
      $0.scriptClient.run = { command in
        try realScriptResult(for: command)
      }
      $0.audioMetadataClient = .liveValue
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      let applyResult = try await ApplyExecutor().apply(applyPlan, toolPaths: toolPaths)
      let conversionResult = try await ConversionExecutor().convert(conversionPlan, toolPaths: toolPaths)
      let verificationResult = try await VerificationExecutor().verify(conversionPlan, toolPaths: toolPaths)
      return (applyResult, conversionResult, verificationResult)
    }

    let workingURL = conversionPlan.tracks[0].workingFile
    let outputURL = conversionPlan.tracks[0].outputFile
    expectNoDifference(result.0.didSucceed, true)
    expectNoDifference(result.1.didSucceed, true)
    expectNoDifference(result.2.didVerify, true)
    expectNoDifference(FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)), true)
    expectNoDifference(FileManager.default.fileExists(atPath: workingURL.path(percentEncoded: false)), true)
    expectNoDifference(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)), true)
    expectNoDifference(outputURL.deletingLastPathComponent(), root.appendingPathComponent("Output", isDirectory: true))
  }

  @Test
  func realToolIntegrationCopiesTagsAndEmbedsCoverForGeneratedMP3AndM4A() async throws {
    guard
      let ffmpegURL = firstExecutable(named: "ffmpeg"),
      let ffprobeURL = firstExecutable(named: "ffprobe")
    else {
      return
    }

    for format in [AudioFormat.mp3, .m4a] {
      let root = try temporaryDirectory()
      let sourceURL = root.appendingPathComponent("source.\(format.rawValue)")
      let coverURL = root.appendingPathComponent("front.jpg")
      try writeGeneratedAudio(format: format, at: sourceURL, ffmpegURL: ffmpegURL)
      try writeGeneratedCover(at: coverURL, ffmpegURL: ffmpegURL)

      let applyPlan = ApplyPlan(
        showPlan: makeSingleFileShowPlan(root: root, sourceURL: sourceURL, format: format),
        showRoot: root,
        coverURL: coverURL
      )
      let toolPaths = AudioToolPaths(paths: [
        .ffmpeg: ffmpegURL.path(percentEncoded: false),
        .ffprobe: ffprobeURL.path(percentEncoded: false),
      ])

      let tags = try await withDependencies {
        $0.fileOperationClient = realFileOperationClient
        $0.scriptClient.run = { command in
          try realScriptResult(for: command)
        }
        $0.audioMetadataClient = .liveValue
        $0.runLogClient = RunLogRecorder().client
      } operation: {
        let applyResult = try await ApplyExecutor().apply(applyPlan, toolPaths: toolPaths)
        expectNoDifference(applyResult.didSucceed, true)
        return try await AudioMetadataClient.liveValue.read(
          AudioMetadataRequest(
            url: applyPlan.tracks[0].workingFile,
            format: format,
            toolPaths: toolPaths
          )
        )
      }

      expectNoDifference(tags.title, "The Way It Is")
      expectNoDifference(tags.album, "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)")
      if format == .mp3 {
        expectNoDifference(tags.sortAlbum, "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)")
      }
      expectNoDifference(tags.artist, "Bruce Hornsby and The Range")
      expectNoDifference(tags.albumArtist, "Bruce Hornsby")
      expectNoDifference(tags.trackNumber, 1)
      expectNoDifference(tags.trackTotal, 1)
      expectNoDifference(tags.discNumber, 1)
      expectNoDifference(tags.hasEmbeddedArtwork, true)
    }
  }
}

private var realFileOperationClient: FileOperationClient {
  FileOperationClient(
    fileExists: { url in
      FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    },
    createDirectory: { url in
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    },
    directoryFiles: { url in
      try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      .filter { file in
        let resourceValues = try file.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues.isDirectory != true
      }
    },
    copyFile: { source, destination in
      guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
        throw FileOperationError.destinationExists(destination)
      }
      try FileManager.default.copyItem(at: source, to: destination)
    },
    replaceFile: { source, destination in
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
    },
    writeData: { data, destination in
      try data.write(to: destination, options: [.atomic])
    },
    reveal: { _ in }
  )
}

private func realScriptResult(for command: ScriptCommand) throws -> ScriptResult {
  let output = try runProcess(executableURL: command.executableURL, arguments: command.arguments)
  return ScriptResult(
    command: command,
    exitCode: output.exitCode,
    standardOutput: output.standardOutput,
    standardError: output.standardError
  )
}

private func makeSingleFileShowPlan(root: URL, sourceURL: URL, format: AudioFormat) -> ShowPlan {
  ShowPlan(
    folder: ScannedShowFolder(
      root: root,
      audioFiles: [
        ScannedAudioFile(
          id: UUID(1),
          url: sourceURL,
          format: format,
          sortKey: sourceURL.lastPathComponent
        ),
      ],
      setlistCandidates: [],
      coverCandidates: []
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
}

private func writeGeneratedAudio(format: AudioFormat, at url: URL, ffmpegURL: URL) throws {
  var arguments = [
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
  ]
  switch format {
  case .flac:
    arguments += ["-c:a", "flac"]
  case .mp3:
    arguments += ["-c:a", "libmp3lame", "-q:a", "9"]
  case .m4a:
    arguments += ["-c:a", "aac", "-b:a", "64k", "-f", "ipod"]
  }
  arguments.append(url.path(percentEncoded: false))
  _ = try runProcess(executableURL: ffmpegURL, arguments: arguments)
}

private func writeGeneratedCover(at url: URL, ffmpegURL: URL) throws {
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
      url.path(percentEncoded: false),
    ]
  )
}
