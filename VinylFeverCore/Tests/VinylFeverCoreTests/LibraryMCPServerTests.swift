import Foundation
import MCPServerKit
import Testing
import VinylFeverCore

struct LibraryMCPServerTests {
  @Test("tool list matches the brief's names, properties, enums, and annotations")
  func toolsList() async throws {
    let server = LibraryMCPServer.make(snapshotURL: temporaryDirectory().appending(path: "missing.json"), inboxRoot: temporaryDirectory())
    let tools = try await listedTools(server)
    let expected: [String: Set<String>] = [
      "library_overview": [],
      "top_artists": ["by", "limit"],
      "top_tracks": ["by", "limit"],
      "search_library": ["artist", "title", "album", "genre", "year_from", "year_to", "min_plays", "max_plays", "favorited", "availability", "sort", "limit"],
      "artist_profile": ["artist"],
      "check_tracks": ["tracks"],
      "stage_playlist": ["name", "description", "tracks"],
    ]
    #expect(Set(tools.compactMap { $0["name"] as? String }) == Set(expected.keys))
    for tool in tools {
      let name = try #require(tool["name"] as? String)
      let schema = try #require(tool["inputSchema"] as? [String: Any])
      let properties = try #require(schema["properties"] as? [String: Any])
      #expect(Set(properties.keys) == expected[name])
      let annotations = try #require(tool["annotations"] as? [String: Any])
      #expect(annotations["openWorldHint"] as? Bool == false)
      if name == "stage_playlist" {
        #expect(annotations["destructiveHint"] as? Bool == false)
        #expect(annotations["readOnlyHint"] == nil)
      } else {
        #expect(annotations["readOnlyHint"] as? Bool == true)
      }
    }
    #expect(enumValues(in: tools, tool: "top_artists", property: "by") == ["plays", "favorites", "recently_added"])
    #expect(enumValues(in: tools, tool: "top_tracks", property: "by") == ["plays", "favorites", "recently_added", "recently_played"])
  }

  @Test("every read tool fails loudly without a snapshot")
  func noSnapshot() async throws {
    let server = LibraryMCPServer.make(snapshotURL: temporaryDirectory().appending(path: "missing.json"), inboxRoot: temporaryDirectory())
    for (id, name, arguments) in [
      (1, "library_overview", "{}"), (2, "top_artists", "{}"), (3, "top_tracks", "{}"),
      (4, "search_library", "{}"), (5, "artist_profile", #"{"artist":"Missing"}"#),
      (6, "check_tracks", #"{"tracks":[]}"#),
    ] {
      let response = try #require(await call(server, id: id, name: name, arguments: arguments))
      #expect(response.contains("Open Vinyl Fever to build the library snapshot."))
      #expect(response.contains("\"isError\":true"))
    }
  }

  @Test("read tools return structured fixture data, order, filters, and version totals")
  func readTools() async throws {
    let (server, _) = try makeServer(snapshot: s0Fixture())
    let artists = try #require(await resultJSON(server, id: 1, name: "top_artists", arguments: #"{"by":"plays","limit":2}"#) as? [[String: Any]])
    #expect(artists.count == 2)
    #expect(artists[0]["artist"] as? String == "Artist 2")
    #expect((artists[0]["plays"] as? Int ?? 0) > (artists[1]["plays"] as? Int ?? 0))

    let tracks = try #require(await resultJSON(server, id: 2, name: "top_tracks", arguments: #"{"by":"plays","limit":3}"#) as? [[String: Any]])
    #expect(tracks.count == 3)
    #expect(tracks.compactMap { $0["playCount"] as? Int } == [29, 28, 27])

    let search = try #require(await resultJSON(server, id: 3, name: "search_library", arguments: #"{"year_from":1984,"year_to":1990,"min_plays":5,"max_plays":10,"sort":"title","limit":10}"#) as? [[String: Any]])
    #expect(search.count == 6)
    #expect(search.compactMap { $0["year"] as? Int } == Array(1985...1990))

    let profile = try #require(await resultJSON(server, id: 4, name: "artist_profile", arguments: #"{"artist":"Beyoncé"}"#) as? [String: Any])
    #expect(profile["uploadedTrackCount"] as? Int == 1)

    let checks = try #require(await resultJSON(server, id: 5, name: "check_tracks", arguments: #"{"tracks":[{"artist":"Version Artist","title":"Version Song"}]}"#) as? [[String: Any]])
    #expect(checks.first?["plays"] as? Int == 12)
    #expect(checks.first?["versionCount"] as? Int == 2)

    let missing = try #require(await call(server, id: 6, name: "artist_profile", arguments: #"{"artist":"No Such Artist"}"#))
    #expect(missing.contains("No tracks by \"No Such Artist\" in Jon's library."))
    #expect(!missing.contains("\"isError\":true"))
  }

  @Test("rejects unknown keys and enum values while omitted ranking defaults to plays")
  func argumentValidation() async throws {
    let (server, _) = try makeServer(snapshot: s0Fixture())
    let unknown = try #require(await call(server, id: 1, name: "top_tracks", arguments: #"{"ranking":"bogus"}"#))
    #expect(unknown.contains("Unknown argument \"ranking\""))
    #expect(unknown.contains("\"isError\":true"))
    let invalid = try #require(await call(server, id: 2, name: "top_tracks", arguments: #"{"by":"bogus"}"#))
    #expect(invalid.contains("Unrecognized value \"bogus\""))
    #expect(invalid.contains("\"isError\":true"))
    let defaulted = try #require(await resultJSON(server, id: 3, name: "top_tracks", arguments: #"{"limit":1}"#) as? [[String: Any]])
    #expect(defaulted.first?["playCount"] as? Int == 29)
  }

  @Test("overview keeps the snapshot generation time across cache hits")
  func overviewCache() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let (server, snapshotURL) = try makeServer(snapshot: s0Fixture(generatedAt: generatedAt))
    try FileManager.default.setAttributes([.modificationDate: generatedAt.addingTimeInterval(500)], ofItemAtPath: snapshotURL.path)
    let first = try #require(await resultJSON(server, id: 1, name: "library_overview", arguments: "{}") as? [String: Any])
    let second = try #require(await resultJSON(server, id: 2, name: "library_overview", arguments: "{}") as? [String: Any])
    #expect(first["generatedAt"] as? String == "2023-11-14T22:13:20Z")
    #expect(second["generatedAt"] as? String == first["generatedAt"] as? String)
  }

  @Test("staging reports dropped rows, writes the valid contract, and rejects empty requests")
  func stagePlaylist() async throws {
    let root = temporaryDirectory()
    let inbox = root.appending(path: "PlaylistInbox", directoryHint: .isDirectory)
    let (server, _) = try makeServer(snapshot: s0Fixture(), inbox: inbox)
    let valid = try #require(await call(server, id: 1, name: "stage_playlist", arguments: #"{"name":"Power Pop","tracks":[{"artist":" ","title":"Dropped"},{"artist":"The Records","title":"Starry Eyes"}]}"#))
    #expect(valid.contains("\"staged\":true"))
    #expect(valid.contains("\"trackCount\":1"))
    #expect(valid.contains("\"dropped\":[{\"artist\":\"\",\"index\":1,\"title\":\"Dropped\"}]"))
    #expect(valid.contains("Jon reviews and creates it in Vinyl Fever; nothing is in Apple Music yet."))
    #expect(!valid.contains(".vfplaylist"))
    let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
    let stagedURL = try #require(files.first)
    let decoded = try PlaylistContract.decode(String(contentsOf: stagedURL, encoding: .utf8))
    #expect(decoded.request == PlaylistRequest(name: "Power Pop", tracks: [TrackRequest(index: 2, artist: "The Records", title: "Starry Eyes")]))

    let countBefore = files.count
    let zero = try #require(await call(server, id: 2, name: "stage_playlist", arguments: #"{"name":"Empty","tracks":[]}"#))
    #expect(zero.contains("tracks must contain at least one track"))
    #expect(zero.contains("\"isError\":true"))
    #expect(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).count == countBefore)
    let emptyName = try #require(await call(server, id: 3, name: "stage_playlist", arguments: #"{"name":" ","tracks":[{"artist":"A","title":"B"}]}"#))
    #expect(emptyName.contains("name must not be empty"))
    #expect(emptyName.contains("\"isError\":true"))
    #expect(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).count == countBefore)
  }

  @Test("instructions use the brief's standalone head and only the track rules tail")
  func instructions() {
    let briefParagraph = "Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any claim about what Jon owns, has played, or has loved — never guess. Before proposing a final list, call check_tracks on it. Tracks with availability \"uploaded\" are library-only and can't be added to a catalog playlist; leave them out. When Jon asks for the playlist, call stage_playlist with the final list instead of printing it; Jon reviews and creates it in Vinyl Fever. Snapshot age is in library_overview."
    #expect(LibraryMCPServer.instructions.hasPrefix(briefParagraph))
    #expect(LibraryMCPServer.instructionHead == briefParagraph)
    #expect(LibraryMCPServer.instructionHead.count <= 512)
    #expect(MCPServer.instructionsHeadStandsAlone(LibraryMCPServer.instructions))
    #expect(LibraryMCPServer.instructions.contains(PlaylistContract.trackRules))
    #expect(!LibraryMCPServer.instructions.contains("VF-PLAYLIST: v1"))
  }

  private func s0Fixture(generatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> LibrarySnapshot {
    var tracks = LibraryTestFixtures.tracks(date: generatedAt)
    tracks += [
      LibraryTrack(persistentID: "v1", name: "Version Song", artist: "Version Artist", playCount: 5),
      LibraryTrack(persistentID: "v2", name: "Version Song", artist: "Version Artist", playCount: 7),
    ]
    return LibrarySnapshot(generatedAt: generatedAt, tracks: tracks)
  }

  private func makeServer(snapshot: LibrarySnapshot, inbox: URL? = nil) throws -> (MCPServer, URL) {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "library-snapshot.json")
    try LibrarySnapshotCodec.encode(snapshot).write(to: snapshotURL)
    return (LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: inbox ?? root.appending(path: "inbox")), snapshotURL)
  }

  private func listedTools(_ server: MCPServer) async throws -> [[String: Any]] {
    let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
    let root = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    let result = try #require(root["result"] as? [String: Any])
    return try #require(result["tools"] as? [[String: Any]])
  }

  private func enumValues(in tools: [[String: Any]], tool name: String, property: String) -> [String] {
    guard let tool = tools.first(where: { $0["name"] as? String == name }),
      let schema = tool["inputSchema"] as? [String: Any],
      let properties = schema["properties"] as? [String: Any],
      let value = properties[property] as? [String: Any],
      let values = value["enum"] as? [String]
    else { return [] }
    return values
  }

  private func call(_ server: MCPServer, id: Int, name: String, arguments: String) async -> String? {
    guard let response = await rawCall(server, id: id, name: name, arguments: arguments) else { return nil }
    let text = contentText(response)
    return response + "\n" + text
  }

  private func resultJSON(_ server: MCPServer, id: Int, name: String, arguments: String) async throws -> Any? {
    guard let response = await rawCall(server, id: id, name: name, arguments: arguments),
      let root = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let content = result["content"] as? [[String: Any]],
      let text = content.first?["text"] as? String
    else { return nil }
    let jsonText = text.components(separatedBy: "\n\nJon reviews and creates it").first ?? text
    return try JSONSerialization.jsonObject(with: Data(jsonText.utf8))
  }

  private func rawCall(_ server: MCPServer, id: Int, name: String, arguments: String) async -> String? {
    await server.handle(line: #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
  }

  private func contentText(_ response: String) -> String {
    guard let root = try? JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let content = result["content"] as? [[String: Any]]
    else { return "" }
    return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
  }

  private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
