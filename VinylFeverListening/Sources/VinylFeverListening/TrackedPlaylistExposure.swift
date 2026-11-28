import Dependencies
import DependenciesMacros
import Foundation
import MusicKit
import VinylFeverNotes

public enum TrackedPlaylistCatalogResult: Equatable, Sendable {
  case snapshot(TrackedPlaylistSnapshot)
  case gap(TrackedPlaylistGap)
}

public struct TrackedPlaylistLibraryEntry: Equatable, Sendable {
  public var name: String
  public var catalogID: String?
  public init(name: String, catalogID: String?) { self.name = name; self.catalogID = catalogID }
}

public enum TrackedPlaylistCatalogResolution: Equatable, Sendable {
  case found(String)
  case gap(String)
}

public enum TrackedPlaylistCatalogResolver {
  public static func resolve(name: String, library: [TrackedPlaylistLibraryEntry], cachedID: String? = nil) -> TrackedPlaylistCatalogResolution {
    let matches = library.filter { $0.name == name }
    guard matches.count == 1 else {
      return .gap(matches.isEmpty
        ? "Apple Music couldn't find this tracked catalog playlist."
        : "Apple Music returned more than one library playlist with this name.")
    }
    guard let catalogID = matches[0].catalogID ?? cachedID, !catalogID.isEmpty else {
      return .gap("Apple Music did not provide a catalog ID for this tracked playlist.")
    }
    return .found(catalogID)
  }
}

public enum TrackedPlaylistSnapshotPolicy {
  public static func shouldAppend(_ snapshot: TrackedPlaylistSnapshot, after records: [TrackedPlaylistRecord]) -> Bool {
    let latest = records.compactMap { record -> TrackedPlaylistSnapshot? in
      guard case let .snapshot(value) = record, value.name == snapshot.name else { return nil }
      return value
    }.max { $0.fetchedAt < $1.fetchedAt }
    return latest?.catalogID != snapshot.catalogID || latest?.lastModifiedDate != snapshot.lastModifiedDate
  }
}

@DependencyClient
public struct TrackedPlaylistCatalogClient: Sendable {
  public var fetch: @Sendable (_ playlists: [PlaylistRoleEntry], _ host: String, _ fetchedAt: Date) async -> [TrackedPlaylistCatalogResult] = { _, _, _ in [] }
}

extension TrackedPlaylistCatalogClient: TestDependencyKey {
  public static var testValue: Self { Self(fetch: { _, _, _ in [] }) }
}

extension DependencyValues {
  public var trackedPlaylistCatalogClient: TrackedPlaylistCatalogClient {
    get { self[TrackedPlaylistCatalogClient.self] }
    set { self[TrackedPlaylistCatalogClient.self] = newValue }
  }
}

extension TrackedPlaylistCatalogClient: DependencyKey {
  public static var liveValue: Self {
    Self(fetch: { playlists, host, fetchedAt in
      guard !playlists.isEmpty else { return [] }
      do {
        let library = try await Self.libraryPlaylists()
        var results: [TrackedPlaylistCatalogResult] = []
        for playlist in playlists {
          let cached = Self.readCache()[playlist.name]
          switch TrackedPlaylistCatalogResolver.resolve(name: playlist.name, library: library, cachedID: cached) {
          case let .gap(detail):
            results.append(.gap(TrackedPlaylistGap(name: playlist.name, fetchedAt: fetchedAt, host: host, detail: detail)))
            continue
          case let .found(catalogID):
            var cache = Self.readCache()
            cache[playlist.name] = catalogID
            Self.writeCache(cache)
            do {
              let value = try await Self.fetch(catalogID: catalogID)
              results.append(.snapshot(TrackedPlaylistSnapshot(name: playlist.name, catalogID: catalogID,
                lastModifiedDate: value.modified, fetchedAt: fetchedAt, host: host, tracks: value.tracks)))
            } catch {
              results.append(.gap(TrackedPlaylistGap(name: playlist.name, fetchedAt: fetchedAt, host: host,
                detail: error.localizedDescription)))
            }
          }
        }
        return results
      } catch {
        return playlists.map { .gap(TrackedPlaylistGap(name: $0.name, fetchedAt: fetchedAt, host: host,
          detail: error.localizedDescription)) }
      }
    })
  }

  private static func libraryPlaylists() async throws -> [TrackedPlaylistLibraryEntry] {
    var next: String? = "https://api.music.apple.com/v1/me/library/playlists?limit=100"
    var playlists: [TrackedPlaylistLibraryEntry] = []
    while let urlString = next {
      guard let url = URL(string: urlString), url.host == "api.music.apple.com" else {
        throw NewMusicExposureError.invalidEndpoint
      }
      let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
      let page = try JSONDecoder().decode(LibraryPlaylistsEnvelope.self, from: response.data)
      playlists += page.data.map { TrackedPlaylistLibraryEntry(name: $0.attributes.name,
        catalogID: $0.attributes.playParams?.globalId ?? $0.relationships?.catalog?.data?.first?.id) }
      if let path = page.next {
        guard let nextURL = URL(string: path, relativeTo: URL(string: "https://api.music.apple.com")!)?.absoluteURL,
          nextURL.host == "api.music.apple.com" else { throw NewMusicExposureError.invalidEndpoint }
        next = nextURL.absoluteString
      } else { next = nil }
    }
    return playlists
  }

  private static func fetch(catalogID: String) async throws -> (modified: Date, tracks: [TrackedPlaylistTrack]) {
    let storefrontResponse = try await MusicDataRequest(urlRequest: URLRequest(url: URL(string: "https://api.music.apple.com/v1/me/storefront")!)).response()
    let storefront = try JSONDecoder().decode(StorefrontEnvelope.self, from: storefrontResponse.data).data.first?.id
    guard let storefront else { throw NewMusicExposureError.storefrontUnresolved }
    let firstURL = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/playlists/\(catalogID)?include=tracks")!
    let firstResponse = try await MusicDataRequest(urlRequest: URLRequest(url: firstURL)).response()
    let firstPage = try JSONDecoder().decode(CatalogPlaylistPage.self, from: firstResponse.data)
    guard let playlist = firstPage.data.first,
      let modified = playlist.attributes.lastModifiedDate.flatMap(Self.parseDate) else {
      throw NewMusicExposureError.invalidPlaylist
    }
    var tracks = playlist.relationships?.tracks?.data.compactMap(Self.track) ?? []
    var next = playlist.relationships?.tracks?.next
    while let upcoming = next, tracks.count < 1_000 {
      guard let url = URL(string: upcoming, relativeTo: firstURL)?.absoluteURL,
        url.host == "api.music.apple.com" else { throw NewMusicExposureError.invalidEndpoint }
      let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
      let page = try JSONDecoder().decode(CatalogTracksPage.self, from: response.data)
      tracks += page.data.compactMap(Self.track)
      next = page.next
    }
    return (modified, Array(tracks.prefix(1_000)))
  }

  private static func track(_ track: CatalogPlaylistPage.Track) -> TrackedPlaylistTrack? {
    guard track.type == "songs" else { return nil }
    return TrackedPlaylistTrack(catalogID: track.id, title: track.attributes.name,
      artist: track.attributes.artistName, album: track.attributes.albumName,
      releaseDate: track.attributes.releaseDate, dateAdded: parseDate(track.attributes.dateAdded))
  }

  private static func parseDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private static var cacheURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appending(path: "VinylFever/Listening/tracked-playlist-catalog-ids.json")
  }

  private static func readCache() -> [String: String] {
    guard let data = try? Data(contentsOf: cacheURL),
      let cache = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return cache
  }

  private static func writeCache(_ value: [String: String]) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: cacheURL, options: .atomic)
  }
}

private struct LibraryPlaylistsEnvelope: Decodable {
  var data: [Resource]
  var next: String?
  struct Resource: Decodable { var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var name: String; var playParams: PlayParams? }
  struct PlayParams: Decodable { var globalId: String? }
  struct Relationships: Decodable { var catalog: Catalog? }
  struct Catalog: Decodable { var data: [Reference]? }
  struct Reference: Decodable { var id: String }
}
private struct StorefrontEnvelope: Decodable { var data: [Resource]; struct Resource: Decodable { var id: String } }
private struct CatalogPlaylistPage: Decodable {
  var data: [Resource]
  struct Resource: Decodable { var attributes: Attributes; var relationships: Relationships? }
  struct Attributes: Decodable { var lastModifiedDate: String? }
  struct Relationships: Decodable { var tracks: TrackRelation? }
  struct TrackRelation: Decodable { var data: [Track]; var next: String? }
  struct Track: Decodable { var id: String; var type: String; var attributes: TrackAttributes }
  struct TrackAttributes: Decodable {
    var name: String; var artistName: String; var albumName: String?
    var releaseDate: String?; var dateAdded: String?
  }
}
private struct CatalogTracksPage: Decodable {
  var data: [CatalogPlaylistPage.Track]
  var next: String?
}
