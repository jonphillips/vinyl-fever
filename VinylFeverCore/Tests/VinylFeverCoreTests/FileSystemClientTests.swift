import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(
  .serialized,
  .dependency(\.uuid, .incrementing)
)
struct FileSystemClientTests {
  @Test
  func scansAudioFilesInNaturalOrder() throws {
    let root = try FixtureFolder {
      File("02 - Second.flac")
      File("01 - First.flac")
      File("notes.md")
      Directory("Disc 2") {
        File("Track10.mp3")
      }
      Directory("Disc 1") {
        File("Track02.m4a")
        File("Track01.flac")
      }
    }

    let result = try FileSystemClient.liveValue.scanShowFolder(root: root.url)

    expectNoDifference(
      result.audioFiles.map { file in
        ScannedAudioFileSnapshot(
          relativePath: file.url.relativePath(from: root.url),
          format: file.format,
          sortKey: file.sortKey
        )
      },
      [
        ScannedAudioFileSnapshot(
          relativePath: "01 - First.flac",
          format: .flac,
          sortKey: "01 - First.flac"
        ),
        ScannedAudioFileSnapshot(
          relativePath: "02 - Second.flac",
          format: .flac,
          sortKey: "02 - Second.flac"
        ),
        ScannedAudioFileSnapshot(
          relativePath: "Disc 1/Track01.flac",
          format: .flac,
          sortKey: "Disc 1/Track01.flac"
        ),
        ScannedAudioFileSnapshot(
          relativePath: "Disc 1/Track02.m4a",
          format: .m4a,
          sortKey: "Disc 1/Track02.m4a"
        ),
        ScannedAudioFileSnapshot(
          relativePath: "Disc 2/Track10.mp3",
          format: .mp3,
          sortKey: "Disc 2/Track10.mp3"
        ),
      ]
    )
  }

  @Test
  func detectsSetlistAndCoverCandidatesAtRoot() throws {
    let root = try FixtureFolder {
      File("notes.txt")
      File("Setlist.txt")
      File("z-extra.txt")
      File("front.PNG")
      File("image.jpg")
      File("back.jpg")
      Directory("front.jpg") {
        File("not-cover.png")
      }
      Directory("Disc 1") {
        File("nested.txt")
        File("front.jpg")
      }
    }

    let result = try FileSystemClient.liveValue.scanShowFolder(root: root.url)

    expectNoDifference(
      result.setlistCandidates.map { $0.relativePath(from: root.url) },
      [
        "Setlist.txt",
        "notes.txt",
        "z-extra.txt",
      ]
    )
    expectNoDifference(
      result.coverCandidates.map { $0.relativePath(from: root.url) },
      [
        "front.PNG",
        "image.jpg",
      ]
    )
  }
}

private struct ScannedAudioFileSnapshot: Equatable {
  var relativePath: String
  var format: AudioFormat
  var sortKey: String
}

@resultBuilder
private enum FixtureFolderBuilder {
  static func buildBlock(_ components: FixtureEntry...) -> [FixtureEntry] {
    components
  }
}

private enum FixtureEntry {
  case file(String)
  case directory(String, [FixtureEntry])
}

private func File(_ name: String) -> FixtureEntry {
  .file(name)
}

private func Directory(
  _ name: String,
  @FixtureFolderBuilder contents: () -> [FixtureEntry]
) -> FixtureEntry {
  .directory(name, contents())
}

private struct FixtureFolder {
  var url: URL

  init(@FixtureFolderBuilder contents: () -> [FixtureEntry]) throws {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try write(contents(), to: url)
  }

  private func write(_ entries: [FixtureEntry], to url: URL) throws {
    for entry in entries {
      switch entry {
      case let .file(name):
        try Data().write(to: url.appendingPathComponent(name))
      case let .directory(name, contents):
        let directory = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(contents, to: directory)
      }
    }
  }
}

private extension URL {
  func relativePath(from root: URL) -> String {
    let rootPath = root.standardizedFileURL.path(percentEncoded: false)
    let filePath = standardizedFileURL.path(percentEncoded: false)
    guard filePath.hasPrefix(rootPath) else {
      return lastPathComponent
    }
    let relativePath = filePath.dropFirst(rootPath.count)
    return String(relativePath.hasPrefix("/") ? relativePath.dropFirst() : relativePath)
  }
}
