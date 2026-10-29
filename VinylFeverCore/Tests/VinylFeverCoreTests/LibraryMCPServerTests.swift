import Foundation
import MCPServerKit
import Testing
import VinylFeverCore
import VinylFeverListening

struct LibraryMCPServerTests {
  @Test("library overview reports the injected connector stamp without exposing a path")
  func libraryOverviewConnectorStamp() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let stamp = ConnectorBuildStamp(build: "c8fa5db", dirty: false, builtAt: "2026-10-26T13:00:00Z")
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), buildStamp: stamp)

    let response = try #require(await resultJSON(server, id: 65, name: "library_overview", arguments: "{}") as? [String: Any])
    let connector = try #require(response["connector"] as? [String: Any])
    #expect(connector["build"] as? String == "c8fa5db")
    #expect(connector["dirty"] as? Bool == false)
    #expect(connector["builtAt"] as? String == "2026-10-26T13:00:00Z")
    #expect(!String(describing: response).contains("snapshot.json"))
  }

  @Test("a missing app build stamp is reported as unknown")
  func missingConnectorBuildStampIsUnknown() {
    #expect(ConnectorBuildStamp.from(infoDictionary: [:]) == .unknown)
  }

  @Test("library overview uses unknown when no connector stamp is injected")
  func libraryOverviewMissingConnectorStamp() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), buildStamp: .unknown)

    let response = try #require(await resultJSON(server, id: 66, name: "library_overview", arguments: "{}") as? [String: Any])
    let connector = try #require(response["connector"] as? [String: Any])
    #expect(connector["build"] as? String == "unknown")
    #expect(connector["builtAt"] as? String == "unknown")
  }

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
      "list_playlists": ["role", "limit"],
      "playlist_tracks": ["name", "limit"],
      "recent_listening": ["period", "limit"],
      "kept_and_passed": ["weeks"],
      "taste_baselines": [],
      "recommendation_outcomes": ["batches"],
      "record_new_music_picks": ["songs"],
      "taste_notes": ["artist", "title", "playlist", "period", "limit"],
      "record_taste_note": ["note", "artist", "title", "album", "playlist", "kind", "answers", "skipped", "about"],
      "stage_playlist": ["name", "description", "request", "tracks"],
    ]
    #expect(Set(tools.compactMap { $0["name"] as? String }) == Set(expected.keys))
    for tool in tools {
      let name = try #require(tool["name"] as? String)
      let schema = try #require(tool["inputSchema"] as? [String: Any])
      let properties = try #require(schema["properties"] as? [String: Any])
      #expect(Set(properties.keys) == expected[name])
      let annotations = try #require(tool["annotations"] as? [String: Any])
      #expect(annotations["openWorldHint"] as? Bool == false)
      #expect(!((tool["description"] as? String) ?? "").contains("VF Note"))
      if name == "stage_playlist" || name == "record_taste_note" || name == "record_new_music_picks" {
        #expect(annotations["destructiveHint"] as? Bool == false)
        #expect(annotations["readOnlyHint"] == nil)
      } else {
        #expect(annotations["readOnlyHint"] as? Bool == true)
      }
      if name == "library_overview" {
        #expect((tool["description"] as? String)?.contains("connector's build stamp") == true)
      }
    }
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appending(path: "../../../scripts/setup-mac").standardizedFileURL
    let setupScript = try String(contentsOf: repoRoot, encoding: .utf8)
    #expect(!setupScript.contains("VF Note"))
    #expect(enumValues(in: tools, tool: "top_artists", property: "by") == ["plays", "favorites", "recently_added"])
    #expect(enumValues(in: tools, tool: "top_tracks", property: "by") == ["plays", "favorites", "recently_added", "recently_played"])
    #expect(enumValues(in: tools, tool: "recent_listening", property: "period") == ["24h", "7d", "30d", "90d"])
    #expect(enumValues(in: tools, tool: "top_artists", property: "period") == ["all_time", "7d", "30d", "90d"])
    let stage = try #require(tools.first { $0["name"] as? String == "stage_playlist" })
    let stageProperties = try #require((stage["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
    #expect((stageProperties["description"] as? [String: Any])?["description"] as? String
      == "One sentence about the music; it becomes the playlist's description in Apple Music. No library stats, availability notes, or dates. Don't stage the same batch again to fix a year; that marks every song as recommended before.")
  }

  @Test("chat taste notes round-trip verbatim and never write the shortcut file")
  func chatTasteNoteRoundTrip() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"),
      tasteRootURL: tasteRoot, hostName: { "Test Mac" }, now: { instant })
    let original = "The melody opens up in the chorus — keep that lift."
    let recorded = try #require(await resultJSON(server, id: 60, name: "record_taste_note",
      arguments: #"{"note":"The melody opens up in the chorus — keep that lift.","artist":" Artist ","title":"Song","album":"Album"}"#) as? [String: Any])
    #expect(recorded["recorded"] as? Bool == true)
    #expect(recorded["source"] as? String == "chat")
    let recordedID = try #require(recorded["id"] as? String)
    #expect(!FileManager.default.fileExists(atPath: tasteRoot.appending(path: "notes.jsonl").path))
    #expect(FileManager.default.fileExists(atPath: tasteRoot.appending(path: "notes-chat-Test_Mac.jsonl").path))

    let notes = try #require(await resultJSON(server, id: 61, name: "taste_notes",
      arguments: #"{"artist":"Artist","title":"Song"}"#) as? [String: Any])
    let rows = try #require(notes["notes"] as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows.first?["note"] as? String == original)
    #expect(rows.first?["source"] as? String == "chat")
    #expect(rows.first?["artist"] as? String == "Artist")
    #expect(rows.first?["id"] as? String == recordedID)
    #expect(notes["openQuestions"] as? [[String: Any]] != nil)
    #expect(notes["coverage"] != nil)
    #expect(!String(describing: notes).contains("Taste Intelligence"))

    _ = await call(server, id: 62, name: "record_taste_note",
      arguments: #"{"note":"Keep the bright guitar line.","playlist":"Jangle Essentials"}"#)
    let playlistNotes = try #require(await resultJSON(server, id: 63, name: "taste_notes",
      arguments: #"{"playlist":"Jangle Essentials"}"#) as? [String: Any])
    let playlistRows = try #require(playlistNotes["notes"] as? [[String: Any]])
    #expect(playlistRows.count == 1)
    #expect(playlistRows.first?["playlist"] as? String == "Jangle Essentials")
    #expect(playlistRows.first?["note"] as? String == "Keep the bright guitar line.")
    #expect(playlistRows.first?["candidates"] == nil)
    #expect(!FileManager.default.fileExists(atPath: tasteRoot.appending(path: "notes.jsonl").path))
  }

  @Test("questions can be answered verbatim and unknown question ids are refused")
  func tasteQuestionFlow() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let snapshotURL = root.appending(path: "snapshot.json")
    let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, listeningRootURL: root.appending(path: "Listening"), tasteRootURL: tasteRoot, now: { clock.now() })
    let questionResult = try #require(await resultJSON(server, id: 1, name: "record_taste_note", arguments: #"{"note":"Was it vocals or tempo?","kind":"question","about":{"songs":[{"artist":"A","title":"B"}],"playlists":[]}}"#) as? [String: Any])
    let questionID = try #require(questionResult["id"] as? String)
    let noteResult = try #require(await resultJSON(server, id: 22, name: "record_taste_note",
      arguments: #"{"note":"A known song note.","artist":"A","title":"B"}"#) as? [String: Any])
    let noteID = try #require(noteResult["id"] as? String)
    let nonQuestionAnswer = await call(server, id: 23, name: "record_taste_note",
      arguments: "{\"note\":\"That note is not a question.\",\"answers\":\"\(noteID)\"}")
    #expect(nonQuestionAnswer?.contains("known question") == true)
    let open = try #require(await resultJSON(server, id: 2, name: "taste_notes", arguments: "{}") as? [String: Any])
    var newerQuestionIDs: [String] = []
    for id in 10...12 {
      clock.advance(by: 10)
      let result = try #require(await resultJSON(server, id: id, name: "record_taste_note",
        arguments: #"{"note":"Another contrast?","kind":"question","about":{"playlists":["Selections"]}}"#) as? [String: Any])
      newerQuestionIDs.append(try #require(result["id"] as? String))
    }
    let openIDs = try #require((open["openQuestions"] as? [[String: Any]])?.compactMap { $0["id"] as? String })
    #expect(openIDs.count == 1)
    let superseded = try #require(await resultJSON(server, id: 13, name: "taste_notes", arguments: "{}") as? [String: Any])
    #expect((superseded["openQuestions"] as? [[String: Any]])?.count == 3)
    #expect(!((superseded["openQuestions"] as? [[String: Any]] ?? []).contains { $0["id"] as? String == questionID }))
    let rejected = await call(server, id: 14, name: "record_taste_note", arguments: #"{"note":"The vocals, verbatim.","answers":"unknown"}"#)
    #expect(rejected?.contains("known question") == true)
    let emptyQuestion = await call(server, id: 15, name: "record_taste_note", arguments: #"{"note":"  ","kind":"question","about":{"playlists":["Selections"]}}"#)
    #expect(emptyQuestion?.contains("note must not be empty") == true)
    let invalidAbout = await call(server, id: 16, name: "record_taste_note", arguments: #"{"note":"Which?","kind":"question","about":{"songs":[{"artist":" ","title":""}]}}"#)
    #expect(invalidAbout?.contains("about entries") == true)
    let songQuestion = await call(server, id: 17, name: "record_taste_note", arguments: #"{"note":"Which?","kind":"question","artist":"Artist","title":"Song","about":{"songs":[{"artist":"Artist","title":"Song"}]}}"#)
    #expect(songQuestion?.contains("question context belongs in about") == true)
    let notAnAnswer = await call(server, id: 18, name: "record_taste_note", arguments: #"{"note":"The vocals.","kind":"answer"}"#)
    #expect(notAnAnswer?.contains("answers must name a known question") == true)
    let answered = try #require(await resultJSON(server, id: 19, name: "record_taste_note", arguments: "{\"note\":\"The vocals, verbatim.\",\"answers\":\"\(questionID)\"}") as? [String: Any])
    #expect(answered["recorded"] as? Bool == true)
    let skipped = try #require(await resultJSON(server, id: 20, name: "record_taste_note", arguments: "{\"note\":\"not now\",\"answers\":\"\(newerQuestionIDs[0])\",\"skipped\":true}") as? [String: Any])
    #expect(skipped["recorded"] as? Bool == true)
    let closed = try #require(await resultJSON(server, id: 21, name: "taste_notes", arguments: "{}") as? [String: Any])
    #expect((closed["openQuestions"] as? [[String: Any]])?.count == 2)
    let rows = try #require(closed["notes"] as? [[String: Any]])
    #expect(rows.first(where: { $0["kind"] as? String == "answer" })?["note"] as? String == "The vocals, verbatim.")
  }

  @Test("question lines are never song-note evidence in check_tracks")
  func questionDoesNotCreateSongEvidence() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let question = TasteNote(notedAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Falsetto or groove?",
      source: "chat", title: "Song", artist: "Artist", kind: "question", id: "question-id")
    try TasteNotesCodec.appendChatNote(question, host: "Fixture", folder: tasteRoot)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, listeningRootURL: root.appending(path: "Listening"), tasteRootURL: tasteRoot)
    let response = try #require(await resultJSON(server, id: 1, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Artist","title":"Song"}]}"#) as? [String: Any])
    let tracks = try #require(response["tracks"] as? [[String: Any]])
    let notes = try #require(tracks.first?["notes"] as? [String: Any])
    #expect(notes["count"] as? Int == 0)
  }

  @Test("taste_notes returns questions with their answers in the golden shape")
  func tasteNotesQuestionAnswerGolden() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let snapshotURL = root.appending(path: "snapshot.json")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let open = TasteNote(notedAt: now.addingTimeInterval(-30), note: "Vocal or groove?", source: "chat",
      kind: "question", id: "open-id", about: .init(songs: [.init(artist: "Artist", title: "Song")]))
    let answered = TasteNote(notedAt: now.addingTimeInterval(-3_600), note: "Falsetto or rhythm?", source: "chat",
      kind: "question", id: "answered-id", about: .init(playlists: ["Selections"]))
    let answer = TasteNote(notedAt: now.addingTimeInterval(-10), note: "The falsetto.", source: "chat",
      kind: "answer", id: "answer-id", answers: "answered-id")
    for note in [open, answered, answer] { try TasteNotesCodec.appendChatNote(note, host: "Fixture", folder: tasteRoot) }
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, listeningRootURL: root.appending(path: "Listening"), tasteRootURL: tasteRoot, now: { now })
    let result = try #require(await resultJSON(server, id: 1, name: "taste_notes", arguments: "{}"))
    let json = try canonicalJSON(result)
    #expect(json == #"{"coverage":{"filesRead":1,"listeningStatus":"not_set_up","skippedLines":0},"notes":[{"answers":"answered-id","id":"answer-id","kind":"answer","note":"The falsetto.","notedAt":"2027-01-15T07:59:50Z","source":"chat"},{"about":{"playlists":[],"songs":[{"artist":"Artist","title":"Song"}]},"id":"open-id","kind":"question","note":"Vocal or groove?","notedAt":"2027-01-15T07:59:30Z","source":"chat"},{"about":{"playlists":["Selections"],"songs":[]},"answer":{"note":"The falsetto.","notedAt":"2027-01-15T07:59:50Z","skipped":false},"id":"answered-id","kind":"question","note":"Falsetto or rhythm?","notedAt":"2027-01-15T07:00:00Z","source":"chat"}],"openQuestions":[{"about":{"playlists":[],"songs":[{"artist":"Artist","title":"Song"}]},"age":30,"id":"open-id","note":"Vocal or groove?"}]}"#)
    #expect(!json.contains(root.path))
    #expect(!json.contains("persistentID"))
    #expect(!json.contains("Taste Intelligence"))
  }

  @Test("check_tracks succeeds when taste notes cannot be read")
  func checkTracksToleratesTasteNoteReadFailure() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(s0Fixture()).write(to: snapshotURL)
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: tasteRoot.appending(path: "notes x.jsonl", directoryHint: .isDirectory), withIntermediateDirectories: true)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), tasteRootURL: tasteRoot)

    let result = try #require(await resultJSON(server, id: 64, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Version Artist","title":"Version Song"}]}"#) as? [String: Any])
    let rows = try #require(result["tracks"] as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows.first?["notes"] == nil)
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

  @Test("playlist tools return ordered tracks and omit persistent IDs")
  func playlistTools() async throws {
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = LibrarySnapshot(generatedAt: generatedAt, tracks: [
      LibraryTrack(persistentID: "private-id", name: "First Song", artist: "The Records", album: "Album"),
    ], playlists: [
      LibraryPlaylist(persistentID: "playlist-private-id", name: "2025: Jon's Selections", kind: .user, members: ["private-id", "outside-id"]),
    ], outsideTracks: [
      "outside-id": LibraryOutsideTrack(name: "Second Song", artist: "The Records", album: "Other Album"),
    ])
    let tasteRoot = temporaryDirectory().appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let recordedAt = generatedAt.addingTimeInterval(-60)
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    try RecommendationLedgerCodec.append(RecommendationBatch(recordedAt: recordedAt, host: "Fixture",
      playlist: "Earlier", tracks: [RecommendationTrack(artist: "The Records", title: "Second Song",
        familiar: false, reasons: [], artistKnown: false)]), host: "Fixture", folder: recommendationFolder)
    let (server, snapshotURL) = try makeServer(snapshot: snapshot, tasteRootURL: tasteRoot)
    let initialModified = try #require(FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.modificationDate] as? Date)
    let stableModified = Date(timeIntervalSince1970: floor(initialModified.timeIntervalSince1970))
    try FileManager.default.setAttributes([.modificationDate: stableModified], ofItemAtPath: snapshotURL.path)
    let listed = try #require(await call(server, id: 1, name: "list_playlists", arguments: #"{"limit":10}"#))
    #expect(listed.contains("2025: Jon's Selections"))
    #expect(listed.contains("\"unlabeledCount\":1"))
    #expect(listed.contains("\"matchingCount\":1"))
    let tracks = try #require(await call(server, id: 2, name: "playlist_tracks", arguments: #"{"name":"2025: Jon's Selections"}"#))
    #expect(tracks.contains("First Song"))
    #expect(tracks.contains("Second Song"))
    #expect(tracks.contains("\"position\":2"))
    #expect(tracks.contains("\"recommended\":{\"count\":1,\"latestOutcome\":\"pending\",\"latestRecordedAt\":\"2023-11-14T22:12:20Z\"}"))
    #expect(!tracks.contains("private-id"))
    let checked = try #require(await call(server, id: 3, name: "check_tracks", arguments: #"{"tracks":[{"artist":"The Records","title":"First Song"}]}"#))
    #expect(checked.contains("\"playlists\":{}"))
    #expect(checked.contains("\"sharedAccountEra\":false"))
    #expect(checked.contains("\"unlabeledPlaylistCount\":1"))
    #expect(checked.contains("\"listening\":\"not_set_up\""))
    #expect(!checked.contains("\"heardDays\""))
    #expect(!checked.contains("private-id"))
    let modifiedAt = try #require(FileManager.default.attributesOfItem(atPath: snapshotURL.path)[.modificationDate] as? Date)
    try Data("invalid snapshot".utf8).write(to: snapshotURL)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: snapshotURL.path)
    let cachedTracks = await call(server, id: 4, name: "playlist_tracks", arguments: #"{"name":"2025: Jon's Selections"}"#)
    #expect(cachedTracks?.contains("Second Song") == true, "Unexpected response: \(cachedTracks ?? "nil")")
    let cachedChecks = await call(server, id: 5, name: "check_tracks", arguments: #"{"tracks":[{"artist":"The Records","title":"First Song"}]}"#)
    #expect(cachedChecks?.contains("First Song") == true, "Unexpected response: \(cachedChecks ?? "nil")")
  }

  @Test("list_playlists defaults to 200 and reports the pre-limit matching count")
  func playlistListDefaultLimit() async throws {
    let playlists = (0..<60).map { index in
      LibraryPlaylist(persistentID: "id-\(index)", name: "Playlist \(index)", kind: .user, members: [])
    }
    let (server, _) = try makeServer(snapshot: LibrarySnapshot(generatedAt: .now, tracks: [], playlists: playlists))
    let all = try #require(await resultJSON(server, id: 1, name: "list_playlists", arguments: "{}") as? [String: Any])
    #expect((all["playlists"] as? [[String: Any]])?.count == 60)
    #expect(all["matchingCount"] as? Int == 60)
    let limited = try #require(await resultJSON(server, id: 2, name: "list_playlists", arguments: #"{"limit":10}"#) as? [String: Any])
    #expect((limited["playlists"] as? [[String: Any]])?.count == 10)
    #expect(limited["matchingCount"] as? Int == 60)
  }

  @Test("list_playlists carries only unresolved open questions")
  func playlistListOpenQuestions() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let open = TasteNote(notedAt: now.addingTimeInterval(-30), note: "Bright or dreamy?", source: "chat",
      kind: "question", id: "open-id", about: .init(songs: [.init(artist: "Artist", title: "Song")]))
    let answered = TasteNote(notedAt: now.addingTimeInterval(-60), note: "Vocal or groove?", source: "chat",
      kind: "question", id: "answered-id", about: .init(playlists: ["Selections"]))
    let answer = TasteNote(notedAt: now.addingTimeInterval(-10), note: "The vocals.", source: "chat",
      kind: "answer", id: "answer-id", answers: "answered-id")
    let skipped = TasteNote(notedAt: now.addingTimeInterval(-50), note: "Skip this", source: "chat",
      kind: "question", id: "skipped-id", about: .init(playlists: ["Keepers"]))
    let skip = TasteNote(notedAt: now.addingTimeInterval(-5), note: "not now", source: "chat",
      kind: "answer", id: "skip-id", answers: "skipped-id", skipped: true)
    for note in [open, answered, answer, skipped, skip] {
      try TasteNotesCodec.appendChatNote(note, host: "Fixture", folder: tasteRoot)
    }
    let (server, _) = try makeServer(snapshot: s0Fixture(generatedAt: now), tasteRootURL: tasteRoot, now: { now })
    let listed = try #require(await resultJSON(server, id: 1, name: "list_playlists", arguments: "{}"))
    let json = try canonicalJSON(listed)
    #expect(json == #"{"matchingCount":0,"openQuestions":[{"about":{"playlists":[],"songs":[{"artist":"Artist","title":"Song"}]},"age":30,"id":"open-id","note":"Bright or dreamy?"}],"playlists":[],"snapshotGeneratedAt":"2023-11-14T22:13:20Z","unlabeledCount":0}"#)
    #expect(!json.contains("answered-id"))
    #expect(!json.contains("skipped-id"))
  }

  @Test("list_playlists omits openQuestions when absent or unreadable")
  func playlistListOmitsUnavailableOpenQuestions() async throws {
    let root = temporaryDirectory()
    let snapshot = s0Fixture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let emptyTasteRoot = root.appending(path: "Empty Taste", directoryHint: .isDirectory)
    let (emptyServer, _) = try makeServer(snapshot: snapshot, tasteRootURL: emptyTasteRoot, now: { now })
    let empty = try #require(await resultJSON(emptyServer, id: 1, name: "list_playlists", arguments: "{}"))
    let emptyJSON = try canonicalJSON(empty)
    #expect(emptyJSON == #"{"matchingCount":0,"playlists":[],"snapshotGeneratedAt":"2023-11-14T22:13:20Z","unlabeledCount":0}"#)

    let unreadableTasteRoot = root.appending(path: "Unreadable Taste", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: unreadableTasteRoot.appending(path: "notes unreadable.jsonl", directoryHint: .isDirectory), withIntermediateDirectories: true)
    let (unreadableServer, _) = try makeServer(snapshot: snapshot, tasteRootURL: unreadableTasteRoot)
    let unreadable = try #require(await resultJSON(unreadableServer, id: 2, name: "list_playlists", arguments: "{}"))
    let unreadableJSON = try canonicalJSON(unreadable)
    #expect(unreadableJSON == emptyJSON)

    let resolvedTasteRoot = root.appending(path: "Resolved Taste", directoryHint: .isDirectory)
    let answeredQuestion = TasteNote(notedAt: now.addingTimeInterval(-60), note: "Vocal or groove?", source: "chat",
      kind: "question", id: "answered-id", about: .init(playlists: ["Selections"]))
    let answer = TasteNote(notedAt: now.addingTimeInterval(-30), note: "The vocals.", source: "chat",
      kind: "answer", id: "answer-id", answers: "answered-id")
    let skippedQuestion = TasteNote(notedAt: now.addingTimeInterval(-50), note: "Bright or dreamy?", source: "chat",
      kind: "question", id: "skipped-id", about: .init(playlists: ["Keepers"]))
    let skip = TasteNote(notedAt: now.addingTimeInterval(-10), note: "not now", source: "chat",
      kind: "answer", id: "skip-id", answers: "skipped-id", skipped: true)
    for note in [answeredQuestion, answer, skippedQuestion, skip] {
      try TasteNotesCodec.appendChatNote(note, host: "Fixture", folder: resolvedTasteRoot)
    }
    let (resolvedServer, _) = try makeServer(snapshot: snapshot, tasteRootURL: resolvedTasteRoot, now: { now })
    let resolved = try #require(await resultJSON(resolvedServer, id: 3, name: "list_playlists", arguments: "{}"))
    #expect(try canonicalJSON(resolved) == emptyJSON)
  }

  @Test("heard index matches duet credits and retains local play days")
  func heardIndexCredits() async throws {
    let root = temporaryDirectory()
    let listening = root.appending(path: "Listening", directoryHint: .isDirectory)
    let stream = listening.appending(path: "fetches/fixture/2026-10.jsonl")
    try FileManager.default.createDirectory(at: stream.deletingLastPathComponent(), withIntermediateDirectories: true)
    let poller = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    func instant(_ day: Int) -> Date { Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: day, hour: 12))! }
    let duet = ListeningItem(kind: .song, id: "heard-song", title: "Song", artist: "A & B")
    let fetches = [
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant(20), outcome: .baseline, pagesRead: 1),
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant(20) + 60, outcome: .plays, newCount: 1, pagesRead: 1, items: [duet]),
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant(21), outcome: .plays, newCount: 1, pagesRead: 1, items: [duet]),
    ]
    let bytes = try fetches.map { try ListeningLogCodec.encode($0) + Data([10]) }.reduce(into: Data()) { $0.append($1) }
    try bytes.write(to: stream)
    let decodedLog = try ListeningLog(jsonlStreams: [bytes], now: instant(22))
    #expect(decodedLog.plays.count == 2)
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [
      LibraryTrack(persistentID: "private", name: "Song", artist: "A & B"),
      LibraryTrack(persistentID: "artist-a", name: "Another Song", artist: "A"),
      LibraryTrack(persistentID: "artist-b", name: "One More Song", artist: "B"),
    ])
    let (server, _) = try makeServer(snapshot: snapshot, listeningRootURL: listening)
    let result = try #require(await resultJSON(server, id: 1, name: "check_tracks", arguments: #"{"tracks":[{"artist":"A","title":"Song"}]}"#) as? [String: Any])
    let row = try #require((result["tracks"] as? [[String: Any]])?.first)
    #expect(row["heardDays"] as? Int == 2)
    #expect(row["heardLast"] != nil)
  }

  @Test("check_tracks reports a collaborator play for a credited artist")
  func checkTracksCollaboratorCredits() async throws {
    let root = temporaryDirectory()
    let listening = root.appending(path: "Listening", directoryHint: .isDirectory)
    let stream = listening.appending(path: "fetches/fixture/2026-10.jsonl")
    try FileManager.default.createDirectory(at: stream.deletingLastPathComponent(), withIntermediateDirectories: true)
    let instant = Date(timeIntervalSince1970: 1_798_200_000)
    let poller = UUID()
    let item = ListeningItem(kind: .song, id: "prologue", title: "Prologue (Eulogy Of A Man Turned Mule)",
      artist: "Emmylou Harris, Noah Cyrus, Allison Russell & Orville Peck")
    let fetches = [
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant, outcome: .baseline, pagesRead: 1),
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant.addingTimeInterval(60),
        outcome: .plays, newCount: 1, pagesRead: 1, items: [item]),
    ]
    let bytes = try fetches.map { try ListeningLogCodec.encode($0) + Data([10]) }
      .reduce(into: Data()) { $0.append($1) }
    try bytes.write(to: stream)
    let snapshot = LibrarySnapshot(generatedAt: instant.addingTimeInterval(120), tracks: [
      LibraryTrack(persistentID: "orville", name: "Another Song", artist: "Orville Peck"),
      LibraryTrack(persistentID: "emmylou", name: "Another Song", artist: "Emmylou Harris"),
    ])
    let (server, _) = try makeServer(snapshot: snapshot, listeningRootURL: listening)
    let result = try #require(await resultJSON(server, id: 1, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Orville Peck","title":"Prologue (Eulogy Of A Man Turned Mule)"}]}"#) as? [String: Any])
    let row = try #require((result["tracks"] as? [[String: Any]])?.first)
    #expect(row["heardDays"] as? Int == 1)
  }

  @Test("recommendation evidence cache notices batches appended by another host")
  func recommendationEvidenceCacheRefreshesAcrossHosts() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let track = RecommendationTrack(artist: "New Artist", title: "New Song", familiar: false,
      reasons: [], artistKnown: false)
    try RecommendationLedgerCodec.append(RecommendationBatch(recordedAt: instant, host: "Other",
      tracks: [track]), host: "Other", folder: recommendationFolder)
    let (server, _) = try makeServer(snapshot: LibrarySnapshot(generatedAt: instant, tracks: []),
      tasteRootURL: tasteRoot)
    let arguments = #"{"tracks":[{"artist":"New Artist","title":"New Song"}]}"#
    let first = try #require(await resultJSON(server, id: 1, name: "check_tracks", arguments: arguments) as? [String: Any])
    let firstRow = try #require((first["tracks"] as? [[String: Any]])?.first)
    let firstEvidence = try #require(firstRow["recommended"] as? [String: Any])
    #expect(firstEvidence["count"] as? Int == 1)

    try RecommendationLedgerCodec.append(RecommendationBatch(recordedAt: instant.addingTimeInterval(60),
      host: "Another", tracks: [track]), host: "Another", folder: recommendationFolder)
    let second = try #require(await resultJSON(server, id: 2, name: "check_tracks", arguments: arguments) as? [String: Any])
    let secondRow = try #require((second["tracks"] as? [[String: Any]])?.first)
    let secondEvidence = try #require(secondRow["recommended"] as? [String: Any])
    #expect(secondEvidence["count"] as? Int == 2)
  }

  @Test("check_tracks latest outcome refreshes when the ledger changes")
  func checkTracksLatestOutcomeRefreshesWhenLedgerChanges() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let oldDate = now.addingTimeInterval(-15 * 86_400)
    try RecommendationLedgerCodec.append(RecommendationBatch(recordedAt: oldDate, host: "Other", tracks: [
      RecommendationTrack(artist: "Cached Artist", title: "Cached Song", familiar: false, reasons: [], artistKnown: false),
    ], coverage: RecommendationCoverage(listening: true, notes: true, snapshotAt: now)), host: "Other", folder: recommendationFolder)
    let clock = TestClock(now)
    let server = LibraryMCPServer.make(snapshotURL: root.appending(path: "snapshot.json"),
      inboxRoot: root.appending(path: "inbox"), listeningRootURL: root.appending(path: "Listening"),
      tasteRootURL: tasteRoot, now: { clock.now() })
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: now.addingTimeInterval(20 * 86_400), tracks: [])).write(to: root.appending(path: "snapshot.json"))

    let first = try #require(await resultJSON(server, id: 1, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Cached Artist","title":"Cached Song"}]}"#) as? [String: Any])
    let firstRow = try #require((first["tracks"] as? [[String: Any]])?.first)
    let firstEvidence = try #require(firstRow["recommended"] as? [String: Any])
    #expect(firstEvidence["latestOutcome"] as? String == "unheard")

    let staged = try #require(await resultJSON(server, id: 2, name: "stage_playlist",
      arguments: #"{"name":"New batch","tracks":[{"artist":"Cached Artist","title":"Cached Song","year":2020},{"artist":"Fresh Artist","title":"Fresh Song","year":2024}]}"#) as? [String: Any])
    #expect(staged["ledgerRecorded"] as? Bool == true)
    let second = try #require(await resultJSON(server, id: 3, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Fresh Artist","title":"Fresh Song"}]}"#) as? [String: Any])
    let secondRow = try #require((second["tracks"] as? [[String: Any]])?.first)
    let secondEvidence = try #require(secondRow["recommended"] as? [String: Any])
    #expect(secondEvidence["count"] as? Int == 1)
    #expect(secondEvidence["latestOutcome"] as? String == "pending")
    #expect(secondEvidence["latestRecordedAt"] as? String == "2027-01-15T08:00:00Z")
  }

  @Test("latest outcome ignores New Music pick batches")
  func latestOutcomeIgnoresNewMusicPicks() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = TestClock(now)
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: now, tracks: [])).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"),
      listeningRootURL: root.appending(path: "Listening"), tasteRootURL: tasteRoot, now: { clock.now() })
    let staged = try #require(await resultJSON(server, id: 1, name: "stage_playlist",
      arguments: #"{"name":"Chat batch","tracks":[{"artist":"Shared Artist","title":"Shared Song","year":2026}]}"#) as? [String: Any])
    #expect(staged["ledgerRecorded"] as? Bool == true)
    let first = try #require(await resultJSON(server, id: 2, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Shared Artist","title":"Shared Song"}]}"#) as? [String: Any])
    let firstRow = try #require((first["tracks"] as? [[String: Any]])?.first)
    #expect((firstRow["recommended"] as? [String: Any])?["latestOutcome"] as? String == "pending")

    let exposureFolder = tasteRoot.appending(path: "exposure", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: exposureFolder, withIntermediateDirectories: true)
    let weekDate = now.addingTimeInterval(10)
    let week = NewMusicWeek(lastModifiedDate: weekDate, fetchedAt: weekDate, host: "Mac", tracks: [
      NewMusicTrack(catalogID: "catalog", title: "Shared Song", artist: "Shared Artist", releaseDate: "2026-01-01"),
    ])
    try NewMusicExposureCodec.encode(week).write(to: exposureFolder.appending(path: "week.jsonl"))
    clock.advance(by: 20)
    let pick = try #require(await resultJSON(server, id: 3, name: "record_new_music_picks",
      arguments: #"{"songs":[{"artist":"Shared Artist","title":"Shared Song"}]}"#) as? [String: Any])
    #expect(pick["recorded"] as? Bool == true)

    let checked = try #require(await resultJSON(server, id: 4, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Shared Artist","title":"Shared Song"}]}"#) as? [String: Any])
    let row = try #require((checked["tracks"] as? [[String: Any]])?.first)
    let evidence = try #require(row["recommended"] as? [String: Any])
    #expect(evidence["count"] as? Int == 1)
    #expect(evidence["latestOutcome"] as? String == "pending")
  }

  @Test("check_tracks latest outcome refreshes when a newer snapshot ends the window")
  func checkTracksLatestOutcomeRefreshesWhenSnapshotEndsWindow() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let clock = TestClock(now)
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: now, tracks: [])).write(to: snapshotURL)
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"),
      listeningRootURL: root.appending(path: "Listening"), tasteRootURL: tasteRoot, now: { clock.now() })
    let staged = try #require(await resultJSON(server, id: 1, name: "stage_playlist",
      arguments: #"{"name":"Window batch","tracks":[{"artist":"Window Artist","title":"Window Song","year":2026}]}"#) as? [String: Any])
    #expect(staged["ledgerRecorded"] as? Bool == true)
    let arguments = #"{"tracks":[{"artist":"Window Artist","title":"Window Song"}]}"#
    let first = try #require(await resultJSON(server, id: 2, name: "check_tracks", arguments: arguments) as? [String: Any])
    let firstRow = try #require((first["tracks"] as? [[String: Any]])?.first)
    #expect((firstRow["recommended"] as? [String: Any])?["latestOutcome"] as? String == "pending")

    let windowEnd = now.addingTimeInterval(15 * 86_400)
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: windowEnd, tracks: [])).write(to: snapshotURL)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(60)], ofItemAtPath: snapshotURL.path)
    clock.advance(by: 15 * 86_400)
    let second = try #require(await resultJSON(server, id: 3, name: "check_tracks", arguments: arguments) as? [String: Any])
    let secondRow = try #require((second["tracks"] as? [[String: Any]])?.first)
    #expect((secondRow["recommended"] as? [String: Any])?["latestOutcome"] as? String == "unheard")
  }

  @Test("recommendation lookups stay fast at library and ledger scale", .enabled(if: ProcessInfo.processInfo.environment["VF_PERF_TESTS"] == "1"))
  func recommendationLookupsPerformance() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let tracks = (0..<87_000).map { number in
      LibraryTrack(persistentID: "track-\(number)", name: "Track \(number)", artist: "Artist \(number % 8_000)")
    }
    let playlist = LibraryPlaylist(persistentID: "playlist", name: "Performance", kind: .user,
      members: (0..<200).map { "track-\($0)" })
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: tracks, playlists: [playlist])
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: recommendationFolder, withIntermediateDirectories: true)
    var ledger = Data()
    for batchNumber in 0..<500 {
      let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(batchNumber)),
        host: "Fixture", tracks: (0..<15).map { songNumber in
          RecommendationTrack(artist: "Ledger Artist \((batchNumber * 15 + songNumber) % 1_000)",
            title: "Ledger Song \(batchNumber * 15 + songNumber)", familiar: false, reasons: [], artistKnown: false)
        })
      ledger.append(try RecommendationLedgerCodec.encode(batch))
    }
    try ledger.write(to: recommendationFolder.appending(path: "fixture.jsonl"))
    let (server, _) = try makeServer(snapshot: snapshot, tasteRootURL: tasteRoot)
    let rows = try #require(await resultJSON(server, id: 1, name: "playlist_tracks",
      arguments: #"{"name":"Performance","limit":200}"#))
    #expect((rows as? [String: Any])?["tracks"] as? [[String: Any]] != nil)
    let playlistStart = ContinuousClock.now
    let timedRows = try #require(await resultJSON(server, id: 2, name: "playlist_tracks",
      arguments: #"{"name":"Performance","limit":200}"#))
    let playlistElapsed = playlistStart.duration(to: .now)
    let timedTracks = (timedRows as? [String: Any])?["tracks"] as? [[String: Any]]
    #expect(timedTracks?.count == 200)
    #expect(playlistElapsed < .seconds(1))

    // Warm the shared indexes and then measure the 15-track familiarity/stage pass.
    let stageTracks = (0..<15).map { #"{"artist":"Artist \#($0)","title":"New Track \#($0)"}"# }.joined(separator: ",")
    let stageArguments = #"{"name":"Performance Stage","tracks":[\#(stageTracks)]}"#
    let stageStart = ContinuousClock.now
    let staged = try #require(await resultJSON(server, id: 3, name: "stage_playlist", arguments: stageArguments) as? [String: Any])
    let stageElapsed = stageStart.duration(to: .now)
    #expect(staged["staged"] as? Bool == true)
    #expect(stageElapsed < .milliseconds(500))
  }

  @Test("playlist tools match their full JSON contract")
  func playlistToolsGolden() async throws {
    let root = temporaryDirectory()
    let listening = root.appending(path: "Listening", directoryHint: .isDirectory)
    let stream = listening.appending(path: "fetches/fixture/2026-10.jsonl")
    try FileManager.default.createDirectory(at: stream.deletingLastPathComponent(), withIntermediateDirectories: true)
    func instant(_ day: Int) -> Date { Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 10, day: day, hour: 12))! }
    let poller = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let item = ListeningItem(kind: .song, id: "logged-song", title: "Song", artist: "A & B")
    let log = [
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant(20), outcome: .baseline, pagesRead: 1),
      ListeningFetch(poller: poller, host: "Mac", fetchedAt: instant(20) + 60, outcome: .plays, newCount: 1, pagesRead: 1, items: [item]),
    ]
    try log.map { try ListeningLogCodec.encode($0) + Data([10]) }.reduce(into: Data()) { $0.append($1) }.write(to: stream)
    let playlists = [
      LibraryPlaylist(persistentID: "id-keepers", name: "Selections 2025", folder: "aJon Selections", kind: .user, members: ["song-id", "song-id", "outside-id"]),
      LibraryPlaylist(persistentID: "id-replay-old", name: "Replay 2017", kind: .subscription, members: ["song-id"]),
      LibraryPlaylist(persistentID: "id-replay-new", name: "Replay 2025", kind: .subscription, members: ["song-id"]),
      LibraryPlaylist(persistentID: "id-followed", name: "Followed Queue", kind: .user, members: ["song-id"]),
      LibraryPlaylist(persistentID: "id-ignore", name: "Ignored Set", kind: .user, members: ["song-id"]),
      LibraryPlaylist(persistentID: "id-unlabeled", name: "Unlabeled Set", kind: .user, members: ["song-id"]),
    ]
    let snapshot = LibrarySnapshot(generatedAt: instant(23), tracks: [
      LibraryTrack(persistentID: "song-id", name: "Song", artist: "A & B", album: "Library Album", year: 2020, playCount: 3, favorited: true),
      LibraryTrack(persistentID: "artist-a", name: "Other A", artist: "A"),
      LibraryTrack(persistentID: "artist-b", name: "Other B", artist: "B"),
    ], playlists: playlists, outsideTracks: [
      "outside-id": LibraryOutsideTrack(name: "Outside Song", artist: "B", album: "Outside Album", year: 2021, durationSeconds: 180),
    ])
    let roles = PlaylistRoles(updatedAt: instant(23), playlists: [
      PlaylistRoleEntry(persistentID: "id-keepers", name: "Selections 2025", role: .keepers),
      PlaylistRoleEntry(persistentID: "id-replay-old", name: "Replay 2017", role: .replay),
      PlaylistRoleEntry(persistentID: "id-replay-new", name: "Replay 2025", role: .replay),
      PlaylistRoleEntry(persistentID: "id-followed", name: "Followed Queue", role: .followed),
      PlaylistRoleEntry(persistentID: "id-ignore", name: "Ignored Set", role: .ignore),
    ])
    let rolesURL = root.appending(path: "Taste Intelligence/playlist-roles.json")
    try FileManager.default.createDirectory(at: rolesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PlaylistRolesCodec.encode(roles).write(to: rolesURL)
    let (server, _) = try makeServer(snapshot: snapshot, listeningRootURL: listening, tasteRootURL: root.appending(path: "Taste Intelligence"))
    let list = try #require(await resultJSON(server, id: 1, name: "list_playlists", arguments: "{}"))
    let tracks = try #require(await resultJSON(server, id: 2, name: "playlist_tracks", arguments: #"{"name":"Selections 2025"}"#))
    let check = try #require(await resultJSON(server, id: 3, name: "check_tracks", arguments: #"{"tracks":[{"artist":"A","title":"Song"}]}"#))
    #expect(try canonicalJSON(list) == #"{"matchingCount":4,"playlists":[{"folder":"aJon Selections","inLibraryCount":2,"kind":"user","name":"Selections 2025","role":"keepers","songCount":3},{"inLibraryCount":1,"kind":"subscription","name":"Replay 2025","role":"replay","songCount":1},{"inLibraryCount":1,"kind":"user","name":"Followed Queue","role":"followed","songCount":1},{"inLibraryCount":1,"kind":"user","name":"Unlabeled Set","songCount":1}],"snapshotGeneratedAt":"2026-10-23T12:00:00Z","unlabeledCount":1}"#)
    #expect(try canonicalJSON(tracks) == #"{"name":"Selections 2025","role":"keepers","snapshotGeneratedAt":"2026-10-23T12:00:00Z","tracks":[{"album":"Library Album","artist":"A & B","evidence":{"availability":["other"],"disliked":false,"favorited":true,"heardDays":1,"heardLast":"2026-10-20T12:01:00Z","notes":{"count":0},"owned":true,"playlistCounts":{"keepers":1,"replay":1},"playlists":{"keepers":["Selections 2025"],"replay":["Replay 2025"]},"plays":3,"sharedAccountEra":false},"position":1,"title":"Song","year":2020},{"album":"Library Album","artist":"A & B","evidence":{"availability":["other"],"disliked":false,"favorited":true,"heardDays":1,"heardLast":"2026-10-20T12:01:00Z","notes":{"count":0},"owned":true,"playlistCounts":{"keepers":1,"replay":1},"playlists":{"keepers":["Selections 2025"],"replay":["Replay 2025"]},"plays":3,"sharedAccountEra":false},"position":2,"title":"Song","year":2020},{"album":"Outside Album","artist":"B","evidence":{"availability":[],"disliked":false,"favorited":false,"heardDays":0,"notes":{"count":0},"owned":false,"playlistCounts":{"keepers":1},"playlists":{"keepers":["Selections 2025"]},"plays":0,"sharedAccountEra":false},"position":3,"title":"Outside Song","year":2021}],"unlabeledPlaylistCount":1}"#)
    #expect(try canonicalJSON(check) == #"{"tracks":[{"artist":"A","availability":["other"],"disliked":false,"favorited":true,"heardDays":1,"heardLast":"2026-10-20T12:01:00Z","notes":{"count":0},"owned":true,"playlistCounts":{"keepers":1,"replay":1},"playlists":{"keepers":["Selections 2025"],"replay":["Replay 2025"]},"plays":3,"sharedAccountEra":false,"title":"Song","uploadedAlbums":[],"versionCount":1}],"unlabeledPlaylistCount":1}"#)
    #expect(!String(describing: [list, tracks, check]).contains("persistentID"))
    #expect(!String(describing: [list, tracks, check]).contains("song-id"))
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
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), tasteRootURL: root.appending(path: "Taste Intelligence"))

    let springsteen = try #require(await resultJSON(
      server, id: 40, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Bruce Springsteen","title":"Thunder Road"}]}"#
    ) as? [String: Any])
    let springsteenRows = try #require(springsteen["tracks"] as? [[String: Any]])
    #expect(springsteenRows.first?["uploadedAlbums"] as? [String] == (1...5).map { "Show \($0)" })
    #expect(!String(describing: springsteen).contains("private-upload-id"))

    let falsePositives = try #require(await resultJSON(
      server, id: 41, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Bruce SpringsteenX","title":"Thunder Road"},{"artist":"Elvis Costello","title":"Alison"}]}"#
    ) as? [String: Any])
    #expect((falsePositives["tracks"] as? [[String: Any]] ?? []).allSatisfy { ($0["uploadedAlbums"] as? [String]) == [] })
  }

  @Test("MCP applies the exported alias map to library checks and artist grouping")
  func artistAliasesFromExport() async throws {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "snapshot.json")
    let tracks = [
      LibraryTrack(persistentID: "cougar", name: "Ain't Even Done With the Night", artist: "John Mellencamp", playCount: 3),
      LibraryTrack(persistentID: "elvis", name: "Song One", artist: "Elvis", playCount: 2),
      LibraryTrack(persistentID: "presley", name: "Song Two", artist: "Elvis Presley", playCount: 4),
    ]
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: .now, tracks: tracks)).write(to: snapshotURL)
    let aliases: [String: String] = [
      "john cougar mellencamp": "john mellencamp",
      "elvis": "elvis presley",
    ]
    try ArtistAliasesCodec.encode(aliases).write(to: root.appending(path: "artist-aliases.json"))
    let server = LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: root.appending(path: "inbox"), tasteRootURL: root.appending(path: "Taste Intelligence"))
    let check = try #require(await resultJSON(
      server, id: 81, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"John Cougar Mellencamp","title":"Ain't Even Done With the Night"}]}"#
    ) as? [String: Any])
    #expect((check["tracks"] as? [[String: Any]])?.first?["owned"] as? Bool == true)
    let artists = try #require(await resultJSON(
      server, id: 82, name: "top_artists", arguments: #"{"period":"all_time"}"#
    ) as? [[String: Any]])
    #expect(artists.filter { ($0["artist"] as? String)?.lowercased().contains("elvis") == true }.count == 1)

    let noFileRoot = temporaryDirectory()
    let noFileSnapshot = noFileRoot.appending(path: "snapshot.json")
    try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: .now, tracks: tracks)).write(to: noFileSnapshot)
    let noFileServer = LibraryMCPServer.make(snapshotURL: noFileSnapshot, inboxRoot: noFileRoot.appending(path: "inbox"), tasteRootURL: noFileRoot.appending(path: "Taste Intelligence"))
    let unchanged = try #require(await resultJSON(
      noFileServer, id: 83, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"John Cougar Mellencamp","title":"Ain't Even Done With the Night"}]}"#
    ) as? [String: Any])
    #expect((unchanged["tracks"] as? [[String: Any]])?.first?["owned"] as? Bool == false)
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

    let checks = try #require(await resultJSON(server, id: 5, name: "check_tracks", arguments: #"{"tracks":[{"artist":"Version Artist","title":"Version Song"}]}"#) as? [String: Any])
    let checkedRows = try #require(checks["tracks"] as? [[String: Any]])
    #expect(checkedRows.first?["plays"] as? Int == 12)
    #expect(checkedRows.first?["versionCount"] as? Int == 2)

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
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let (server, _) = try makeServer(snapshot: s0Fixture(), inbox: inbox, tasteRootURL: tasteRoot)
    let valid = try #require(await call(server, id: 1, name: "stage_playlist", arguments: #"{"name":"Power Pop","tracks":[{"artist":" ","title":"Dropped"},{"artist":"The Records","title":"Starry Eyes","why":"Bright guitars and wiry hooks."}]}"#))
    #expect(valid.contains("\"staged\":true"))
    #expect(valid.contains("\"trackCount\":1"))
    #expect(valid.contains("\"missingYear\":[\"The Records — Starry Eyes\"]"))
    #expect(valid.contains("\"ledgerRecorded\":true"))
    #expect(valid.contains("\"dropped\":[{\"artist\":\"\",\"index\":1,\"title\":\"Dropped\"}]"))
    #expect(valid.contains("Jon reviews and creates it in Vinyl Fever; nothing is in Apple Music yet."))
    #expect(!valid.contains(".vfplaylist"))
    let files = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
    let stagedURL = try #require(files.first)
    let decoded = try PlaylistContract.decode(String(contentsOf: stagedURL, encoding: .utf8))
    #expect(decoded.request == PlaylistRequest(name: "Power Pop", tracks: [TrackRequest(index: 2, artist: "The Records", title: "Starry Eyes")]))
    let recommendationFolder = tasteRoot.appending(path: "recommendations")
    let ledgerFile = try #require(FileManager.default.contentsOfDirectory(at: recommendationFolder, includingPropertiesForKeys: nil).first)
    let ledger = RecommendationLedgerCodec.readFiles([try Data(contentsOf: ledgerFile)])
    #expect(ledger.batches.count == 1)
    #expect(ledger.batches[0].recordedAt != .distantPast)
    #expect(ledger.batches[0].tracks.map(\.title) == ["Starry Eyes"])
    #expect(ledger.batches[0].tracks[0].reasons.isEmpty)
    let checked = try #require(await resultJSON(server, id: 4, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"The Records","title":"Starry Eyes"}]}"#) as? [String: Any])
    let checkedRows = try #require(checked["tracks"] as? [[String: Any]])
    let recommended = try #require(checkedRows.first?["recommended"] as? [String: Any])
    #expect(recommended["count"] as? Int == 1)
    #expect(recommended["latestWhy"] as? String == "Bright guitars and wiry hooks.")
    #expect(recommended["latestOutcome"] as? String == "pending")

    let countBefore = files.count
    let zero = try #require(await call(server, id: 2, name: "stage_playlist", arguments: #"{"name":"Empty","tracks":[]}"#))
    #expect(zero.contains("tracks must contain at least one track"))
    #expect(zero.contains("\"isError\":true"))
    #expect(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).count == countBefore)
    let emptyName = try #require(await call(server, id: 3, name: "stage_playlist", arguments: #"{"name":" ","tracks":[{"artist":"A","title":"B"}]}"#))
    #expect(emptyName.contains("name must not be empty"))
    #expect(emptyName.contains("\"isError\":true"))
    #expect(try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).count == countBefore)

    let blockedRoot = root.appending(path: "Blocked Taste")
    try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: true)
    let recommendationsFile = blockedRoot.appending(path: "recommendations")
    try Data("file prevents the ledger folder".utf8).write(to: recommendationsFile)
    let (ledgerUnavailableServer, _) = try makeServer(snapshot: s0Fixture(), inbox: root.appending(path: "blocked-inbox"),
      tasteRootURL: blockedRoot)
    let stagedWithoutLedger = try #require(await resultJSON(ledgerUnavailableServer, id: 5,
      name: "stage_playlist", arguments: #"{"name":"Still stages","tracks":[{"artist":"A","title":"B"}]}"#) as? [String: Any])
    #expect(stagedWithoutLedger["staged"] as? Bool == true)
    #expect(stagedWithoutLedger["ledgerRecorded"] as? Bool == false)
    #expect(stagedWithoutLedger["ledgerReason"] as? String != nil)
    #expect(!String(describing: stagedWithoutLedger).contains(recommendationsFile.path))
  }

  @Test("unlabeled cited playlist membership verifies a recommendation reference")
  func stageReferenceInUnlabeledPlaylist() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let inbox = root.appending(path: "PlaylistInbox", directoryHint: .isDirectory)
    let snapshot = LibrarySnapshot(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), tracks: [
      LibraryTrack(persistentID: "reference-id", name: "Reference Song", artist: "Reference Artist"),
    ], playlists: [
      LibraryPlaylist(persistentID: "unlabeled-id", name: "Unlabeled Reference Set", kind: .user, members: ["reference-id"]),
    ])
    let (server, _) = try makeServer(snapshot: snapshot, inbox: inbox, tasteRootURL: tasteRoot)
    let staged = try #require(await resultJSON(server, id: 1, name: "stage_playlist", arguments: #"{"name":"Reference Test","request":"Find a companion","tracks":[{"artist":"New Artist","title":"New Song","year":2024,"why":"It shares the bright guitars.","like":[{"artist":"Reference Artist","title":"Reference Song","from":"Unlabeled Reference Set"},{"artist":"Reference Artist","title":"Reference Song","from":"Wrong Playlist"},{"artist":"Missing Artist","title":"Missing Song","from":"Unlabeled Reference Set"}]},{"artist":"Second Artist","title":"Second New Song","like":[{"artist":"Reference Artist","title":"Reference Song"}]}]}"#) as? [String: Any])
    #expect(staged["ledgerRecorded"] as? Bool == true)
    let recommendations = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    let ledgerFile = try #require(FileManager.default.contentsOfDirectory(at: recommendations, includingPropertiesForKeys: nil).first)
    let ledger = RecommendationLedgerCodec.readFiles([try Data(contentsOf: ledgerFile)])
    let reference = try #require(ledger.batches.first?.tracks.first?.like?.first)
    #expect(reference.found == "playlist")
    let references = try #require(ledger.batches.first?.tracks.first?.like)
    #expect(references.map(\.found) == ["playlist", "library", "none"])
    #expect(ledger.batches.first?.tracks.last?.like?.first?.found == "library")
    #expect((staged["unverifiedReferences"] as? [String])?.count == 2)
    let stagedFile = try #require(FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil).first)
    let stagedText = try String(contentsOf: stagedFile, encoding: .utf8)
    #expect(!stagedText.contains("request"))
    #expect(!stagedText.contains("why"))
    #expect(!stagedText.contains("like"))
  }

  @Test("stage truncates request and reason in the ledger and reports it")
  func stageReasoningTruncation() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let request = String(repeating: "r", count: 501)
    let why = String(repeating: "w", count: 301)
    let (server, _) = try makeServer(snapshot: s0Fixture(), tasteRootURL: tasteRoot)
    let arguments = #"{"name":"Long Reason","request":"\#(request)","tracks":[{"artist":"A","title":"B","year":2024,"why":"\#(why)"}]}"#
    let staged = try #require(await resultJSON(server, id: 1, name: "stage_playlist", arguments: arguments) as? [String: Any])
    #expect(staged["truncated"] as? Bool == true)
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    let ledgerFile = try #require(FileManager.default.contentsOfDirectory(at: recommendationFolder, includingPropertiesForKeys: nil).first)
    let batch = try #require(RecommendationLedgerCodec.readFiles([try Data(contentsOf: ledgerFile)]).batches.first)
    #expect(batch.request?.count == 500)
    #expect(batch.tracks.first?.why?.count == 300)
  }

  @Test("New Music picks validate against and record the latest saved week")
  func recordNewMusicPicks() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let exposureFolder = tasteRoot.appending(path: "exposure", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: exposureFolder, withIntermediateDirectories: true)
    let week = NewMusicWeek(lastModifiedDate: Date(timeIntervalSince1970: 1_790_000_000),
      fetchedAt: Date(timeIntervalSince1970: 1_790_000_100), host: "Mac", tracks: [
        NewMusicTrack(catalogID: "catalog", title: "Week Song", artist: "Week Artist", releaseDate: "2026-01-01"),
        NewMusicTrack(catalogID: "catalog-2", title: "Other Week Song", artist: "Other Week Artist", releaseDate: "2025-01-01"),
      ])
    try NewMusicExposureCodec.encode(week).write(to: exposureFolder.appending(path: "week.jsonl"))
    let inbox = root.appending(path: "PlaylistInbox", directoryHint: .isDirectory)
    let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let (server, _) = try makeServer(snapshot: s0Fixture(), inbox: inbox, tasteRootURL: tasteRoot, now: { recordedAt })
    let empty = try #require(await call(server, id: 0, name: "record_new_music_picks", arguments: #"{"songs":[]}"#))
    #expect(empty.contains("songs must contain at least one pick"))
    #expect(empty.contains("\"isError\":true"))
    let invalid = try #require(await call(server, id: 1, name: "record_new_music_picks",
      arguments: #"{"songs":[{"artist":"Other Artist","title":"Other Song"}]}"#))
    #expect(invalid.contains("Other Artist — Other Song isn't in the latest saved New Music week"))
    #expect(invalid.contains("\"isError\":true"))
    let recorded = try #require(await resultJSON(server, id: 2, name: "record_new_music_picks",
      arguments: #"{"songs":[{"artist":"Week Artist","title":"Week Song"}]}"#) as? [String: Any])
    #expect(recorded["recorded"] as? Bool == true)
    #expect(recorded["songCount"] as? Int == 1)
    #expect(try canonicalJSON(recorded) == #"{"recorded":true,"recordedAt":"2027-01-15T08:00:00Z","songCount":1}"#)
    #expect(!String(describing: recorded).contains(tasteRoot.path))
    #expect(!String(describing: recorded).contains("catalog"))
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    let ledgerFile = try #require(FileManager.default.contentsOfDirectory(at: recommendationFolder, includingPropertiesForKeys: nil).first)
    let batch = try #require(RecommendationLedgerCodec.readFiles([try Data(contentsOf: ledgerFile)]).batches.first)
    #expect(batch.kind == "new-music-picks")
    #expect(batch.batchDate == week.lastModifiedDate)
    #expect(batch.tracks.first?.picked == true)

    let beforeStage = try #require(await resultJSON(server, id: 3, name: "check_tracks",
      arguments: #"{"tracks":[{"artist":"Week Artist","title":"Week Song"},{"artist":"Other Week Artist","title":"Other Week Song"}]}"#) as? [String: Any])
    let beforeRows = try #require(beforeStage["tracks"] as? [[String: Any]])
    #expect(beforeRows.allSatisfy { $0["recommended"] == nil })
    _ = try #require(await resultJSON(server, id: 4, name: "stage_playlist",
      arguments: #"{"name":"Picked week","tracks":[{"artist":"Week Artist","title":"Week Song","year":2026},{"artist":"Other Week Artist","title":"Other Week Song","year":2025}]}"#) as? [String: Any])
    let batches = RecommendationLedgerCodec.readFiles([try Data(contentsOf: ledgerFile)]).batches
    let staged = try #require(batches.first { $0.kind == "staged-playlist" })
    #expect(staged.tracks.count == 2)
    #expect(staged.tracks.allSatisfy { !$0.familiar && !$0.reasons.contains("recommended") })
  }

  @Test("recommendation_outcomes returns golden JSON without library identifiers or paths")
  func recommendationOutcomesGoldenJSON() async throws {
    let root = temporaryDirectory()
    let tasteRoot = root.appending(path: "Taste Intelligence", directoryHint: .isDirectory)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [])
    let recommendationFolder = tasteRoot.appending(path: "recommendations", directoryHint: .isDirectory)
    try RecommendationLedgerCodec.append(RecommendationBatch(recordedAt: now, host: "Fixture",
      playlist: "Fixture batch", tracks: [RecommendationTrack(artist: "New Artist", title: "New Song",
        familiar: false, reasons: [], artistKnown: false)]), host: "Fixture", folder: recommendationFolder)
    let (server, _) = try makeServer(snapshot: snapshot, tasteRootURL: tasteRoot, now: { now })
    let result = try #require(await resultJSON(server, id: 1, name: "recommendation_outcomes",
      arguments: #"{"batches":10}"#) as? [String: Any])
    let json = try canonicalJSON(result)
    #expect(json == #"{"coverage":{"exposureGaps":0,"exposureSkippedLines":0,"listeningStatus":"not_set_up","snapshotAge":0,"snapshotGeneratedAt":"2027-01-15T08:00:00Z"},"outcomes":{"batches":[{"counts":{"pending":1},"kind":"staged-playlist","notCounted":[],"playlist":"Fixture batch","recordedAt":"2027-01-15T08:00:00Z","songs":[{"artist":"New Artist","band":"unknown","classification":"pending","title":"New Song"}],"source":"chat"}],"listeningCoverage":{"collapsedOverlappingPlays":0,"gaps":[]},"skippedLines":0,"snapshotAge":0}}"#)
    #expect(!json.contains("persistentID"))
    #expect(!json.contains(root.path))
  }

  @Test("instructions use the brief's standalone head and only the track rules tail")
  func instructions() {
    let briefParagraph = "Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any claim about what Jon owns, has played, or has loved — never guess. Before proposing a final list, call check_tracks on it. For Jon's uploads, use an exact album from uploadedAlbums as the album hint. When Jon asks for the playlist, call stage_playlist with the final list instead of printing it; Jon reviews and creates it in Vinyl Fever. Snapshot age is in library_overview."
    #expect(LibraryMCPServer.instructions.hasPrefix(briefParagraph))
    #expect(LibraryMCPServer.instructionHead == briefParagraph)
    #expect(LibraryMCPServer.instructionHead.count <= 512)
    #expect(MCPServer.instructionsHeadStandsAlone(LibraryMCPServer.instructions))
    #expect(LibraryMCPServer.instructions.contains("For taste questions, start with list_playlists"))
    #expect(LibraryMCPServer.instructions.contains("`list_playlists` returns `openQuestions` when there are any."))
    #expect(LibraryMCPServer.instructions.contains("ask at most one without waiting to be asked"))
    #expect(LibraryMCPServer.instructions.contains("Record his reply word for word as `note`"))
    #expect(LibraryMCPServer.instructions.contains("show Jon each song's year and why"))
    #expect(LibraryMCPServer.instructions.contains("If the result lists `missingYear` or `unverifiedReferences`, tell Jon which songs."))
    #expect(LibraryMCPServer.instructions.contains("Don't stage the same batch again"))
    #expect(LibraryMCPServer.instructions.contains("never ask what tools can tell you"))
    #expect(!LibraryMCPServer.instructions.contains("VF Note"))
    #expect(LibraryMCPServer.instructions.contains("Stage discoveries with stage_playlist"))
    #expect(LibraryMCPServer.instructions.contains("Drop songs recommended before, unless Jon asks for them again."))
    #expect(LibraryMCPServer.instructions.contains("record_new_music_picks"))
    #expect(LibraryMCPServer.instructions.contains("`like`"))
    #expect(LibraryMCPServer.instructions.contains("name the playlist"))
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

  private func makeServer(snapshot: LibrarySnapshot, inbox: URL? = nil, listeningRootURL: URL? = nil,
    tasteRootURL: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) throws -> (MCPServer, URL) {
    let root = temporaryDirectory()
    let snapshotURL = root.appending(path: "library-snapshot.json")
    try LibrarySnapshotCodec.encode(snapshot).write(to: snapshotURL)
    return (LibraryMCPServer.make(snapshotURL: snapshotURL, inboxRoot: inbox ?? root.appending(path: "inbox"), listeningRootURL: listeningRootURL ?? root.appending(path: "Listening"), tasteRootURL: tasteRootURL ?? root.appending(path: "Taste Intelligence"), now: now), snapshotURL)
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

  private func canonicalJSON(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    return String(decoding: data, as: UTF8.self)
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
