import Foundation
import VinylFeverNotes

struct RecommendationLedgerFolderRead: Equatable {
  var ledger: RecommendationLedgerReadResult
  var filesRead: Int
  var unreadableFileCount: Int
  var totalFileCount: Int = 0
}

enum RecommendationLedgerFolderReader {
  static func read(
    folder: URL,
    deadline: Date = Date().addingTimeInterval(8),
    startDownload: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) },
    coordinatedRead: @escaping @Sendable (URL) throws -> Data = TasteFolderReader.coordinatedRead
  ) -> RecommendationLedgerFolderRead {
    let read = TasteFolderReader.read(
      folder: folder,
      subdirectory: "recommendations",
      includes: { $0.hasSuffix(".jsonl") },
      missingDirectoryIsUnavailable: true,
      emptyDirectoryIsUnavailable: true,
      deadline: deadline,
      startDownload: startDownload,
      coordinatedRead: coordinatedRead
    )
    return RecommendationLedgerFolderRead(
      ledger: RecommendationLedgerCodec.readFiles(read.files),
      filesRead: read.filesRead,
      unreadableFileCount: read.unreadableFileCount,
      totalFileCount: read.totalFileCount
    )
  }
}
