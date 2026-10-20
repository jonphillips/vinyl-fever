import Foundation

public enum LibrarySearchResource: Equatable, Sendable {
  case albums
  case songs
}

/// Decodes both `/v1/me/library/search` and paged library-album track responses.
public struct LibrarySearchPage: Decodable, Sendable {
  public struct Resource: Decodable, Sendable {
    public var id: String
    public var attributes: Attributes

    public struct Attributes: Decodable, Sendable {
      public var name: String
      public var artistName: String?
      public var albumName: String?
      public var playParams: PlayParameters?

      public struct PlayParameters: Decodable, Sendable {
        public var catalogId: String?
      }
    }

    public var albumCandidate: LibraryAlbumCandidate {
      LibraryAlbumCandidate(id: id, title: attributes.name)
    }

    public var songCandidate: LibrarySongCandidate {
      LibrarySongCandidate(
        id: id,
        title: attributes.name,
        artist: attributes.artistName ?? "",
        album: attributes.albumName ?? "",
        hasCatalogID: attributes.playParams?.catalogId != nil)
    }
  }

  public struct ResourceCollection: Decodable, Sendable {
    public var data: [Resource]?
    public var next: String?
    public var items: [Resource] { data ?? [] }
  }

  public struct Results: Decodable, Sendable {
    public var libraryAlbums: ResourceCollection?
    public var librarySongs: ResourceCollection?

    enum CodingKeys: String, CodingKey {
      case libraryAlbums = "library-albums"
      case librarySongs = "library-songs"
    }
  }

  public var results: Results?
  public var data: [Resource]?
  public var next: String?

  public var albumResults: ResourceCollection? { results?.libraryAlbums }
  public var songResults: ResourceCollection? { results?.librarySongs }
  public var relationshipItems: [Resource] { data ?? [] }
}

public struct PlaylistSongPayload: Encodable, Equatable, Sendable {
  public var id: String
  public var type: String

  public init(_ reference: PlaylistSongReference) {
    id = reference.id
    type = reference.source == .libraryUpload ? "library-songs" : "songs"
  }
}

public enum AppleMusicPlaylistRequestEncoder {
  public static func createBody(name: String, description: String?, songs: [PlaylistSongReference])
    throws -> Data
  {
    try JSONEncoder().encode(CreateBody(
      attributes: .init(name: name, description: description),
      relationships: .init(tracks: .init(data: songs.map(PlaylistSongPayload.init)))))
  }

  public static func appendBody(songs: [PlaylistSongReference]) throws -> Data {
    try JSONEncoder().encode(TracksBody(data: songs.map(PlaylistSongPayload.init)))
  }

  private struct CreateBody: Encodable {
    var attributes: Attributes
    var relationships: Relationships

    struct Attributes: Encodable {
      var name: String
      var description: String?
    }

    struct Relationships: Encodable {
      var tracks: Tracks
    }

    struct Tracks: Encodable {
      var data: [PlaylistSongPayload]
    }
  }

  private struct TracksBody: Encodable {
    var data: [PlaylistSongPayload]
  }
}
