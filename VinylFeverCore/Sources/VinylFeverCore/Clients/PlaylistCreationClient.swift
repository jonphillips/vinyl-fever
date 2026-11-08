import Dependencies
import DependenciesMacros
import Foundation
import VinylFeverNotes

@DependencyClient
public struct PlaylistCreationClient: Sendable {
  public var read: @Sendable () throws -> PlaylistCreationsReadResult
  public var append: @Sendable (_ event: PlaylistCreationEvent) throws -> Void
}

extension PlaylistCreationClient: TestDependencyKey {
  public static var testValue: Self { Self(read: { .init(events: [], skippedLines: 0, filesRead: 0) }, append: { _ in }) }
}

extension PlaylistCreationClient: DependencyKey {
  public static var liveValue: Self {
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/playlist-creations", directoryHint: .isDirectory)
    return live(root: root)
  }
}

extension PlaylistCreationClient {
  public static func live(root: URL) -> Self {
    Self(
      read: {
        guard FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) else {
          return PlaylistCreationsReadResult(events: [], skippedLines: 0, filesRead: 0)
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
          .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
          .map { url -> Data in
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return try coordinatedRead(url)
          }
        return PlaylistCreationsCodec.readFiles(files)
      },
      append: { event in
        let writer = event.device ?? event.writerHost ?? "Mac"
        let safe = writer.unicodeScalars.map {
          CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
        }.joined()
        try JSONLAppend.append(PlaylistCreationsCodec.encode(event),
          to: root.appending(path: "\(safe.isEmpty ? "Mac" : safe).jsonl"))
      }
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

extension DependencyValues {
  public var playlistCreationClient: PlaylistCreationClient {
    get { self[PlaylistCreationClient.self] }
    set { self[PlaylistCreationClient.self] = newValue }
  }
}
