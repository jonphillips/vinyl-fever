import Foundation
import VinylFeverCore

enum TasteCurationLog {
  static func append(_ change: CurationChange, host: String) throws {
    let folder = URL(fileURLWithPath: NSHomeDirectory())
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/curation", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let safeHost = host.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
    }.joined()
    let url = folder.appending(path: (safeHost.isEmpty ? "Mac" : safeHost) + ".jsonl")
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
      do {
        if !FileManager.default.fileExists(atPath: target.path) {
          _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: CurationLogCodec.encode(change))
        try handle.synchronize()
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }
}

