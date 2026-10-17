import Foundation
import MCPServerKit
import Testing
import VinylFeverCore

struct LibraryMCPServerTests {
  @Test("tool list carries the seven tools and read-only annotations")
  func toolsList() async throws {
    let server = LibraryMCPServer.make(snapshotURL: temporaryDirectory().appending(path: "missing.json"), inboxRoot: temporaryDirectory())
    let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
    let root = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    let result = try #require(root["result"] as? [String: Any])
    let tools = try #require(result["tools"] as? [[String: Any]])
    #expect(Set(tools.compactMap { $0["name"] as? String }) == Set([
      "library_overview", "top_artists", "top_tracks", "search_tracks", "artist_profile", "check_tracks", "stage_playlist",
    ]))
    for tool in tools where (tool["name"] as? String) != "stage_playlist" {
      let annotations = try #require(tool["annotations"] as? [String: Any])
      #expect(annotations["readOnlyHint"] as? Bool == true)
    }
    let staged = try #require(tools.first { ($0["name"] as? String) == "stage_playlist" })
    #expect((staged["annotations"] as? [String: Any])?["readOnlyHint"] == nil)
  }

  @Test("reads fail loudly when no snapshot exists")
  func noSnapshot() async throws {
    let server = LibraryMCPServer.make(snapshotURL: temporaryDirectory().appending(path: "missing.json"), inboxRoot: temporaryDirectory())
    let response = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"library_overview","arguments":{}}}"#))
    #expect(response.contains("Open Vinyl Fever to build the library snapshot."))
    #expect(response.contains("\"isError\":true"))
  }

  @Test("read tools query the fixture snapshot and stage_playlist writes the pinned contract")
  func readAndStage() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "library-snapshot.json")
    let inbox = root.appending(path: "PlaylistInbox", directoryHint: .isDirectory)
    let snapshot = LibrarySnapshot(generatedAt: Date(timeIntervalSince1970: 1_700_000_000), tracks: [
      LibraryTrack(persistentID: "1", name: "Starry Eyes", artist: "The Records", album: "The Records", playCount: 43, favorited: true),
    ])
    try LibrarySnapshotCodec.encode(snapshot).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: inbox)

    for request in [
      #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"library_overview","arguments":{}}}"#,
      #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"top_artists","arguments":{}}}"#,
      #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"top_tracks","arguments":{}}}"#,
      #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"search_tracks","arguments":{"artist":"Records"}}}"#,
      #"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"artist_profile","arguments":{"artist":"The Records"}}}"#,
    ] {
      let response = try #require(await server.handle(line: request))
      #expect(response.contains("Starry Eyes") || response.contains("The Records") || response.contains("trackCount"))
      #expect(!response.contains("persistentID"))
    }

    let check = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_tracks","arguments":{"tracks":[{"artist":"The Records","title":"Starry Eyes"}]}}}"#))
    #expect(check.contains("owned"))
    #expect(check.contains("43"))

    let valid = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"stage_playlist","arguments":{"name":"Power Pop","tracks":[{"artist":"The Records","title":"Starry Eyes"}]}}}"#))
    #expect(valid.contains("Staged"))
    let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
    let stagedURL = try #require(files.first)
    let decoded = try PlaylistContract.decode(String(contentsOf: stagedURL, encoding: .utf8))
    #expect(decoded.request == PlaylistRequest(name: "Power Pop", tracks: [TrackRequest(index: 1, artist: "The Records", title: "Starry Eyes")]))

    let invalid = try #require(await server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"stage_playlist","arguments":{"name":"","tracks":[{"artist":"The Records","title":"Starry Eyes"}]}}}"#))
    #expect(invalid.contains("\"isError\":true"))
    #expect(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).count == 1)
  }

  @Test("instructions have a standalone head and carry the Core playlist contract")
  func instructions() {
    #expect(MCPServer.instructionsHeadStandsAlone(LibraryMCPServer.instructions))
    #expect(LibraryMCPServer.instructions.contains(PlaylistContract.projectInstructions))
  }

  private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
