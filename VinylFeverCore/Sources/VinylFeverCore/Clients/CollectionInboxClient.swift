import Dependencies
import DependenciesMacros
import Foundation

/// App-owned staging area for loose audio files dropped onto a compilation album.
///
/// The filesystem is the source of truth for what is staged — there is no schema. Each
/// album owns a subfolder under the Inbox root (`<AppSupport>/VinylFever/Inbox/<albumID>/`);
/// dropped files are **copied** in (originals untouched) and drained to **Trash** only after
/// their append certifies. Drain is guarded to the Inbox root so a user-picked source folder
/// can never be trashed.
@DependencyClient
public struct CollectionInboxClient: Sendable {
  /// Resolve (creating on demand) the staging subfolder for `albumID`.
  public var stagingDirectory: @Sendable (_ albumID: CompilationAlbum.ID) throws -> URL
  /// Copy `files` into `albumID`'s staging subfolder, preserving the originals. On a name
  /// collision the copy is suffixed (` (2)`, ` (3)`, …) rather than overwriting. Returns the
  /// staged destination URLs.
  public var stage: @Sendable (_ files: [URL], _ albumID: CompilationAlbum.ID) throws -> [URL]
  /// List the files currently staged for `albumID`, natural-sorted by name.
  public var contents: @Sendable (_ albumID: CompilationAlbum.ID) throws -> [URL]
  /// Per-album staged counts across the whole Inbox root.
  public var summary: @Sendable () throws -> [InboxAlbumSummary]
  /// Move specific staged `files` for `albumID` to Trash, leaving the rest of the queue (and its
  /// subfolder) intact. Refuses any path that is not a direct child of `albumID`'s staging
  /// subfolder, so a user-picked source file can never be trashed. Missing files are skipped.
  public var remove: @Sendable (_ files: [URL], _ albumID: CompilationAlbum.ID) throws -> Void
  /// Move `albumID`'s staged files to Trash and leave its subfolder absent. Refuses to act on
  /// any path outside the Inbox root.
  public var drain: @Sendable (_ albumID: CompilationAlbum.ID) throws -> Void
}

public struct InboxAlbumSummary: Equatable, Identifiable, Sendable {
  public var albumID: CompilationAlbum.ID
  public var fileCount: Int

  public init(albumID: CompilationAlbum.ID, fileCount: Int) {
    self.albumID = albumID
    self.fileCount = fileCount
  }

  public var id: CompilationAlbum.ID { albumID }
}

public enum CollectionInboxError: LocalizedError, Equatable, Sendable {
  /// A drain target resolved outside the Inbox root — refused as a safety assertion.
  case pathOutsideInboxRoot(URL)

  public var errorDescription: String? {
    switch self {
    case let .pathOutsideInboxRoot(url):
      "\(url.path(percentEncoded: false)) is not inside the Inbox root; refusing to trash it."
    }
  }
}

/// All Inbox filesystem logic, parameterized on the root so tests run against a temp directory.
struct CollectionInboxStore: Sendable {
  let root: URL

  func stagingDirectory(albumID: CompilationAlbum.ID) throws -> URL {
    let directory = albumDirectory(albumID)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  func stage(files: [URL], albumID: CompilationAlbum.ID) throws -> [URL] {
    let directory = try stagingDirectory(albumID: albumID)
    var staged: [URL] = []
    for source in files {
      let destination = collisionFreeDestination(for: source.lastPathComponent, in: directory)
      try FileManager.default.copyItem(at: source, to: destination)
      staged.append(destination.standardizedFileURL)
    }
    return staged
  }

  func contents(albumID: CompilationAlbum.ID) throws -> [URL] {
    let directory = albumDirectory(albumID)
    guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
      return []
    }
    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    .map(\.standardizedFileURL)
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  func summary() throws -> [InboxAlbumSummary] {
    guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
      return []
    }
    let albumDirectories = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

    return try albumDirectories
      .compactMap { directory -> InboxAlbumSummary? in
        guard let albumID = CompilationAlbum.ID(uuidString: directory.lastPathComponent) else {
          return nil
        }
        return InboxAlbumSummary(albumID: albumID, fileCount: try contents(albumID: albumID).count)
      }
      .sorted { $0.albumID.uuidString < $1.albumID.uuidString }
  }

  func remove(files: [URL], albumID: CompilationAlbum.ID) throws {
    let directory = albumDirectory(albumID).standardizedFileURL
    for file in files {
      let standardized = file.standardizedFileURL
      // A removable file must be a direct child of *this album's* staging folder. The root
      // guard alone isn't enough — it would also admit a sibling album's staged file.
      try assertUnderRoot(standardized)
      guard standardized.deletingLastPathComponent().standardizedFileURL == directory else {
        throw CollectionInboxError.pathOutsideInboxRoot(standardized)
      }
      guard FileManager.default.fileExists(atPath: standardized.path(percentEncoded: false)) else {
        continue
      }
      try FileManager.default.trashItem(at: standardized, resultingItemURL: nil)
    }
  }

  func drain(albumID: CompilationAlbum.ID) throws {
    let directory = albumDirectory(albumID)
    try assertUnderRoot(directory)
    guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
      return
    }
    try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
  }

  func albumDirectory(_ albumID: CompilationAlbum.ID) -> URL {
    root.appendingPathComponent(albumID.uuidString, isDirectory: true)
  }

  /// Build a destination that does not clobber an existing staged file: `song.flac` →
  /// `song (2).flac`, `song (2).flac` → `song (3).flac`, deterministically.
  private func collisionFreeDestination(for fileName: String, in directory: URL) -> URL {
    let candidate = directory.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
      return candidate
    }
    let nameURL = URL(fileURLWithPath: fileName)
    let base = nameURL.deletingPathExtension().lastPathComponent
    let ext = nameURL.pathExtension
    var counter = 2
    while true {
      let suffixed = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
      let next = directory.appendingPathComponent(suffixed)
      if !FileManager.default.fileExists(atPath: next.path(percentEncoded: false)) {
        return next
      }
      counter += 1
    }
  }

  /// Safety assertion: a drain target must live strictly inside the Inbox root.
  func assertUnderRoot(_ url: URL) throws {
    let rootPath = root.standardizedFileURL.path(percentEncoded: false)
    let normalizedRoot = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    let targetPath = url.standardizedFileURL.path(percentEncoded: false)
    guard targetPath.hasPrefix(normalizedRoot), targetPath != rootPath else {
      throw CollectionInboxError.pathOutsideInboxRoot(url)
    }
  }
}

extension CollectionInboxClient {
  /// Build a live client rooted at `root`. `liveValue` points this at Application Support;
  /// tests point it at a temp directory.
  public static func live(root: URL) -> Self {
    let store = CollectionInboxStore(root: root)
    return Self(
      stagingDirectory: { try store.stagingDirectory(albumID: $0) },
      stage: { try store.stage(files: $0, albumID: $1) },
      contents: { try store.contents(albumID: $0) },
      summary: { try store.summary() },
      remove: { try store.remove(files: $0, albumID: $1) },
      drain: { try store.drain(albumID: $0) }
    )
  }

  /// `<AppSupport>/VinylFever/Inbox/`, created on demand.
  static func applicationSupportRoot() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return appSupport
      .appendingPathComponent("VinylFever", isDirectory: true)
      .appendingPathComponent("Inbox", isDirectory: true)
  }
}

extension CollectionInboxClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension CollectionInboxClient: DependencyKey {
  public static var liveValue: Self {
    do {
      return .live(root: try applicationSupportRoot())
    } catch {
      // Application Support is unavailable — fall back to the unimplemented client so the
      // failure surfaces at the call site rather than at app launch.
      return Self()
    }
  }
}

extension DependencyValues {
  public var collectionInboxClient: CollectionInboxClient {
    get { self[CollectionInboxClient.self] }
    set { self[CollectionInboxClient.self] = newValue }
  }
}
