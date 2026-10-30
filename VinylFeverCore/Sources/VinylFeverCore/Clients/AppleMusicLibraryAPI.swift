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
