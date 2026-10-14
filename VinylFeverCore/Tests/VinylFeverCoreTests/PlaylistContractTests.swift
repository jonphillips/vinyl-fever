import Foundation
import Testing
import VinylFeverCore

@Suite("Playlist contract")
struct PlaylistContractTests {
  @Test("decodes a clean marked playlist")
  func cleanBlock() throws {
    let result = try PlaylistContract.decode("""
      VF-PLAYLIST: v1
      {"name":"  Power Pop  ","description":"  Deep cuts ","tracks":[{"artist":"The Records","title":"Starry Eyes","album":"The Records","year":1979}]}
      """)
    #expect(result.request.name == "Power Pop")
    #expect(result.request.description == "Deep cuts")
    #expect(result.request.tracks == [TrackRequest(index: 1, artist: "The Records", title: "Starry Eyes", album: "The Records", year: 1979)])
    #expect(result.warning == nil)
    #expect(result.droppedTracks.isEmpty)
  }

  @Test("decodes a valid playlist without the marker and returns a warning")
  func missingMarker() throws {
    let result = try PlaylistContract.decode(#"{"name":"List","tracks":[{"artist":"A","title":"B"}]}"#)
    #expect(result.warning?.contains("missing its contract marker") == true)
  }

  @Test("rejects a newer marker")
  func newerMarker() {
    #expect(throws: PlaylistContractError.unsupportedMarker(found: "VF-PLAYLIST: v2", expected: "VF-PLAYLIST: v1")) {
      try PlaylistContract.decode("VF-PLAYLIST: v2\n{\"name\":\"List\",\"tracks\":[{\"artist\":\"A\",\"title\":\"B\"}]}")
    }
  }

  @Test("recovers a fenced block with typographic quotes")
  func fencedAndSmartQuoted() throws {
    let result = try PlaylistContract.decode("""
      VF-PLAYLIST: v1
      ```json
      {“name”:“List”,“tracks”:[{“artist”:“Björk”,“title”:“Jóga”}]}
      ```
      """)
    #expect(result.request.tracks.first?.artist == "Björk")
    #expect(result.request.tracks.first?.title == "Jóga")
  }

  @Test("preserves curly quotes inside otherwise valid JSON values")
  func curlyQuotesInValue() throws {
    let result = try PlaylistContract.decode(#"""
      VF-PLAYLIST: v1
      {"name":"List","description":"the “B-side” set","tracks":[{"artist":"Artist","title":"Song"}]}
      """#)
    #expect(result.request.description == "the “B-side” set")
  }

  @Test("prose and malformed JSON produce typed errors")
  func invalidJSON() {
    #expect(throws: PlaylistContractError.invalidJSON) {
      try PlaylistContract.decode("VF-PLAYLIST: v1\nHere is your playlist")
    }
    #expect(throws: PlaylistContractError.invalidJSON) {
      try PlaylistContract.decode("VF-PLAYLIST: v1\n{\"name\":\"List\",\"tracks\":[}")
    }
  }

  @Test("drops and reports tracks with an empty artist or title")
  func dropsEmptyTracks() throws {
    let result = try PlaylistContract.decode(#"""
      VF-PLAYLIST: v1
      {"name":"List","tracks":[{"artist":"  ","title":"Missing artist"},{"artist":"Present","title":"  "},{"artist":"Kept","title":"Song"}]}
      """#)
    #expect(result.request.tracks.map(\.title) == ["Song"])
    #expect(result.droppedTracks == [
      DroppedPlaylistTrack(index: 1, artist: "", title: "Missing artist"),
      DroppedPlaylistTrack(index: 2, artist: "Present", title: ""),
    ])
  }

  @Test("pins the Project instructions byte for byte")
  func instructionsStayPinned() throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { root.deleteLastPathComponent() }
    let instructions = try String(contentsOf: root.appending(path: "docs/chatgpt/PLAYLIST-CONTRACT.md"), encoding: .utf8)
    #expect(instructions == PlaylistContract.projectInstructions)
  }
}
