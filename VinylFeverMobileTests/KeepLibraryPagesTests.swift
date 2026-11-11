import Foundation
import Testing
@testable import VinylFeverMobile

struct KeepLibraryPagesTests {
  @Test
  func trackPageSkipsMalformedItemsAndKeepsPagination() throws {
    let json = #"""
    {"data":[
      {"id":"good","attributes":{"name":"Song","artistName":"Artist"}},
      {"id":"bad-track","attributes":{"name":"Jeffrey Osborne - On The Wings Of Lo 1"}},
      {"id":"no-attributes"}
    ],"next":"/v1/me/library/playlists/next/tracks"}
    """#

    let page = try KeepLibraryPages.decodeTracks(Data(json.utf8))
    #expect(page.data.count == 1)
    #expect(page.data.first?.id == "good")
    #expect(page.skipped == ["bad-track", "no-attributes"])
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
