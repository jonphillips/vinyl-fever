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
  enum CodingKeys: String, CodingKey { case artist, title, album, genre, yearFrom = "year_from", yearTo = "year_to", minPlays = "min_plays", maxPlays = "max_plays", favorited, availability, sort, limit }
}

private struct RankingPayload: Decodable, Sendable { var by: String?; var limit: Int? }
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
  private var cachedGeneratedAt: Date?
  private var cachedOverview: LibraryOverview?

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
    if let cachedIndex, let cachedGeneratedAt, cachedModifiedAt == modifiedAt { return (cachedIndex, cachedGeneratedAt) }
    do {
      let snapshot = try LibrarySnapshotCodec.decode(Data(contentsOf: snapshotURL))
      let index = LibraryIndex(snapshot: snapshot)
      cachedIndex = index
      cachedModifiedAt = modifiedAt
      cachedGeneratedAt = snapshot.generatedAt
      cachedOverview = index.overview(generatedAt: snapshot.generatedAt)
      return (index, snapshot.generatedAt)
    } catch {
      throw error
    }
  }

  func overview() throws -> LibraryOverview {
    _ = try index()
    guard let cachedOverview else { throw SnapshotUnavailable() }
    return cachedOverview
  }

  func stage(_ payload: PlaylistToolPayload) throws -> (name: String, trackCount: Int, dropped: [DroppedPlaylistTrack]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
    let contract = "VF-PLAYLIST: v1\n\(json)"
    let decoded = try PlaylistContract.decode(contract)
    guard !decoded.request.tracks.isEmpty else {
      throw PlaylistContractError.invalidShape("tracks must contain at least one track")
    }
    _ = try inbox.stage(contract, slug: payload.name, now: Date())
    return (decoded.request.name, decoded.request.tracks.count, decoded.droppedTracks)
  }
}

private struct SnapshotUnavailable: LocalizedError {
  var errorDescription: String? { "Open Vinyl Fever to build the library snapshot." }
}

/// Factory for the standalone `vf-mcp` helper and the instructions used by every client.
public enum LibraryMCPServer {
  public static let instructionHead = """
  Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any claim about what Jon owns, has played, or has loved — never guess. Before proposing a final list, call check_tracks on it. Tracks with availability "uploaded" are library-only and can't be added to a catalog playlist; leave them out. When Jon asks for the playlist, call stage_playlist with the final list instead of printing it; Jon reviews and creates it in Vinyl Fever. Snapshot age is in library_overview.
  """
  public static let instructions: String = {
    instructionHead + "\n\n" + PlaylistContract.trackRules
  }()

  public static func make(
    snapshotURL: URL? = nil,
    inboxRoot: URL? = nil
  ) -> MCPServer {
    let context = LibraryMCPContext(snapshotURL: snapshotURL, inboxRoot: inboxRoot)
    let readOnly = MCPToolAnnotations(readOnly: true, openWorld: false)
    let overviewSchema = schema([:])
    let topArtistsSchema = schema(["by": enumField(["plays", "favorites", "recently_added"]), "limit": integerField])
    let topTracksSchema = schema(["by": enumField(["plays", "favorites", "recently_added", "recently_played"]), "limit": integerField])
    let searchSchema = schema(["artist": stringField, "title": stringField, "album": stringField, "genre": stringField, "year_from": integerField, "year_to": integerField, "min_plays": integerField, "max_plays": integerField, "favorited": boolField, "availability": enumField(LibraryAvailability.allCases.map(\.rawValue)), "sort": enumField(["plays", "favorites", "recently_added", "recently_played", "title", "artist"]), "limit": integerField])
    let artistSchema = schema(["artist": stringField], required: ["artist"])
    let checksSchema = schema(["tracks": .object(["type": .string("array"), "maxItems": .integer(LibraryIndex.maximumCheckTracks), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])])], required: ["tracks"])
    let stageSchema = schema(["name": stringField, "description": stringField, "tracks": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField, "album": stringField, "year": integerField]), "required": .array([.string("artist"), .string("title")])])])], required: ["name", "tracks"])
    return MCPServer(name: "Vinyl Fever", version: "1.0.0", instructions: instructions, tools: [
      MCPTool(name: "library_overview", description: "Summarize Jon's Apple Music library, including track, artist, album, genre and decade counts.", inputSchema: overviewSchema, annotations: readOnly) { _ in
        return .json(try await context.overview())
      },
      MCPTool(name: "top_artists", description: "List artists ranked by plays, favorites, or recent additions.", inputSchema: topArtistsSchema, annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input, schema: topArtistsSchema)
        let (index, _) = try await context.index()
        return .json(index.topArtists(by: try ranking(p.by, allowed: ["plays", "favorites", "recently_added"]), limit: p.limit ?? LibraryIndex.defaultLimit))
      },
      MCPTool(name: "top_tracks", description: "List tracks ranked by plays, favorites, recent additions, or recent plays.", inputSchema: topTracksSchema, annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input, schema: topTracksSchema)
        let (index, _) = try await context.index()
        return .json(index.topTracks(by: try ranking(p.by, allowed: ["plays", "favorites", "recently_added", "recently_played"]), limit: p.limit ?? LibraryIndex.defaultLimit).map(MCPTrack.init))
      },
      MCPTool(name: "search_library", description: "Search library tracks by artist, title, album, genre, year, play count, favorite status, or availability.", inputSchema: searchSchema, annotations: readOnly) { input in
        let p = try decode(SearchPayload.self, from: input, schema: searchSchema)
        let (index, _) = try await context.index()
        var filter = LibrarySearchFilter()
        filter.artist = p.artist; filter.title = p.title; filter.album = p.album; filter.genre = p.genre
        filter.yearFrom = p.yearFrom; filter.yearTo = p.yearTo; filter.minPlays = p.minPlays
        filter.maxPlays = p.maxPlays; filter.favorited = p.favorited; filter.availability = p.availability
        return .json(index.search(filter, sort: try sort(p.sort), limit: p.limit ?? LibraryIndex.defaultLimit).map(MCPTrack.init))
      },
      MCPTool(name: "artist_profile", description: "Show library statistics, albums and most played tracks for an artist.", inputSchema: artistSchema, annotations: readOnly) { input in
        let p = try decode(ArtistPayload.self, from: input, schema: artistSchema)
        let (index, _) = try await context.index()
        guard let profile = index.artistProfile(p.artist) else { return .text("No tracks by \"\(p.artist)\" in Jon's library.") }
        return .json(MCPArtistProfile(profile))
      },
      MCPTool(name: "check_tracks", description: "Check which requested songs are in the library and return summed plays across versions.", inputSchema: checksSchema, annotations: readOnly) { input in
        let p = try decode(CheckTracksPayload.self, from: input, schema: checksSchema)
        let (index, _) = try await context.index()
        return .json(index.checkTracks(p.tracks.map { (artist: $0.artist, title: $0.title) }))
      },
      MCPTool(name: "stage_playlist", description: "Stage a playlist proposal for Jon to review in Vinyl Fever; it does not change Apple Music.", inputSchema: stageSchema, annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
        let payload = try decode(PlaylistToolPayload.self, from: input, schema: stageSchema)
        let staged = try await context.stage(payload)
        let json = MCPToolResult.json(StagedPlaylistResult(staged: true, name: staged.name, trackCount: staged.trackCount, dropped: staged.dropped))
        let payloadText = json.content.first?.text ?? "{}"
        return .text(payloadText + "\n\nJon reviews and creates it in Vinyl Fever; nothing is in Apple Music yet.")
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
  private static func decode<T: Decodable>(_ type: T.Type, from value: MCPValue, schema: MCPValue) throws -> T {
    guard case let .object(arguments) = value else { throw ArgumentError.expectedObject }
    guard let properties = schema.objectValue?["properties"]?.objectValue else { throw ArgumentError.expectedObject }
    if let unknown = arguments.keys.sorted().first(where: { properties[$0] == nil }) {
      throw ArgumentError.unknown(unknown)
    }
    return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
  private static func ranking(_ value: String?, allowed: [String]) throws -> LibraryRanking {
    guard let value else { return .plays }
    guard allowed.contains(value) else { throw ArgumentError.invalidEnum(value) }
    return switch value { case "favorites": .favorites; case "recently_added": .recentlyAdded; case "recently_played": .recentlyPlayed; default: .plays }
  }
  private static func sort(_ value: String?) throws -> LibrarySort {
    guard let value else { return .plays }
    let allowed = ["plays", "favorites", "recently_added", "recently_played", "title", "artist"]
    guard allowed.contains(value) else { throw ArgumentError.invalidEnum(value) }
    return switch value { case "favorites": .favorites; case "recently_added": .recentlyAdded; case "recently_played": .recentlyPlayed; case "title": .title; case "artist": .artist; default: .plays }
  }
}

private struct StagedPlaylistResult: Encodable {
  struct Dropped: Encodable { var index: Int; var artist: String; var title: String }
  var staged: Bool; var name: String; var trackCount: Int; var dropped: [Dropped]
  init(staged: Bool, name: String, trackCount: Int, dropped: [DroppedPlaylistTrack]) {
    self.staged = staged; self.name = name; self.trackCount = trackCount
    self.dropped = dropped.map { Dropped(index: $0.index, artist: $0.artist, title: $0.title) }
  }
}

private enum ArgumentError: LocalizedError {
  case expectedObject
  case unknown(String)
  case invalidEnum(String)
  var errorDescription: String? {
    switch self {
    case .expectedObject: "Expected an object of tool arguments."
    case .unknown(let key): "Unknown argument \"\(key)\"."
    case .invalidEnum(let value): "Unrecognized value \"\(value)\"."
    }
  }
}
