import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct AudioConversionCommandTests {
  @Test
  func constructsPinnedALACCommandWithFolderCover() throws {
    let track = ConversionTrackPlan(
      applyTrack: makeApplyTrack(
        format: .flac,
        coverURL: applyShowRoot.appendingPathComponent("front.jpg")
      ),
      outputDirectory: applyShowRoot.appendingPathComponent("Output", isDirectory: true)
    )

    let command = try AudioConversionCommands.alacCommand(
      for: track,
      toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
    )

    expectNoDifference(command.tool, .ffmpeg)
    expectNoDifference(command.executableURL, URL(fileURLWithPath: "/tools/ffmpeg"))
    expectNoDifference(
      command.arguments,
      [
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
        "-i",
        "/Shows/BruceHornsby/front.jpg",
        "-map",
        "0:a:0",
        "-map",
        "1:v:0",
        "-map_metadata",
        "0",
        "-c:a",
        "alac",
        "-c:v",
        "mjpeg",
        "-disposition:v:0",
        "attached_pic",
        "-metadata",
        "title=The Way It Is",
        "-metadata",
        "album=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        "-metadata",
        "sort_album=1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
        "-metadata",
        "artist=Bruce Hornsby and The Range",
        "-metadata",
        "album_artist=Bruce Hornsby",
        "-metadata",
        "track=1/2",
        "-metadata",
        "disc=1",
        "-metadata:s:v",
        "title=Album cover",
        "-metadata:s:v",
        "comment=Cover (front)",
        "-movflags",
        "+faststart",
        "/Shows/BruceHornsby/Output/01 - The Way It Is.m4a",
      ]
    )
  }

  @Test
  func constructsALACCommandWithOptionalEmbeddedCover() throws {
    let track = ConversionTrackPlan(
      applyTrack: makeApplyTrack(format: .flac, coverURL: nil),
      outputDirectory: applyShowRoot.appendingPathComponent("Output", isDirectory: true)
    )

    let arguments = try AudioConversionCommands.alacCommand(
      for: track,
      toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
    )
    .arguments

    expectNoDifference(
      Array(arguments.prefix(10)),
      [
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
        "-map",
        "0:a:0",
        "-map",
        "0:v:0?",
      ]
    )
  }

  @Test
  func carriesGroupingAndCommentsIntoALACMetadata() throws {
    let applyTrack = makeApplyTrack(format: .flac, coverURL: nil)
    var taggedTrack = applyTrack
    taggedTrack.tags.grouping = "Collection | Session"
    taggedTrack.tags.comments = "Original comment\nAppend note"
    let track = ConversionTrackPlan(
      applyTrack: taggedTrack,
      outputDirectory: applyShowRoot.appendingPathComponent("Output", isDirectory: true)
    )

    let arguments = try AudioConversionCommands.alacCommand(
      for: track,
      toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
    ).arguments

    #expect(arguments.contains { $0 == "grouping=Collection | Session" })
    #expect(arguments.contains { $0 == "comment=Original comment\nAppend note" })
  }
}
