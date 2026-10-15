import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct AppleMusicCatalogClient: Sendable {
  public var authorizationStatus: @Sendable () async -> MusicKitAuthorization = { .notDetermined }
  public var requestAuthorization: @Sendable () async -> MusicKitAuthorization = { .notDetermined }
  public var subscriptionStatus: @Sendable () async throws -> AppleMusicSubscriptionStatus
  public var searchSongs: @Sendable (_ term: String, _ limit: Int) async throws -> [CatalogSongCandidate]
  public var createLibraryPlaylist: @Sendable (
    _ name: String,
    _ description: String?,
    _ songIDs: [String]
  ) async throws -> CreatedPlaylistRef
  public var appendToLibraryPlaylist: @Sendable (_ id: String, _ songIDs: [String]) async throws -> Void
}

public enum MusicKitAuthorization: Equatable, Sendable {
  case authorized
  case notDetermined
  case denied
  case restricted
  case unknown
}

public struct AppleMusicSubscriptionStatus: Equatable, Sendable {
  public var canPlayCatalogContent: Bool
  public var hasCloudLibraryEnabled: Bool

  public init(canPlayCatalogContent: Bool, hasCloudLibraryEnabled: Bool) {
    self.canPlayCatalogContent = canPlayCatalogContent
    self.hasCloudLibraryEnabled = hasCloudLibraryEnabled
  }
}

public struct CreatedPlaylistRef: Equatable, Sendable {
  public var id: String
  public var name: String
  public var trackCount: Int

  public init(id: String, name: String, trackCount: Int) {
    self.id = id
    self.name = name
    self.trackCount = trackCount
  }
}

public struct AppleMusicAPIError: LocalizedError, Equatable, Sendable {
  public var statusCode: Int
  public var detail: String

  public init(statusCode: Int, detail: String) {
    self.statusCode = statusCode
    self.detail = detail
  }

  public var errorDescription: String? {
    "Apple Music returned HTTP \(statusCode): \(detail)"
  }
}

/// Apple Music answered a catalog request with rate limiting (HTTP 429) or a body MusicKit
/// couldn't read. Catalog searches are safe to retry after a pause.
public struct AppleMusicCatalogBusyError: LocalizedError, Equatable, Sendable {
  public init() {}

  public var errorDescription: String? {
    "Apple Music is limiting searches right now. Try Search again in a moment."
  }
}

extension AppleMusicCatalogClient: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension DependencyValues {
  public var appleMusicCatalogClient: AppleMusicCatalogClient {
    get { self[AppleMusicCatalogClient.self] }
    set { self[AppleMusicCatalogClient.self] = newValue }
  }
}
