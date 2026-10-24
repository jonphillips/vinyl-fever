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
      let catalogID: String
      if let value = try? String(contentsOf: cached, encoding: .utf8), !value.isEmpty {
        catalogID = value.trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        let library = try await MusicDataRequest(urlRequest: Self.request(
          path: "/v1/me/library/playlists", query: [
            URLQueryItem(name: "filter[name]", value: "New Music"),
            URLQueryItem(name: "include", value: "catalog"),
            URLQueryItem(name: "limit", value: "100"),
          ])).response()
        let envelope = try JSONDecoder().decode(LibraryPlaylistEnvelope.self, from: library.data)
        guard let match = envelope.data.first(where: { $0.attributes.name == "New Music" }),
          let id = match.relationships?.catalog?.data.first?.id else {
          throw NewMusicExposureError.playlistUnresolved
        }
        catalogID = id
        try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(id.utf8).write(to: cached, options: .atomic)
      }

      let storefrontResponse = try await MusicDataRequest(urlRequest: Self.request(path: "/v1/me/storefront")).response()
      let storefront = try JSONDecoder().decode(StorefrontEnvelope.self, from: storefrontResponse.data).data.first?.id
      guard let storefront else { throw NewMusicExposureError.storefrontUnresolved }
      let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/playlists/\(catalogID)?include=tracks&limit=100")!
      let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
      let decoded = try JSONDecoder().decode(CatalogPlaylistEnvelope.self, from: response.data)
      guard let playlist = decoded.data.first,
        let modified = Self.date(playlist.attributes.lastModifiedDate) else {
        throw NewMusicExposureError.invalidPlaylist
      }
      var resources = playlist.relationships?.tracks?.data ?? []
      var next = playlist.relationships?.tracks?.next
      while let pageURL = next, resources.count < 1_000 {
        guard let url = URL(string: pageURL) else { throw NewMusicExposureError.invalidPlaylist }
        let page = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        let pageData = try JSONDecoder().decode(CatalogTracksEnvelope.self, from: page.data)
        resources.append(contentsOf: pageData.data)
        next = pageData.next
      }
      let tracks = resources.prefix(1_000).compactMap { resource -> NewMusicTrack? in
        guard resource.type == "songs" else { return nil }
        return NewMusicTrack(catalogID: resource.id, title: resource.attributes.name,
          artist: resource.attributes.artistName, album: resource.attributes.albumName,
          releaseDate: resource.attributes.releaseDate,
          durationSeconds: resource.attributes.durationInMillis.map { Double($0) / 1_000 })
      }
      return NewMusicCatalogWeek(lastModifiedDate: modified, tracks: tracks)
    })
  }

  private static func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
    var components = URLComponents(string: "https://api.music.apple.com\(path)")!
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else { throw NewMusicExposureError.invalidEndpoint }
    var request = URLRequest(url: url); request.httpMethod = "GET"; return request
  }

  private static func date(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = formatter.date(from: value) { return parsed }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

private enum NewMusicCatalogCache {
  static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "VinylFever/Listening/new-music-catalog-id.txt")
}

private struct LibraryPlaylistEnvelope: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var name: String }
  struct Relationships: Decodable { var catalog: Relation? }
  struct Relation: Decodable { var data: [Reference] }
  struct Reference: Decodable { var id: String }
}
private struct StorefrontEnvelope: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var id: String }
}
private struct CatalogPlaylistEnvelope: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var lastModifiedDate: String }
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
  case invalidEndpoint, playlistUnresolved, storefrontUnresolved, invalidPlaylist, notConfigured
  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "Apple Music's New Music endpoint is invalid."
    case .playlistUnresolved: "The library playlist ‘New Music’ did not expose a catalog playlist ID."
    case .storefrontUnresolved: "Apple Music did not return this account's storefront."
    case .invalidPlaylist: "Apple Music returned an unreadable New Music playlist."
    case .notConfigured: "The New Music exposure client is unavailable in this environment."
    }
  }
}
