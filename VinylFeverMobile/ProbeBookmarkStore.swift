import Foundation

enum ProbeBookmarkStore {
  private static let defaultsKey = "probe-folder-bookmark"

  /// A bookmark made while the folder isn't being accessed carries no access, so saving opens it first.
  static func save(_ folder: URL, defaults: UserDefaults = .standard) throws {
    let accessing = folder.startAccessingSecurityScopedResource()
    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
    let bookmark = try folder.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    defaults.set(bookmark, forKey: defaultsKey)
  }

  static func resolve(defaults: UserDefaults = .standard) throws -> (folder: URL, isStale: Bool) {
    guard let bookmark = defaults.data(forKey: defaultsKey) else {
      throw ProbeBookmarkError.folderNotSelected
    }
    var stale = false
    let folder = try URL(
      resolvingBookmarkData: bookmark,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    return (folder, stale)
  }

  /// Runs `body` while the saved folder is accessible. A stale bookmark is refreshed inside that
  /// access; refreshed outside it, the new bookmark has no access and the next run is refused.
  static func withFolder<T>(defaults: UserDefaults = .standard, _ body: (URL) throws -> T) throws -> T {
    let (folder, isStale) = try resolve(defaults: defaults)
    guard folder.startAccessingSecurityScopedResource() else {
      throw ProbeBookmarkError.accessRefused
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    if isStale { try save(folder, defaults: defaults) }
    return try body(folder)
  }
}

enum ProbeBookmarkError: LocalizedError {
  case folderNotSelected
  case accessRefused

  var errorDescription: String? {
    switch self {
    case .folderNotSelected: "Choose the Vinyl Fever folder first."
    case .accessRefused: "Folder access was refused. Choose the folder again."
    }
  }
}
