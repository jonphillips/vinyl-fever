import Foundation
import LLMHandoffKit
import MCPServerKit

private struct PlaylistToolPayload: Codable, Sendable {
  struct Track: Codable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var year: Int?
  }
  var name: String
  var description: String?
  var tracks: [Track]
}

private struct CheckTracksPayload: Decodable, Sendable {
  struct Track: Decodable, Sendable { var artist: String; var title: String }
  var tracks: [Track]
}

private struct SearchPayload: Decodable, Sendable {
  var artist: String?; var title: String?; var album: String?; var genre: String?
  var yearFrom: Int?; var yearTo: Int?; var minPlays: Int?; var maxPlays: Int?
  var favorited: Bool?; var availability: LibraryAvailability?; var sort: String?; var limit: Int?
}

private struct RankingPayload: Decodable, Sendable { var ranking: String?; var limit: Int? }
private struct ArtistPayload: Decodable, Sendable { var artist: String }

private struct MCPTrack: Encodable {
  var name: String; var artist: String; var albumArtist: String; var album: String
  var genre: String?; var year: Int?; var durationSeconds: Double?; var playCount: Int
  var favorited: Bool; var dateAdded: Date?; var lastPlayed: Date?; var availability: LibraryAvailability

  init(_ track: LibraryTrack) {
    name = track.name; artist = track.artist; albumArtist = track.albumArtist; album = track.album
    genre = track.genre; year = track.year; durationSeconds = track.durationSeconds
    playCount = track.playCount; favorited = track.favorited; dateAdded = track.dateAdded
    lastPlayed = track.lastPlayed; availability = track.availability
  }
}

private struct MCPArtistProfile: Encodable {
  var artist: String; var albums: [String]; var trackCount: Int; var totalPlays: Int
  var favorites: Int; var firstAdded: Date?; var lastPlayed: Date?
  var mostPlayedTracks: [MCPTrack]; var uploadedTrackCount: Int

  init(_ profile: LibraryArtistProfile) {
    artist = profile.artist; albums = profile.albums; trackCount = profile.trackCount
    totalPlays = profile.totalPlays; favorites = profile.favorites; firstAdded = profile.firstAdded
    lastPlayed = profile.lastPlayed; mostPlayedTracks = profile.mostPlayedTracks.map(MCPTrack.init)
    uploadedTrackCount = profile.uploadedTrackCount
  }
}

private actor LibraryMCPContext {
  private let snapshotURL: URL
  private let inbox: HandoffInbox
  private var cachedIndex: LibraryIndex?
  private var cachedModifiedAt: Date?

  init(snapshotURL: URL?, inboxRoot: URL?) {
    self.snapshotURL = snapshotURL ?? Self.defaultSnapshotURL
    self.inbox = HandoffInbox(root: inboxRoot ?? Self.defaultInbox.root, fileExtension: "vfplaylist")
  }

  static var defaultSnapshotURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/VinylFever/LibrarySnapshot/library-snapshot.json")
  }
  static var defaultInbox: HandoffInbox {
    HandoffInbox(
      root: FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/VinylFever/PlaylistInbox", directoryHint: .isDirectory),
      fileExtension: "vfplaylist"
    )
  }

  func index() throws -> (LibraryIndex, Date) {
    let attributes = try? FileManager.default.attributesOfItem(atPath: snapshotURL.path)
    guard let modifiedAt = attributes?[.modificationDate] as? Date else {
      throw SnapshotUnavailable()
    }
    if let cachedIndex, cachedModifiedAt == modifiedAt { return (cachedIndex, modifiedAt) }
    do {
      let snapshot = try LibrarySnapshotCodec.decode(Data(contentsOf: snapshotURL))
      let index = LibraryIndex(snapshot: snapshot)
      cachedIndex = index
      cachedModifiedAt = modifiedAt
      return (index, snapshot.generatedAt)
    } catch {
      throw error
    }
  }

  func stage(_ payload: PlaylistToolPayload) throws -> (file: String, droppedCount: Int) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
    let contract = "VF-PLAYLIST: v1\n\(json)"
    let decoded = try PlaylistContract.decode(contract)
    guard !decoded.request.tracks.isEmpty else {
      throw PlaylistContractError.invalidShape("tracks must contain at least one non-empty track")
    }
    let item = try inbox.stage(contract, slug: payload.name, now: Date())
    return (item.url.lastPathComponent, decoded.droppedTracks.count)
  }
}

private struct SnapshotUnavailable: LocalizedError {
  var errorDescription: String? { "Open Vinyl Fever to build the library snapshot." }
}

/// Factory for the standalone `vf-mcp` helper and the instructions used by every client.
public enum LibraryMCPServer {
  public static let instructions: String = {
    "Vinyl Fever answers read-only questions about Jon's Apple Music library. Its one write tool stages a playlist for review in Vinyl Fever; staging never changes Apple Music. Jon must review the playlist and press Create in Vinyl Fever. Library answers reflect the latest snapshot built by Vinyl Fever.\n\n"
      + PlaylistContract.projectInstructions
  }()

  public static func make(
    snapshotURL: URL? = nil,
    inboxRoot: URL? = nil
  ) -> MCPServer {
    let context = LibraryMCPContext(snapshotURL: snapshotURL, inboxRoot: inboxRoot)
    let readOnly = MCPToolAnnotations(readOnly: true)
    return MCPServer(name: "Vinyl Fever", version: "1.0.0", instructions: instructions, tools: [
      MCPTool(name: "library_overview", description: "Summarize Jon's Apple Music library, including track, artist, album, genre and decade counts.", inputSchema: schema([:]), annotations: readOnly) { _ in
        let (index, generatedAt) = try await context.index()
        return .json(index.overview(generatedAt: generatedAt))
      },
      MCPTool(name: "top_artists", description: "List artists ranked by plays, favorites, recent additions, or recent plays.", inputSchema: schema(["ranking": enumField(["plays", "favorites", "recentlyAdded", "recentlyPlayed"]), "limit": integerField]), annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input)
        let (index, _) = try await context.index()
        return .json(index.topArtists(by: ranking(p.ranking), limit: p.limit ?? LibraryIndex.defaultLimit))
      },
      MCPTool(name: "top_tracks", description: "List tracks ranked by plays, favorites, recent additions, or recent plays.", inputSchema: schema(["ranking": enumField(["plays", "favorites", "recentlyAdded", "recentlyPlayed"]), "limit": integerField]), annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input)
        let (index, _) = try await context.index()
        return .json(index.topTracks(by: ranking(p.ranking), limit: p.limit ?? LibraryIndex.defaultLimit).map(MCPTrack.init))
      },
      MCPTool(name: "search_tracks", description: "Search library tracks by artist, title, album, genre, year, play count, favorite status, or availability.", inputSchema: schema(["artist": stringField, "title": stringField, "album": stringField, "genre": stringField, "yearFrom": integerField, "yearTo": integerField, "minPlays": integerField, "maxPlays": integerField, "favorited": boolField, "availability": enumField(LibraryAvailability.allCases.map(\.rawValue)), "sort": enumField(["plays", "favorites", "recentlyAdded", "recentlyPlayed", "title", "artist"]), "limit": integerField]), annotations: readOnly) { input in
        let p = try decode(SearchPayload.self, from: input)
        let (index, _) = try await context.index()
        var filter = LibrarySearchFilter()
        filter.artist = p.artist; filter.title = p.title; filter.album = p.album; filter.genre = p.genre
        filter.yearFrom = p.yearFrom; filter.yearTo = p.yearTo; filter.minPlays = p.minPlays
        filter.maxPlays = p.maxPlays; filter.favorited = p.favorited; filter.availability = p.availability
        return .json(index.search(filter, sort: sort(p.sort), limit: p.limit ?? LibraryIndex.defaultLimit).map(MCPTrack.init))
      },
      MCPTool(name: "artist_profile", description: "Show library statistics, albums and most played tracks for an artist.", inputSchema: schema(["artist": stringField], required: ["artist"]), annotations: readOnly) { input in
        let p = try decode(ArtistPayload.self, from: input)
        let (index, _) = try await context.index()
        guard let profile = index.artistProfile(p.artist) else { return .json(Optional<LibraryArtistProfile>.none) }
        return .json(MCPArtistProfile(profile))
      },
      MCPTool(name: "check_tracks", description: "Check which requested songs are in the library and return summed plays across versions.", inputSchema: schema(["tracks": .object(["type": .string("array"), "maxItems": .integer(LibraryIndex.maximumCheckTracks), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])])], required: ["tracks"]), annotations: readOnly) { input in
        let p = try decode(CheckTracksPayload.self, from: input)
        let (index, _) = try await context.index()
        return .json(index.checkTracks(p.tracks.map { (artist: $0.artist, title: $0.title) }))
      },
      MCPTool(name: "stage_playlist", description: "Stage a VF-PLAYLIST v1 payload in Vinyl Fever for Jon to review. This does not create or modify an Apple Music playlist.", inputSchema: schema(["name": stringField, "description": stringField, "tracks": .object(["type": .string("array"), "minItems": .integer(1), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField, "album": stringField, "year": integerField]), "required": .array([.string("artist"), .string("title")])])])], required: ["name", "tracks"])) { input in
        let payload = try decode(PlaylistToolPayload.self, from: input)
        let staged = try await context.stage(payload)
        let dropped = staged.droppedCount == 0 ? "" : " Dropped \(staged.droppedCount) blank track(s)."
        return .text("Staged \(staged.file).\(dropped) Open Vinyl Fever → Playlists → From chat to review it.")
      },
    ])
  }

  private static let stringField: MCPValue = .object(["type": .string("string")])
  private static let integerField: MCPValue = .object(["type": .string("integer")])
  private static let boolField: MCPValue = .object(["type": .string("boolean")])
  private static func enumField(_ values: [String]) -> MCPValue {
    .object(["type": .string("string"), "enum": .array(values.map(MCPValue.string))])
  }
  private static func schema(_ properties: [String: MCPValue], required: [String] = []) -> MCPValue {
    var value: [String: MCPValue] = ["type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(false)]
    if !required.isEmpty { value["required"] = .array(required.map(MCPValue.string)) }
    return .object(value)
  }
  private static func decode<T: Decodable>(_ type: T.Type, from value: MCPValue) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
  private static func ranking(_ value: String?) -> LibraryRanking {
    switch value { case "favorites": .favorites; case "recentlyAdded": .recentlyAdded; case "recentlyPlayed": .recentlyPlayed; default: .plays }
  }
  private static func sort(_ value: String?) -> LibrarySort {
    switch value { case "favorites": .favorites; case "recentlyAdded": .recentlyAdded; case "recentlyPlayed": .recentlyPlayed; case "title": .title; case "artist": .artist; default: .plays }
  }
}
