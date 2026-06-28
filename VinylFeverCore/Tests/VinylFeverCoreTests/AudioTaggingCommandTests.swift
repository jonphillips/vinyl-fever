import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct AudioTaggingCommandTests {
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
}
