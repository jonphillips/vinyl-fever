import Foundation
import VinylFeverNotes

struct PlaylistTasteNotesFolderRead: Equatable {
  var result: TasteNotesReadResult
  var unreadableFileCount: Int
  var totalFileCount: Int
}

enum PlaylistTasteNotesFolderReader {
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
  ) -> PlaylistTasteNotesFolderRead {
    let directory = folder.appendingPathComponent("Taste Intelligence", isDirectory: true)
    let candidates: [URL]
    do {
      candidates = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]
      )
    } catch {
      if (error as NSError).code == CocoaError.fileNoSuchFile.rawValue {
        return PlaylistTasteNotesFolderRead(result: TasteNotesCodec.readFiles([]), unreadableFileCount: 0, totalFileCount: 0)
      }
      return PlaylistTasteNotesFolderRead(result: TasteNotesCodec.readFiles([]), unreadableFileCount: 1, totalFileCount: 0)
    }
    let urls = candidates.compactMap { candidate -> URL? in
      let name = candidate.lastPathComponent
      if name.hasPrefix("notes"), name.hasSuffix(".jsonl") { return candidate }
      guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
      let actualName = String(name.dropFirst().dropLast(".icloud".count))
      guard actualName.hasPrefix("notes"), actualName.hasSuffix(".jsonl") else { return nil }
      return directory.appendingPathComponent(actualName)
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !urls.isEmpty else {
      return PlaylistTasteNotesFolderRead(result: TasteNotesCodec.readFiles([]), unreadableFileCount: 0, totalFileCount: 0)
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
    _ = group.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow))
    let files = results.snapshot()
    return PlaylistTasteNotesFolderRead(
      result: TasteNotesCodec.readFiles(files), unreadableFileCount: urls.count - files.count, totalFileCount: urls.count
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
