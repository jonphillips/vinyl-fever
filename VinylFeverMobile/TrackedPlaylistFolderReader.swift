import Foundation
import VinylFeverNotes

struct TrackedPlaylistFolderRead {
  var snapshots: [TrackedPlaylistSnapshot]
  var unreadableFileCount: Int
  var totalFileCount: Int
}

enum TrackedPlaylistFolderReader {
  static func read(folder: URL) -> TrackedPlaylistFolderRead {
    let files = TasteFolderReader.read(folder: folder, subdirectory: "tracked",
      includes: { $0.hasSuffix(".jsonl") }, missingDirectoryIsUnavailable: false,
      emptyDirectoryIsUnavailable: false)
    let records = TrackedPlaylistExposureCodec.readFiles(files.files)
    return TrackedPlaylistFolderRead(
      snapshots: records.compactMap { if case let .snapshot(value) = $0 { value } else { nil } },
      unreadableFileCount: files.unreadableFileCount, totalFileCount: files.totalFileCount)
  }
}
