import Dependencies
import DependenciesMacros
import Foundation
import MusicKit

public struct NewMusicTrack: Codable, Equatable, Sendable {
  public var catalogID: String
  public var title: String
  public var artist: String
  public var album: String?
  public var releaseDate: String?
  public var durationSeconds: Double?

  public init(catalogID: String, title: String, artist: String, album: String? = nil,
    releaseDate: String? = nil, durationSeconds: Double? = nil) {
    self.catalogID = catalogID; self.title = title; self.artist = artist; self.album = album
    self.releaseDate = releaseDate; self.durationSeconds = durationSeconds
  }
}

public struct NewMusicWeek: Codable, Equatable, Sendable {
  public var format = "vf-new-music-week"
  public var version = 1
  public var lastModifiedDate: Date
  public var fetchedAt: Date
  public var host: String
  public var tracks: [NewMusicTrack]

  public init(lastModifiedDate: Date, fetchedAt: Date, host: String, tracks: [NewMusicTrack]) {
    self.lastModifiedDate = lastModifiedDate; self.fetchedAt = fetchedAt; self.host = host
    self.tracks = tracks
  }
}

public struct NewMusicExposureGap: Codable, Equatable, Sendable {
  public var format = "vf-new-music-exposure-gap"
  public var version = 1
  public var fetchedAt: Date
  public var host: String
  public var detail: String
  public init(fetchedAt: Date, host: String, detail: String) {
    self.fetchedAt = fetchedAt; self.host = host; self.detail = detail
  }
}

public enum NewMusicExposureRecord: Equatable, Sendable {
  case week(NewMusicWeek)
  case gap(NewMusicExposureGap)
  public var fetchedAt: Date {
    switch self { case let .week(value): value.fetchedAt; case let .gap(value): value.fetchedAt }
  }
  public var lastModifiedDate: Date? {
    guard case let .week(value) = self else { return nil }
    return value.lastModifiedDate
  }
}

@DependencyClient
public struct NewMusicCatalogClient: Sendable {
  public var fetch: @Sendable () async throws -> NewMusicCatalogWeek
}

public struct NewMusicCatalogWeek: Equatable, Sendable {
  public var lastModifiedDate: Date
  public var tracks: [NewMusicTrack]
  public init(lastModifiedDate: Date, tracks: [NewMusicTrack]) {
    self.lastModifiedDate = lastModifiedDate; self.tracks = tracks
  }
}

extension NewMusicCatalogClient: TestDependencyKey {
  public static var testValue: Self { Self(fetch: { throw NewMusicExposureError.notConfigured }) }
}
extension DependencyValues {
  public var newMusicCatalogClient: NewMusicCatalogClient {
    get { self[NewMusicCatalogClient.self] }
    set { self[NewMusicCatalogClient.self] = newValue }
  }
}

/// Apple Music's library playlist relationship is the runtime source of the catalog ID.
/// The ID is cached locally after discovery; no S0 fixture IDs are embedded here.
extension NewMusicCatalogClient: DependencyKey {
  public static var liveValue: Self {
    Self(fetch: {
      let cached = NewMusicCatalogCache.url
      let cachedID = try? String(contentsOf: cached, encoding: .utf8)
      return try await Self.fetchWithRecovery(
        cachedCatalogID: cachedID?.trimmingCharacters(in: .whitespacesAndNewlines),
        resolve: { try await Self.resolveCatalogID() },
        load: { try await Self.fetchCatalogPlaylist($0) },
        cache: { try Self.cache($0, at: cached) },
        invalidate: { try? FileManager.default.removeItem(at: cached) })
    })
  }

  static func fetchWithRecovery(
    cachedCatalogID: String?,
    resolve: @escaping @Sendable () async throws -> String,
    load: @escaping @Sendable (String) async throws -> NewMusicCatalogWeek,
    cache: @escaping @Sendable (String) throws -> Void,
    invalidate: @escaping @Sendable () -> Void
  ) async throws -> NewMusicCatalogWeek {
    if let cachedCatalogID, !cachedCatalogID.isEmpty {
      do { return try await load(cachedCatalogID) }
      catch where isStaleCatalogFailure(error) {
        invalidate()
        let fresh = try await resolve()
        try cache(fresh)
        return try await load(fresh)
      }
    }
    let id = try await resolve()
    try cache(id)
    return try await load(id)
  }

  private static func resolveCatalogID() async throws -> String {
    let first = try libraryPlaylistsRequest()
    var next: String? = first.url?.absoluteString
    while let nextURL = next {
      let response = try await MusicDataRequest(urlRequest: try request(absoluteURL: nextURL)).response()
      let page = try NewMusicCatalogParser.libraryPlaylists(response.data)
      if let id = page.catalogID { return id }
      next = page.next
    }
    throw NewMusicExposureError.playlistUnresolved
  }

  private static func fetchCatalogPlaylist(_ catalogID: String) async throws -> NewMusicCatalogWeek {
    let storefrontResponse = try await MusicDataRequest(urlRequest: try request(path: "/v1/me/storefront")).response()
    let storefront = try JSONDecoder().decode(StorefrontEnvelope.self, from: storefrontResponse.data).data.first?.id
    guard let storefront else { throw NewMusicExposureError.storefrontUnresolved }
    let response: MusicDataResponse
    do {
      response = try await MusicDataRequest(urlRequest: catalogPlaylistRequest(storefront: storefront, catalogID: catalogID)).response()
    }
    catch let error as MusicDataRequest.Error where error.status == 404 { throw NewMusicExposureError.staleCatalogID }
    let page = try NewMusicCatalogParser.catalogPlaylist(response.data)
    var tracks = page.tracks
    var next = page.next
    while let nextURL = next, tracks.count < 1_000 {
      let response = try await MusicDataRequest(urlRequest: try request(absoluteURL: nextURL)).response()
      let nextPage = try NewMusicCatalogParser.catalogTracks(response.data)
      tracks.append(contentsOf: nextPage.tracks)
      next = nextPage.next
    }
    return NewMusicCatalogWeek(lastModifiedDate: page.lastModifiedDate, tracks: Array(tracks.prefix(1_000)))
  }

  private static func cache(_ id: String, at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(id.utf8).write(to: url, options: .atomic)
  }

  private static func isStaleCatalogFailure(_ error: Error) -> Bool {
    if let error = error as? NewMusicExposureError, error == .staleCatalogID || error == .invalidPlaylist { return true }
    if let error = error as? MusicDataRequest.Error, error.status == 404 { return true }
    return false
  }

  static func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
    var components = URLComponents(string: "https://api.music.apple.com\(path)")!
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else { throw NewMusicExposureError.invalidEndpoint }
    var request = URLRequest(url: url); request.httpMethod = "GET"; return request
  }

  static func libraryPlaylistsRequest() throws -> URLRequest {
    try request(path: "/v1/me/library/playlists", query: [URLQueryItem(name: "limit", value: "100")])
  }

  static func catalogPlaylistRequest(storefront: String, catalogID: String) throws -> URLRequest {
    try request(path: "/v1/catalog/\(storefront)/playlists/\(catalogID)",
      query: [URLQueryItem(name: "include", value: "tracks")])
  }

  static func request(absoluteURL: String) throws -> URLRequest {
    guard let url = URL(string: absoluteURL, relativeTo: URL(string: "https://api.music.apple.com")!)?.absoluteURL,
      url.host == "api.music.apple.com" else { throw NewMusicExposureError.invalidEndpoint }
    return URLRequest(url: url)
  }
}

private enum NewMusicCatalogCache {
  static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "VinylFever/Listening/new-music-catalog-id.txt")
}

public struct NewMusicLibraryPlaylistPage: Equatable, Sendable {
  public var catalogID: String?
  public var next: String?
}
public struct NewMusicParsedCatalogPage: Equatable, Sendable {
  public var lastModifiedDate: Date
  public var tracks: [NewMusicTrack]
  public var next: String?
}
public struct NewMusicParsedTracksPage: Equatable, Sendable {
  public var tracks: [NewMusicTrack]
  public var next: String?
}

public enum NewMusicCatalogParser {
  public static let apiRoot = "https://api.music.apple.com"

  public static func endpointURL(_ next: String) throws -> URL {
    guard let url = URL(string: next, relativeTo: URL(string: apiRoot)!)?.absoluteURL,
      url.host == "api.music.apple.com" else { throw NewMusicExposureError.invalidEndpoint }
    return url
  }

  public static func libraryPlaylists(_ data: Data) throws -> NewMusicLibraryPlaylistPage {
    let page = try JSONDecoder().decode(LibraryPlaylistEnvelope.self, from: data)
    let match = page.data.first(where: { $0.attributes.name == "New Music" })
    let id = match?.attributes.playParams?.globalId ?? match?.relationships?.catalog?.data?.first?.id
    return NewMusicLibraryPlaylistPage(catalogID: id, next: page.next)
  }

  public static func catalogPlaylist(_ data: Data) throws -> NewMusicParsedCatalogPage {
    let page = try JSONDecoder().decode(CatalogPlaylistEnvelope.self, from: data)
    guard let playlist = page.data.first, playlist.type == "playlists",
      let modified = parseDate(playlist.attributes.lastModifiedDate) else { throw NewMusicExposureError.invalidPlaylist }
    return NewMusicParsedCatalogPage(lastModifiedDate: modified,
      tracks: (playlist.relationships?.tracks?.data ?? []).compactMap(track),
      next: playlist.relationships?.tracks?.next)
  }

  public static func catalogTracks(_ data: Data) throws -> NewMusicParsedTracksPage {
    let page = try JSONDecoder().decode(CatalogTracksEnvelope.self, from: data)
    return NewMusicParsedTracksPage(tracks: page.data.compactMap(track), next: page.next)
  }

  private static func track(_ resource: CatalogPlaylistEnvelope.Track) -> NewMusicTrack? {
    guard resource.type == "songs" else { return nil }
    return NewMusicTrack(catalogID: resource.id, title: resource.attributes.name,
      artist: resource.attributes.artistName, album: resource.attributes.albumName,
      releaseDate: resource.attributes.releaseDate,
      durationSeconds: resource.attributes.durationInMillis.map { Double($0) / 1_000 })
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

private struct LibraryPlaylistEnvelope: Decodable {
  var data: [Resource]
  var next: String?
  struct Resource: Decodable { var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var name: String; var playParams: PlayParams? }
  struct PlayParams: Decodable { var globalId: String? }
  struct Relationships: Decodable { var catalog: Relation? }
  struct Relation: Decodable { var data: [Reference]? }
  struct Reference: Decodable { var id: String }
}
private struct StorefrontEnvelope: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var id: String }
}
private struct CatalogPlaylistEnvelope: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var type: String; var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var lastModifiedDate: String? }
  struct Relationships: Decodable { var tracks: TrackRelation? }
  struct TrackRelation: Decodable { var data: [Track]; var next: String? }
  struct Track: Decodable { var id: String; var type: String; var attributes: TrackAttributes }
  struct TrackAttributes: Decodable {
    var name: String; var artistName: String; var albumName: String?
    var releaseDate: String?; var durationInMillis: Int?
  }
}
private struct CatalogTracksEnvelope: Decodable {
  var data: [CatalogPlaylistEnvelope.Track]
  var next: String?
}

public enum NewMusicExposureError: Error, Equatable, LocalizedError, Sendable {
  case invalidEndpoint, playlistUnresolved, storefrontUnresolved, invalidPlaylist, staleCatalogID, notConfigured
  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "Apple Music's New Music endpoint is invalid."
    case .playlistUnresolved: "The library playlist ‘New Music’ did not expose a catalog playlist ID."
    case .storefrontUnresolved: "Apple Music did not return this account's storefront."
    case .invalidPlaylist: "Apple Music returned an unreadable New Music playlist."
    case .staleCatalogID: "Apple Music no longer recognizes the cached New Music catalog ID."
    case .notConfigured: "The New Music exposure client is unavailable in this environment."
    }
  }
}
