import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

struct ToolPathResolverTests {
  @Test
  func resolvesFromHomebrewDirectoryBeforePath() {
    let resolver = ToolPathResolver(
      searchDirectories: ["/fixture/opt/homebrew/bin", "/fixture/usr/local/bin"],
      environmentPath: "/fixture/path/bin",
      isExecutableFile: { path in
        path == "/fixture/opt/homebrew/bin/ffmpeg"
          || path == "/fixture/path/bin/ffmpeg"
      }
    )

    let resolution = resolver.resolve(tool: .ffmpeg, overrides: ToolPathOverrides())

    expectNoDifference(
      resolution,
      ToolPathResolution(
        tool: .ffmpeg,
        resolvedPath: "/fixture/opt/homebrew/bin/ffmpeg",
        source: .discovered(directory: "/fixture/opt/homebrew/bin"),
        issue: nil
      )
    )
  }

  @Test
  func resolvesFromOverrideBeforeDiscoveredLocations() {
    let resolver = ToolPathResolver(
      searchDirectories: ["/fixture/opt/homebrew/bin"],
      environmentPath: nil,
      isExecutableFile: { path in
        path == "/custom/bin/metaflac"
          || path == "/fixture/opt/homebrew/bin/metaflac"
      }
    )

    let resolution = resolver.resolve(
      tool: .metaflac,
      overrides: ToolPathOverrides(metaflacPath: " /custom/bin/metaflac ")
    )

    expectNoDifference(
      resolution,
      ToolPathResolution(
        tool: .metaflac,
        resolvedPath: "/custom/bin/metaflac",
        source: .userOverride,
        issue: nil
      )
    )
  }

  @Test
  func reportsMissingOverride() {
    let resolver = ToolPathResolver(
      searchDirectories: ["/fixture/opt/homebrew/bin"],
      environmentPath: "/fixture/path/bin",
      isExecutableFile: { _ in false }
    )

    let resolution = resolver.resolve(
      tool: .ffprobe,
      overrides: ToolPathOverrides(ffprobePath: "/missing/ffprobe")
    )

    expectNoDifference(
      resolution,
      ToolPathResolution(
        tool: .ffprobe,
        resolvedPath: nil,
        source: .userOverride,
        issue: .overrideNotExecutable(path: "/missing/ffprobe")
      )
    )
  }

  @Test
  func reportsMissingTool() {
    let resolver = ToolPathResolver(
      searchDirectories: ["/fixture/opt/homebrew/bin"],
      environmentPath: "/fixture/path/bin",
      isExecutableFile: { _ in false }
    )

    let resolution = resolver.resolve(tool: .metaflac, overrides: ToolPathOverrides())

    expectNoDifference(
      resolution,
      ToolPathResolution(
        tool: .metaflac,
        resolvedPath: nil,
        source: .missing,
        issue: .notFound
      )
    )
  }

  @Test
  func parsesVersionOutput() {
    expectNoDifference(
      AudioTool.metaflac.parseVersion(from: "metaflac 1.5.0\n"),
      "metaflac 1.5.0"
    )
    expectNoDifference(
      AudioTool.ffmpeg.parseVersion(
        from: """
          ffmpeg version 8.1.1 Copyright (c) 2000-2026 the FFmpeg developers
          built with Apple clang version 21.0.0
          """
      ),
      "ffmpeg version 8.1.1"
    )
    expectNoDifference(
      AudioTool.ffprobe.parseVersion(
        from: """
          ffprobe version 8.1.1 Copyright (c) 2007-2026 the FFmpeg developers
          libavutil 60.26.101
          """
      ),
      "ffprobe version 8.1.1"
    )
  }

  @Test
  func versionArgumentsMatchLocalTools() {
    expectNoDifference(AudioTool.metaflac.versionArguments, ["--version"])
    expectNoDifference(AudioTool.ffmpeg.versionArguments, ["-version"])
    expectNoDifference(AudioTool.ffprobe.versionArguments, ["-version"])
  }
}
