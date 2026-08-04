import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct AudioTaggingCommandTests {
  @Test
  func constructsArtworkStrippingCommand() throws {
    let source = URL(fileURLWithPath: "/Inbox/broken-cover.mp3")
    let replacement = URL(fileURLWithPath: "/Inbox/.broken-cover.artwork-repair.mp3")
    let command = try AudioArtworkRepairCommands.stripEmbeddedArtwork(
      from: source,
      to: replacement,
      format: .mp3,
      toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
    )

    expectNoDifference(command.tool, .ffmpeg)
    expectNoDifference(command.executableURL, URL(fileURLWithPath: "/tools/ffmpeg"))
    expectNoDifference(
      command.arguments,
      [
        "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-i", "/Inbox/broken-cover.mp3",
        "-map", "0:a?", "-map_metadata", "0", "-c", "copy",
        "/Inbox/.broken-cover.artwork-repair.mp3",
      ]
    )
  }

  @Test
  func refusesArtworkStrippingForFLAC() throws {
    #expect(throws: AudioArtworkRepairError.unsupportedFormat(.flac)) {
      try AudioArtworkRepairCommands.stripEmbeddedArtwork(
        from: URL(fileURLWithPath: "/Inbox/broken-cover.flac"),
        to: URL(fileURLWithPath: "/Inbox/replacement.flac"),
        format: .flac,
        toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
      )
    }
  }

  @Test
  func constructsPinnedTaggingCommands() throws {
    let toolPaths = AudioToolPaths(paths: [
      .metaflac: "/tools/metaflac",
      .ffmpeg: "/tools/ffmpeg",
    ])
    let coverURL = applyShowRoot.appendingPathComponent("front.jpg")
    let flacTrack = makeApplyTrack(format: .flac, coverURL: coverURL)
    let mp3Track = makeApplyTrack(format: .mp3, coverURL: coverURL)
    let m4aTrack = makeApplyTrack(format: .m4a, coverURL: nil)

    expectNoDifference(
      try AudioTaggingCommands.plan(for: flacTrack, toolPaths: toolPaths).steps,
      [
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .metaflac,
            executableURL: URL(fileURLWithPath: "/tools/metaflac"),
            arguments: [
              "--remove-tag=TITLE", "--set-tag=TITLE=The Way It Is",
              "--remove-tag=ALBUM", "--set-tag=ALBUM=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
              "--remove-tag=ALBUMSORT", "--set-tag=ALBUMSORT=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
              "--remove-tag=ARTIST", "--set-tag=ARTIST=Bruce Hornsby and The Range",
              "--remove-tag=ALBUMARTIST", "--set-tag=ALBUMARTIST=Bruce Hornsby",
              "--remove-tag=TRACKNUMBER", "--set-tag=TRACKNUMBER=1",
              "--remove-tag=TRACKTOTAL", "--set-tag=TRACKTOTAL=2",
              "--remove-tag=DISCNUMBER", "--set-tag=DISCNUMBER=1",
              "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
            ]
          ),
          allowsFailure: false
        ),
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .metaflac,
            executableURL: URL(fileURLWithPath: "/tools/metaflac"),
            arguments: [
              "--remove",
              "--block-type=PICTURE",
              "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
            ]
          ),
          allowsFailure: true
        ),
        TaggingCommandStep(
          command: ScriptCommand(
            tool: .metaflac,
            executableURL: URL(fileURLWithPath: "/tools/metaflac"),
            arguments: [
              "--import-picture-from=/Shows/BruceHornsby/front.jpg",
              "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
            ]
          ),
          allowsFailure: false
        ),
      ]
    )

    let mp3Plan = try AudioTaggingCommands.plan(for: mp3Track, toolPaths: toolPaths)
    expectNoDifference(
      mp3Plan.replacement?.source.path(percentEncoded: false),
      "/Shows/BruceHornsby/Working/01 - The Way It Is.mp3.tagtmp.mp3"
    )
    expectNoDifference(
      mp3Plan.commands.first?.arguments,
      [
        "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-i", "/Shows/BruceHornsby/Working/01 - The Way It Is.mp3",
        "-i", "/Shows/BruceHornsby/front.jpg",
        "-map", "0:a:0", "-map", "1:v:0",
        "-c:a", "copy", "-c:v", "mjpeg",
        "-id3v2_version", "3",
        "-metadata", "title=The Way It Is",
        "-metadata", "album=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        "-metadata", "sort_album=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        "-metadata", "artist=Bruce Hornsby and The Range",
        "-metadata", "album_artist=Bruce Hornsby",
        "-metadata", "track=1/2",
        "-metadata", "disc=1",
        "-metadata:s:v", "title=Album cover",
        "-metadata:s:v", "comment=Cover (front)",
        "/Shows/BruceHornsby/Working/01 - The Way It Is.mp3.tagtmp.mp3",
      ]
    )

    let m4aSuffix = try AudioTaggingCommands
      .plan(for: m4aTrack, toolPaths: toolPaths)
      .commands.first?
      .arguments
      .suffix(5)
    expectNoDifference(
      m4aSuffix.map(Array.init),
      Optional(["-movflags", "+faststart", "-f", "ipod", "/Shows/BruceHornsby/Working/01 - The Way It Is.m4a.tagtmp.m4a"])
    )
  }

  @Test
  func constructsCompilationTaggingCommandsThatStripAndPreserve() throws {
    let toolPaths = AudioToolPaths(paths: [
      .metaflac: "/tools/metaflac",
      .ffmpeg: "/tools/ffmpeg",
    ])
    let tags = ProposedTags(
      album: "Great Covers",
      albumArtist: "Jon Phillips",
      grouping: "Existing | Great Covers",
      comments: "Transferred from the source tape\nAppend session",
      isCompilation: false,
      clearedFields: [.trackNumber, .trackTotal, .discNumber, .isCompilation]
    )
    let flacTrack = ApplyTrackPlan(
      id: UUID(1),
      sourceFile: makeAudioFile(id: UUID(1), name: "cover.flac", format: .flac, sortKey: "cover.flac"),
      workingFile: URL(fileURLWithPath: "/Incoming/Working/cover.flac"),
      tags: tags,
      trackTotal: 0,
      coverURL: URL(fileURLWithPath: "/Incoming/front.jpg")
    )
    let mp3Track = ApplyTrackPlan(
      id: UUID(2),
      sourceFile: makeAudioFile(id: UUID(2), name: "cover.mp3", format: .mp3, sortKey: "cover.mp3"),
      workingFile: URL(fileURLWithPath: "/Incoming/Working/cover.mp3"),
      tags: tags,
      trackTotal: 0,
      coverURL: nil
    )

    expectNoDifference(
      try AudioTaggingCommands.plan(for: flacTrack, toolPaths: toolPaths).steps[0].command.arguments,
      [
        "--remove-tag=ALBUM", "--set-tag=ALBUM=Great Covers",
        "--remove-tag=ALBUMARTIST", "--set-tag=ALBUMARTIST=Jon Phillips",
        "--remove-tag=GROUPING", "--set-tag=GROUPING=Existing | Great Covers",
        "--remove-tag=COMMENT", "--set-tag=COMMENT=Transferred from the source tape\nAppend session",
        "--remove-tag=COMPILATION",
        "--remove-tag=TRACKNUMBER",
        "--remove-tag=TRACKTOTAL",
        "--remove-tag=DISCNUMBER",
        "/Incoming/Working/cover.flac",
      ]
    )

    expectNoDifference(
      try AudioTaggingCommands.plan(for: mp3Track, toolPaths: toolPaths).commands[0].arguments,
      [
        "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-i", "/Incoming/Working/cover.mp3",
        "-map", "0:a:0", "-map", "0:v:0?",
        "-c:a", "copy", "-c:v", "mjpeg",
        "-id3v2_version", "3",
        "-metadata", "album=Great Covers",
        "-metadata", "album_artist=Jon Phillips",
        "-metadata", "grouping=Existing | Great Covers",
        "-metadata", "comment=Transferred from the source tape\nAppend session",
        "-metadata", "compilation=",
        "-metadata", "track=",
        "-metadata", "disc=",
        "-metadata:s:v", "title=Album cover",
        "-metadata:s:v", "comment=Cover (front)",
        "/Incoming/Working/cover.mp3.tagtmp.mp3",
      ]
    )
  }

  @Test
  func m4aClearingDropsCompilationAndTrackAtomsWithRealTools() throws {
    guard let ffmpeg = firstExecutable(named: "ffmpeg"),
      let ffprobe = firstExecutable(named: "ffprobe")
    else {
      return
    }

    let directory = try temporaryDirectory()
    let workingFile = directory.appendingPathComponent("tagged.m4a")
    _ = try runProcess(
      executableURL: ffmpeg,
      arguments: [
        "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi",
        "-i", "anullsrc=r=44100:cl=stereo",
        "-t", "0.1",
        "-c:a", "aac",
        "-metadata", "album=Original",
        "-metadata", "album_artist=Original Artist",
        "-metadata", "compilation=1",
        "-metadata", "track=3/9",
        "-f", "ipod",
        workingFile.path(percentEncoded: false),
      ]
    )

    let track = ApplyTrackPlan(
      id: UUID(1),
      sourceFile: makeAudioFile(id: UUID(1), name: "tagged.m4a", format: .m4a, sortKey: "tagged.m4a"),
      workingFile: workingFile,
      tags: ProposedTags(
        album: "Great Covers",
        albumArtist: "Jon Phillips",
        isCompilation: false,
        clearedFields: [.isCompilation, .trackNumber, .trackTotal, .discNumber]
      ),
      trackTotal: 0,
      coverURL: nil
    )
    let commandPlan = try AudioTaggingCommands.plan(
      for: track,
      toolPaths: AudioToolPaths(paths: [.ffmpeg: ffmpeg.path(percentEncoded: false)])
    )
    for command in commandPlan.commands {
      _ = try runProcess(executableURL: command.executableURL, arguments: command.arguments)
    }
    if let replacement = commandPlan.replacement {
      _ = try FileManager.default.replaceItemAt(
        replacement.destination,
        withItemAt: replacement.source
      )
    }

    let output = try runProcess(
      executableURL: ffprobe,
      arguments: [
        "-v", "error",
        "-show_entries", "format_tags=album,album_artist,compilation,track",
        "-of", "json",
        workingFile.path(percentEncoded: false),
      ]
    )
    let json = String(data: output.standardOutput, encoding: .utf8) ?? ""
    #expect(json.contains(#""album": "Great Covers""#))
    #expect(json.contains(#""album_artist": "Jon Phillips""#))
    #expect(!json.contains(#""compilation""#))
    #expect(!json.contains(#""track""#))
  }
}
