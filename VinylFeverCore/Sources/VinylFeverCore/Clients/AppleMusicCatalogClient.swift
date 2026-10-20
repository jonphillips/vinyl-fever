import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct AppleMusicCatalogClient: Sendable {
  /// Apple Music documents 25 as the maximum library search page size.
  public static let librarySearchPageSize = 25
  /// The S0 resolver caps one term at four 25-result library search pages.
  public static let librarySongSearchCap = 100
  public var authorizationStatus: @Sendable () async -> MusicKitAuthorization = { .notDetermined }
  public var requestAuthorization: @Sendable () async -> MusicKitAuthorization = { .notDetermined }
  public var subscriptionStatus: @Sendable () async throws -> AppleMusicSubscriptionStatus
  public var searchSongs: @Sendable (_ term: String, _ limit: Int) async throws -> [CatalogSongCandidate]
  public var searchLibraryAlbums: @Sendable (_ term: String) async throws -> [LibraryAlbumCandidate]
  public var libraryAlbumTracks: @Sendable (_ albumID: String) async throws -> [LibrarySongCandidate]
  public var searchLibrarySongs: @Sendable (_ term: String, _ offset: Int) async throws -> [LibrarySongCandidate]
  public var createLibraryPlaylist: @Sendable (
    _ name: String,
    _ description: String?,
    _ songs: [PlaylistSongReference]
  ) async throws -> CreatedPlaylistRef
  public var appendToLibraryPlaylist: @Sendable (_ id: String, _ songs: [PlaylistSongReference]) async throws -> Void
}

public struct PlaylistSongReference: Equatable, Sendable {
  public var id: String
  public var source: CatalogSongCandidate.Source
  public init(id: String, source: CatalogSongCandidate.Source) { self.id = id; self.source = source }
}

public struct LibraryAlbumCandidate: Equatable, Sendable {
  public var id: String
  public var title: String
  public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct LibrarySongCandidate: Equatable, Sendable {
  public var id: String
  public var title: String
  public var artist: String
  public var album: String
  public var hasCatalogID: Bool
  public init(id: String, title: String, artist: String, album: String, hasCatalogID: Bool) {
    self.id = id; self.title = title; self.artist = artist; self.album = album; self.hasCatalogID = hasCatalogID
  }
  public var candidate: CatalogSongCandidate {
    CatalogSongCandidate(id: id, title: title, artistName: artist, albumTitle: album, source: .libraryUpload)
  }
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
