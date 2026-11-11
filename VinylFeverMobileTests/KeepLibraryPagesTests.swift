import Foundation
import Testing
@testable import VinylFeverMobile

struct KeepLibraryPagesTests {
  @Test
  func trackPageSkipsMalformedItemsAndKeepsPagination() throws {
    let json = #"""
    {"data":[
      {"id":"good","attributes":{"name":"Song","artistName":"Artist"}},
      {"id":"i.0YJRXHkvem9","type":"library-songs","href":"/v1/me/library/songs/i.0YJRXHkvem9","attributes":{"name":"Jeffrey Osborne - On The Wings Of Lo 1","trackNumber":0,"genreNames":[""],"durationInMillis":243069,"discNumber":0,"hasLyrics":true,"playParams":{"catalogId":"1434921727","id":"i.0YJRXHkvem9","kind":"song","isLibrary":true,"reporting":true,"reportingId":"1434921727"}}},
      {"id":"wrong-type","attributes":{"name":"Song","artistName":42}},
      {"id":"no-attributes"}
    ],"next":"/v1/me/library/playlists/next/tracks"}
    """#

    let page = try KeepLibraryPages.decodeTracks(Data(json.utf8))
    #expect(page.data.map(\.id) == ["good"])
    #expect(page.skipped == ["i.0YJRXHkvem9", "wrong-type", "no-attributes"])
    #expect(page.next == "/v1/me/library/playlists/next/tracks")
  }

  @Test
  func trackPageWithoutDataThrows() {
    #expect(throws: (any Error).self) {
      try KeepLibraryPages.decodeTracks(Data(#"{"next":"/next"}"#.utf8))
    }
  }

  @Test
  func playlistPageSkipsMissingName() throws {
    let json = #"{"data":[{"id":"good","attributes":{"name":"Keepers"}},{"id":"bad","attributes":{}}]}"#
    let page = try KeepLibraryPages.decodePlaylists(Data(json.utf8))
    #expect(page.data.map(\.id) == ["good"])
    #expect(page.skipped == ["bad"])
  }
}
