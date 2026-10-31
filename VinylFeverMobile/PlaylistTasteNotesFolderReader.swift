import Foundation
import VinylFeverNotes

struct PlaylistTasteNotesFolderRead: Equatable {
  var result: TasteNotesReadResult
  var unreadableFileCount: Int
  var totalFileCount: Int
}

enum PlaylistTasteNotesFolderReader {
  static func read(
    folder: URL,
    deadline: Date = Date().addingTimeInterval(8),
    startDownload: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) },
    coordinatedRead: @escaping @Sendable (URL) throws -> Data = TasteFolderReader.coordinatedRead
  ) -> PlaylistTasteNotesFolderRead {
    let read = TasteFolderReader.read(
      folder: folder,
      includes: { $0.hasPrefix("notes") && $0.hasSuffix(".jsonl") },
      missingDirectoryIsUnavailable: false,
      emptyDirectoryIsUnavailable: false,
      deadline: deadline,
      startDownload: startDownload,
      coordinatedRead: coordinatedRead
    )
    return PlaylistTasteNotesFolderRead(
      result: TasteNotesCodec.readFiles(read.files), unreadableFileCount: read.unreadableFileCount,
      totalFileCount: read.totalFileCount
    )
  }
}
