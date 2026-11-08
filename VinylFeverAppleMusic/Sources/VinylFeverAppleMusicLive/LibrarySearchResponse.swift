import Foundation
import VinylFeverAppleMusic

enum LibrarySearchResource: Equatable { case albums, songs }

struct LibrarySearchPage: Decodable {
  struct Resource: Decodable {
    var id: String
    var attributes: Attributes
    struct Attributes: Decodable {
      var name: String
      var artistName: String?
      var albumName: String?
      var playParams: PlayParameters?
      struct PlayParameters: Decodable { var catalogId: String? }
    }
    var albumCandidate: LibraryAlbumCandidate { .init(id: id, title: attributes.name) }
    var songCandidate: LibrarySongCandidate {
      .init(id: id, title: attributes.name, artist: attributes.artistName ?? "",
        album: attributes.albumName ?? "", hasCatalogID: attributes.playParams?.catalogId != nil)
    }
  }
  struct ResourceCollection: Decodable {
    var data: [Resource]?
    var next: String?
    var items: [Resource] { data ?? [] }
  }
  struct Results: Decodable {
    var libraryAlbums: ResourceCollection?
    var librarySongs: ResourceCollection?
    enum CodingKeys: String, CodingKey { case libraryAlbums = "library-albums"; case librarySongs = "library-songs" }
  }
  var results: Results?
  var data: [Resource]?
  var next: String?
  var albumResults: ResourceCollection? { results?.libraryAlbums }
  var songResults: ResourceCollection? { results?.librarySongs }
  var relationshipItems: [Resource] { data ?? [] }
}
