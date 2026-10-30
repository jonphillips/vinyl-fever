import Foundation
import VinylFeverNotes

struct RecommendationLedgerFolderRead: Equatable {
  var ledger: RecommendationLedgerReadResult
  var filesRead: Int
  var unreadableFileCount: Int
  var totalFileCount: Int = 0
}

enum RecommendationLedgerFolderReader {
  private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data] = []
    func append(_ data: Data) { lock.lock(); values.append(data); lock.unlock() }
    func snapshot() -> [Data] { lock.lock(); defer { lock.unlock() }; return values }
  }

  static func read(
    folder: URL,
    deadline: Date = Date().addingTimeInterval(8),
    startDownload: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) },
    coordinatedRead: @escaping @Sendable (URL) throws -> Data = coordinatedRead
  ) -> RecommendationLedgerFolderRead {
    let directory = folder.appendingPathComponent("Taste Intelligence/recommendations", isDirectory: true)
    let candidates: [URL]
    do {
      candidates = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
      )
    } catch {
      return RecommendationLedgerFolderRead(
        ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0),
        filesRead: 0,
        unreadableFileCount: 1,
        totalFileCount: 0
      )
    }
    let urls = candidates.compactMap { candidate -> URL? in
      let name = candidate.lastPathComponent
      if name.hasSuffix(".jsonl") { return candidate }
      guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
      let actualName = String(name.dropFirst().dropLast(".icloud".count))
      guard actualName.hasSuffix(".jsonl") else { return nil }
      return directory.appendingPathComponent(actualName)
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !urls.isEmpty else {
      return RecommendationLedgerFolderRead(
        ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0),
        filesRead: 0,
        unreadableFileCount: 1,
        totalFileCount: 0
      )
    }

    let group = DispatchGroup()
    let results = Results()
    for url in urls {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        defer { group.leave() }
        let hasScopedAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasScopedAccess { folder.stopAccessingSecurityScopedResource() } }
        do {
          try? startDownload(url)
          results.append(try coordinatedRead(url))
        } catch {}
      }
    }
    let remaining = max(0, deadline.timeIntervalSinceNow)
    _ = group.wait(timeout: .now() + remaining)
    let files = results.snapshot()
    let unreadable = urls.count - files.count
    return RecommendationLedgerFolderRead(
      ledger: RecommendationLedgerCodec.readFiles(files),
      filesRead: files.count,
      unreadableFileCount: unreadable,
      totalFileCount: urls.count
    )
  }

  private static func coordinatedRead(_ url: URL) throws -> Data {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readError: Error?
    var data: Data?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      do { data = try Data(contentsOf: coordinatedURL) } catch { readError = error }
    }
    if let coordinationError { throw coordinationError }
    if let readError { throw readError }
    guard let data else { throw CocoaError(.fileReadUnknown) }
    return data
  }
}
