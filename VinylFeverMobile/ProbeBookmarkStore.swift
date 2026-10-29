import Foundation

enum ProbeBookmarkStore {
  private static let defaultsKey = "probe-folder-bookmark"

  static func save(_ folder: URL, defaults: UserDefaults = .standard) throws {
    let bookmark = try folder.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    defaults.set(bookmark, forKey: defaultsKey)
  }

  static func resolve(defaults: UserDefaults = .standard) throws -> URL {
    guard let bookmark = defaults.data(forKey: defaultsKey) else {
      throw ProbeBookmarkError.folderNotSelected
    }
    var stale = false
    let folder = try URL(
      resolvingBookmarkData: bookmark,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    guard !stale else { throw ProbeBookmarkError.bookmarkIsStale }
    return folder
  }
}

enum ProbeBookmarkError: LocalizedError {
  case folderNotSelected
  case bookmarkIsStale

  var errorDescription: String? {
    switch self {
    case .folderNotSelected: "Choose the Vinyl Fever folder first."
    case .bookmarkIsStale: "Folder access expired. Choose the folder again."
    }
  }
}
