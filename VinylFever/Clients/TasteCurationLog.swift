import Foundation
import VinylFeverCore

enum TasteCurationLog {
  static func append(_ change: CurationChange, host: String, folder: URL) throws {
    let safeHost = host.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
    }.joined()
    let url = folder.appending(path: (safeHost.isEmpty ? "Mac" : safeHost) + ".jsonl")
    try JSONLAppend.append(try CurationLogCodec.encode(change), to: url)
  }
}

