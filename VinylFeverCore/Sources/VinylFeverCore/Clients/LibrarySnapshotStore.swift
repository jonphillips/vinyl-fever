import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LibrarySnapshotStore: Sendable {
  public var read: @Sendable () async throws -> LibrarySnapshot?
  public var write: @Sendable (_ snapshot: LibrarySnapshot) async throws -> Void
  public var readAliases: @Sendable () throws -> [String: String]
  public var writeAliases: @Sendable (_ aliases: [String: String]) async throws -> Void
  public var modifiedAt: @Sendable () async throws -> Date?
}

extension LibrarySnapshotStore: TestDependencyKey {
  public static var testValue: Self {
    let storage = SnapshotMemoryStore()
    return Self(
      read: { await storage.snapshot }, write: { await storage.set($0) }, readAliases: { [:] }, writeAliases: { _ in },
      modifiedAt: { await storage.modifiedAt })
  }
}

extension DependencyValues {
  public var librarySnapshotStore: LibrarySnapshotStore {
    get { self[LibrarySnapshotStore.self] }
    set { self[LibrarySnapshotStore.self] = newValue }
  }
}

private actor SnapshotMemoryStore {
  var snapshot: LibrarySnapshot?
  var modifiedAt: Date?
  func set(_ value: LibrarySnapshot) {
    snapshot = value
    modifiedAt = value.generatedAt
  }
}
