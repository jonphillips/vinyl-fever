import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct FileSystemClient: Sendable {
  public var scanShowFolder: @Sendable (_ root: URL) throws -> ScannedShowFolder
}

private struct LiveShowFolderScanner {
  @Dependency(\.uuid) private var uuid

  func scanShowFolder(at root: URL) throws -> ScannedShowFolder {
    let root = root.standardizedFileURL
    let contents = try directoryContents(at: root)
      .filter(isRegularFile)
    let allFiles = try recursiveFiles(at: root)

    let audioFiles = allFiles
      .compactMap { url -> ScannedAudioFile? in
        guard let format = AudioFormat(pathExtension: url.pathExtension) else {
          return nil
        }
        let sortKey = relativePath(for: url, root: root)
        return ScannedAudioFile(
          id: uuid(),
          url: url,
          format: format,
          sortKey: sortKey
        )
      }
      .sorted { lhs, rhs in
        lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
      }

    return ScannedShowFolder(
      root: root,
      audioFiles: audioFiles,
      setlistCandidates: setlistCandidates(in: contents),
      coverCandidates: coverCandidates(in: contents)
    )
  }

  private func directoryContents(at url: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
  }

  private func recursiveFiles(at root: URL) throws -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var urls: [URL] = []
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
      if values.isDirectory == true {
        continue
      }
      if values.isRegularFile == true {
        urls.append(url.standardizedFileURL)
      }
    }
    return urls
  }

  private func isRegularFile(_ url: URL) throws -> Bool {
    try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
  }

  private func setlistCandidates(in contents: [URL]) -> [URL] {
    contents
      .filter { $0.pathExtension.localizedCaseInsensitiveCompare("txt") == .orderedSame }
      .sorted { lhs, rhs in
        setlistSortKey(for: lhs).localizedStandardCompare(setlistSortKey(for: rhs))
          == .orderedAscending
      }
      .map(\.standardizedFileURL)
  }

  private func setlistSortKey(for url: URL) -> String {
    if url.lastPathComponent.localizedCaseInsensitiveCompare("setlist.txt") == .orderedSame {
      return "0"
    }
    return "1-\(url.lastPathComponent)"
  }

  private func coverCandidates(in contents: [URL]) -> [URL] {
    contents
      .filter { url in
        let baseName = url.deletingPathExtension().lastPathComponent
        return baseName.localizedCaseInsensitiveCompare("front") == .orderedSame
          || baseName.localizedCaseInsensitiveCompare("image") == .orderedSame
      }
      .sorted { lhs, rhs in
        coverSortKey(for: lhs).localizedStandardCompare(coverSortKey(for: rhs))
          == .orderedAscending
      }
      .map(\.standardizedFileURL)
  }

  private func coverSortKey(for url: URL) -> String {
    let baseName = url.deletingPathExtension().lastPathComponent
    if baseName.localizedCaseInsensitiveCompare("front") == .orderedSame {
      return "0-\(url.lastPathComponent)"
    }
    return "1-\(url.lastPathComponent)"
  }

  private func relativePath(for url: URL, root: URL) -> String {
    let rootPath = root.path(percentEncoded: false)
    let filePath = url.path(percentEncoded: false)
    guard filePath.hasPrefix(rootPath) else {
      return url.lastPathComponent
    }
    let relativePath = filePath.dropFirst(rootPath.count)
    return String(relativePath.hasPrefix("/") ? relativePath.dropFirst() : relativePath)
  }
}

extension FileSystemClient: DependencyKey {
  public static let testValue = Self()
  public static let liveValue = Self { root in
    try LiveShowFolderScanner().scanShowFolder(at: root)
  }
}

extension DependencyValues {
  public var fileSystemClient: FileSystemClient {
    get { self[FileSystemClient.self] }
    set { self[FileSystemClient.self] = newValue }
  }
}
