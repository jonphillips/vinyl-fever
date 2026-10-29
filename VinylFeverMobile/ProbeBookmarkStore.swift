import Foundation

enum ProbeBookmarkStore {
  private static let defaultsKey = "probe-folder-bookmark"

  static func save(_ folder: URL, defaults: UserDefaults = .standard) throws {
    let bookmark = try folder.bookmarkData(
      options: [],
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
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    if stale { try save(folder, defaults: defaults) }
    return folder
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
