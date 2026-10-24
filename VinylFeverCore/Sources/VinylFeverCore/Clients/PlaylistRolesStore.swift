import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct PlaylistRolesStore: Sendable {
  public var read: @Sendable () async throws -> PlaylistRoles?
  public var write: @Sendable (_ roles: PlaylistRoles) async throws -> Void
  public var fileURL: @Sendable () -> URL = { URL(fileURLWithPath: "/") }
}

extension PlaylistRolesStore: TestDependencyKey {
  public static var testValue: Self {
    let storage = PlaylistRolesMemoryStore()
    return Self(read: { await storage.value }, write: { await storage.set($0) }, fileURL: { URL(fileURLWithPath: "/test/Taste Intelligence/playlist-roles.json") })
  }
}

extension PlaylistRolesStore: DependencyKey {
  public static var liveValue: Self {
    let url = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/playlist-roles.json")
    return Self(
      read: {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try coordinatedRead(url)
        return try PlaylistRolesCodec.decode(data)
      },
      write: { roles in
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PlaylistRolesCodec.encode(roles)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
          do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
      },
      fileURL: { url }
    )
  }
}

private func coordinatedRead(_ url: URL) throws -> Data {
  let coordinator = NSFileCoordinator(filePresenter: nil)
  var coordinationError: NSError?
  var result: Result<Data, Error>?
  coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
    result = Result { try Data(contentsOf: target) }
  }
  if let coordinationError { throw coordinationError }
  return try result?.get() ?? Data()
}

extension DependencyValues {
  public var playlistRolesStore: PlaylistRolesStore {
    get { self[PlaylistRolesStore.self] }
    set { self[PlaylistRolesStore.self] = newValue }
  }
}

private actor PlaylistRolesMemoryStore {
  var value: PlaylistRoles?
  func set(_ next: PlaylistRoles) { value = next }
}
