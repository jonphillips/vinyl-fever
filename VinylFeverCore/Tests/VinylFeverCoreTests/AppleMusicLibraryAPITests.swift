import Foundation
import Testing
import VinylFeverCore

@Suite("Apple Music library API payloads")
struct AppleMusicLibraryAPITests {
  @Test("decode album and song search results, including absent results")
  func searchResponseShapes() throws {
    let albums = try JSONDecoder().decode(LibrarySearchPage.self, from: Data(
      #"{"results":{"library-albums":{"data":[{"id":"album-1","attributes":{"name":"Live at Hall"}}],"next":"/next"}}}"#.utf8))
    #expect(albums.albumResults?.items.map(\.albumCandidate) == [LibraryAlbumCandidate(id: "album-1", title: "Live at Hall")])
    #expect(albums.albumResults?.next == "/next")

    let songs = try JSONDecoder().decode(LibrarySearchPage.self, from: Data(
      #"{"results":{"library-songs":{"data":[{"id":"song-1","attributes":{"name":"Night Drive","artistName":"The Records","albumName":"Live at Hall","playParams":{"catalogId":"catalog-1"}}},{"id":"song-2","attributes":{"name":"Night Drive","artistName":"The Records","albumName":"Live at Hall"}}]}}}"#.utf8))
    #expect(songs.songResults?.items.map(\.songCandidate).map(\.hasCatalogID) == [true, false])

    let missing = try JSONDecoder().decode(LibrarySearchPage.self, from: Data(#"{}"#.utf8))
    #expect(missing.results == nil)
    #expect(missing.albumResults == nil)
    #expect(missing.songResults == nil)
  }

  @Test("create body interleaves catalog and upload resource types in row order")
  func createBodyMixedSources() throws {
    let songs = [
      PlaylistSongReference(id: "one", source: PlaylistSongSource.catalog),
      PlaylistSongReference(id: "two", source: PlaylistSongSource.libraryUpload),
      PlaylistSongReference(id: "three", source: PlaylistSongSource.catalog),
    ]
    let body = try AppleMusicPlaylistRequestEncoder.createBody(
      name: "Mix", description: nil, songs: songs)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let relationships = try #require(json["relationships"] as? [String: Any])
    let tracks = try #require(relationships["tracks"] as? [String: Any])
    let data = try #require(tracks["data"] as? [[String: String]])
    #expect(data.map { $0["type"] } == ["songs", "library-songs", "songs"])
    #expect(data.map { $0["id"] } == ["one", "two", "three"])
  }
}
