import Foundation
import MCPServerKit
import Testing
import VinylFeverCore
import VinylFeverListening

struct LibraryMCPServerTests {
  @Test("tool list matches the brief's names, properties, enums, and annotations")
  func toolsList() async throws {
    let server = LibraryMCPServer.make(snapshotURL: temporaryDirectory().appending(path: "missing.json"), inboxRoot: temporaryDirectory())
    let tools = try await listedTools(server)
    let expected: [String: Set<String>] = [
      "library_overview": [],
      "top_artists": ["by", "period", "limit"],
      "top_tracks": ["by", "period", "limit"],
      "search_library": ["artist", "title", "album", "genre", "year_from", "year_to", "min_plays", "max_plays", "favorited", "availability", "sort", "limit"],
      "artist_profile": ["artist"],
      "check_tracks": ["tracks"],
      "recent_listening": ["period", "limit"],
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
    #expect(enumValues(in: tools, tool: "recent_listening", property: "period") == ["24h", "7d", "30d", "90d"])
    #expect(enumValues(in: tools, tool: "top_artists", property: "period") == ["all_time", "7d", "30d", "90d"])
    let stage = try #require(tools.first { $0["name"] as? String == "stage_playlist" })
    let stageProperties = try #require((stage["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
    #expect((stageProperties["description"] as? [String: Any])?["description"] as? String
      == "One sentence about the music; it becomes the playlist's description in Apple Music. No library stats, availability notes, or dates.")
  }

  @Test("listening calls report setup guidance when no listening log exists")
  func listeningNotSetUp() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), listeningRootURL: root.appending(path: "Listening"))
    let response = try #require(await call(server, id: 9, name: "recent_listening", arguments: #"{"period":"7d"}"#))
    #expect(response.contains("Listening history isn't set up yet"))
    #expect(response.contains("\"isError\":true"))
  }

  @Test("check_tracks returns up to five matching upload album names without IDs")
  func checkTracksUploadedAlbums() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    let uploads = (1...5).map { number in
      LibraryTrack(
        persistentID: "private-upload-id-\(number)", name: "Thunder Road",
        artist: "Bruce Springsteen & The E Street Band (Live)", album: "Show \(number)",
        playCount: 6 - number, availability: .uploaded)
    }
    let unnamedUpload = LibraryTrack(
      persistentID: "private-unnamed-upload-id", name: "Thunder Road",
      artist: "Bruce Springsteen & The E Street Band (Live)", album: " \n ",
      playCount: 99, availability: .uploaded)
    let almostMatch = LibraryTrack(
      persistentID: "private-unrelated-id", name: "Alison", artist: "Elvis", album: "Show",
      availability: .uploaded)
    try LibrarySnapshotCodec.encode(
      LibrarySnapshot(generatedAt: .now, tracks: [unnamedUpload] + uploads + [almostMatch]))
      .write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"))

    let springsteen = try #require(await resultJSON(
      server, id: 40, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Bruce Springsteen","title":"Thunder Road"}]}"#
    ) as? [[String: Any]])
    #expect(springsteen.first?["uploadedAlbums"] as? [String] == (1...5).map { "Show \($0)" })
    #expect(!String(describing: springsteen).contains("private-upload-id"))

    let falsePositives = try #require(await resultJSON(
      server, id: 41, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Bruce SpringsteenX","title":"Thunder Road"},{"artist":"Elvis Costello","title":"Alison"}]}"#
    ) as? [[String: Any]])
    #expect(falsePositives.allSatisfy { ($0["uploadedAlbums"] as? [String]) == [] })
  }

  @Test("listening tools cover periods, gaps, library joins, validation, and omit IDs")
  func listeningTools() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let poller = UUID()
    let now = Date()
    let host = "Fixture Mac"
    let baseline = ListeningFetch(poller: poller, host: host, fetchedAt: now.addingTimeInterval(-70 * 86_400), outcome: .baseline, pagesRead: 1)
    let oldFailure = ListeningFetch(poller: poller, host: host, fetchedAt: now.addingTimeInterval(-60 * 86_400), outcome: .failed, pagesRead: 0, error: "network")
    let play = ListeningFetch(poller: poller, host: host, fetchedAt: now.addingTimeInterval(-3 * 86_400), outcome: .plays, newCount: 1, pagesRead: 1,
      items: [ListeningItem(kind: .song, id: "secret-id", title: "Version Song", artist: "Version Artist", album: "Live")])
    let gap = ListeningFetch(poller: poller, host: host, fetchedAt: now.addingTimeInterval(-2 * 86_400), outcome: .gap, pagesRead: 5,
      items: [ListeningItem(kind: .song, id: "private-id", title: "New Song", artist: "New Artist")])
    let stream = root.appending(path: "Listening/fetches/\(poller.uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
    var data = try ListeningLogCodec.encode(baseline)
    data.append(try ListeningLogCodec.encode(oldFailure))
    data.append(try ListeningLogCodec.encode(play))
    data.append(try ListeningLogCodec.encode(gap))
    try data.write(to: stream.appending(path: "2026-10.jsonl"))
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), listeningRootURL: root.appending(path: "Listening"))

    for period in ["24h", "7d", "30d", "90d"] {
      let result = try #require(await resultJSON(server, id: 30, name: "recent_listening", arguments: #"{"period":"\#(period)"}"#) as? [String: Any])
      let plays = try #require(result["plays"] as? [[String: Any]])
      #expect(period == "24h" ? plays.isEmpty : !plays.isEmpty)
      #expect(result["coverage"] != nil)
      #expect(!String(describing: result).contains(poller.uuidString))
      #expect(!String(describing: result).contains("secret-id"))
    }
    let artists = try #require(await resultJSON(server, id: 31, name: "top_artists", arguments: #"{"period":"7d"}"#) as? [String: Any])
    let weekGaps = try #require((artists["coverage"] as? [String: Any])?["gaps"] as? [[String: Any]])
    #expect(weekGaps.count == 1)
    #expect(weekGaps.first?["outcome"] as? String == "gap")
    let day = try #require(await resultJSON(server, id: 34, name: "recent_listening", arguments: #"{"period":"24h"}"#) as? [String: Any])
    let dayGaps = try #require((day["coverage"] as? [String: Any])?["gaps"] as? [[String: Any]])
    #expect(dayGaps.isEmpty)
    let tracks = try #require(await resultJSON(server, id: 32, name: "top_tracks", arguments: #"{"period":"90d"}"#) as? [String: Any])
    #expect(((tracks["coverage"] as? [String: Any])?["gaps"] as? [[String: Any]])?.count == 2)
    let invalid = try #require(await call(server, id: 33, name: "top_artists", arguments: #"{"period":"7d","by":"favorites"}"#))
    #expect(invalid.contains("Only by: plays is allowed"))
    #expect(invalid.contains("\"isError\":true"))
  }

  @Test("cached listening coverage age advances without a file change")
  func listeningCoverageAgeRefreshesOnCachedLog() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let poller = UUID()
    let instant = Date()
    let clock = TestClock(instant)
    let fetches = [ListeningFetch(poller: poller, host: "Fixture Mac", fetchedAt: instant.addingTimeInterval(-3_600), outcome: .baseline, pagesRead: 1)]
    let stream = root.appending(path: "Listening/fetches/\(poller.uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
    try ListeningLogCodec.encode(fetches[0]).write(to: stream.appending(path: "2026-10.jsonl"))
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), listeningRootURL: root.appending(path: "Listening"), now: { clock.now() })
    let first = try #require(await resultJSON(server, id: 40, name: "recent_listening", arguments: #"{"period":"7d"}"#) as? [String: Any])
    let firstAge = try #require((first["coverage"] as? [String: Any])?["lastFetchAge"] as? Double)
    clock.advance(by: 3_600)
    let second = try #require(await resultJSON(server, id: 41, name: "recent_listening", arguments: #"{"period":"7d"}"#) as? [String: Any])
    let secondAge = try #require((second["coverage"] as? [String: Any])?["lastFetchAge"] as? Double)
    #expect(abs((secondAge - firstAge) - 3_600) < 1)
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
    let briefParagraph = "Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any claim about what Jon owns, has played, or has loved — never guess. Before proposing a final list, call check_tracks on it. For Jon's uploads, use an exact album from uploadedAlbums as the album hint. When Jon asks for the playlist, call stage_playlist with the final list instead of printing it; Jon reviews and creates it in Vinyl Fever. Snapshot age is in library_overview."
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

  private func makeServer(snapshot: LibrarySnapshot, inbox: URL? = nil, listeningRootURL: URL? = nil) throws -> (MCPServer, URL) {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "library-snapshot.json")
    try LibrarySnapshotCodec.encode(snapshot).write(to: snapshotURL)
    return (LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: inbox ?? root.appending(path: "inbox"), listeningRootURL: listeningRootURL ?? root.appending(path: "Listening")), snapshotURL)
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

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var instant: Date

  init(_ instant: Date) { self.instant = instant }
  func now() -> Date {
    lock.lock(); defer { lock.unlock() }
    return instant
  }
  func advance(by interval: TimeInterval) {
    lock.lock(); defer { lock.unlock() }
    instant.addTimeInterval(interval)
  }
}
