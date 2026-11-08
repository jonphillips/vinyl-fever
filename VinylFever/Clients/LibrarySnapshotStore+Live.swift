import Foundation
import VinylFeverCore

extension LibrarySnapshotStore {
  static var liveValue: Self {
    let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ]
    .appending(path: "VinylFever/LibrarySnapshot/library-snapshot.json")
    let mirrorURL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/artist-aliases.json")
    return live(fileURL: fileURL, mirrorURL: mirrorURL)
  }

  static func live(fileURL: URL, mirrorURL: URL) -> Self {
    let aliasesURL = fileURL.deletingLastPathComponent().appending(path: "artist-aliases.json")
    let mirrorAliases: @Sendable (_ data: Data, _ repairIfOlder: Bool) throws -> Void = { data, repairIfOlder in
      if repairIfOlder,
        let localDate = try? FileManager.default.attributesOfItem(atPath: aliasesURL.path)[.modificationDate] as? Date,
        let mirrorDate = try? FileManager.default.attributesOfItem(atPath: mirrorURL.path)[.modificationDate] as? Date,
        mirrorDate >= localDate { return }
      try FileManager.default.createDirectory(at: mirrorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: mirrorURL, options: .atomic)
    }
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
        guard FileManager.default.fileExists(atPath: aliasesURL.path(percentEncoded: false)) else { return [:] }
        return try ArtistAliasesCodec.decode(Data(contentsOf: aliasesURL))
      },
      writeAliases: { aliases in
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try ArtistAliasesCodec.encode(aliases)
        try data.write(to: aliasesURL, options: .atomic)
        try mirrorAliases(data, false)
      },
      repairAliasesMirror: {
        guard FileManager.default.fileExists(atPath: aliasesURL.path(percentEncoded: false)) else { return }
        try mirrorAliases(Data(contentsOf: aliasesURL), true)
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
