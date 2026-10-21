import Foundation
import VinylFeverCore

extension LibrarySnapshotStore {
  static var liveValue: Self {
    let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ]
    .appending(path: "VinylFever/LibrarySnapshot/library-snapshot.json")
    return Self(
      read: {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
          return nil
        }
        return try LibrarySnapshotCodec.decode(Data(contentsOf: fileURL))
      },
      write: { snapshot in
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LibrarySnapshotCodec.encode(snapshot).write(to: fileURL, options: .atomic)
      },
      readAliases: {
        let aliasesURL = fileURL.deletingLastPathComponent().appending(path: "artist-aliases.json")
        guard FileManager.default.fileExists(atPath: aliasesURL.path(percentEncoded: false)) else { return [:] }
        return try ArtistAliasesCodec.decode(Data(contentsOf: aliasesURL))
      },
      writeAliases: { aliases in
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let aliasesURL = fileURL.deletingLastPathComponent().appending(path: "artist-aliases.json")
        try ArtistAliasesCodec.encode(aliases).write(to: aliasesURL, options: .atomic)
      },
      modifiedAt: {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
          return nil
        }
        return try FileManager.default.attributesOfItem(
          atPath: fileURL.path(percentEncoded: false))[.modificationDate] as? Date
      }
    )
  }
}
