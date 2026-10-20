import Foundation
import LLMHandoffKit
import MCPServerKit
import VinylFeverListening

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

private struct RankingPayload: Decodable, Sendable { var by: String?; var period: String?; var limit: Int? }
private struct ListeningPayload: Decodable, Sendable { var period: String?; var limit: Int?; var by: String? }
private struct ArtistPayload: Decodable, Sendable { var artist: String }

private struct MCPListeningCoverage: Encodable {
  struct Gap: Encodable { var host: String; var outcome: String; var windowStart: Date?; var windowEnd: Date; var detail: String? }
  var firstFetchAt: Date?; var lastFetchAt: Date?; var lastFetchAge: TimeInterval?; var pollingMac: String?
  var gaps: [Gap]; var collapsedOverlappingPlays: Int
  init(_ value: ListeningCoverage, now: Date, period: ListeningPeriod) {
    firstFetchAt = value.firstFetchAt; lastFetchAt = value.lastFetchAt
    lastFetchAge = value.lastFetchAt.map { max(0, now.timeIntervalSince($0)) }
    pollingMac = value.host
    gaps = value.gaps.filter { $0.windowEnd >= now.addingTimeInterval(-period.duration) }
      .map { Gap(host: $0.host, outcome: $0.outcome.rawValue, windowStart: $0.windowStart, windowEnd: $0.windowEnd, detail: $0.detail) }
    collapsedOverlappingPlays = value.collapsedOverlappingPlays
  }
}
private struct MCPRecentListening: Encodable {
  struct Play: Encodable { var artist: String; var title: String; var album: String?; var windowStart: Date; var windowEnd: Date; var inLibrary: Bool }
  var plays: [Play]; var coverage: MCPListeningCoverage
}
private struct MCPListeningArtists: Encodable { var artists: [ListeningArtistCount]; var coverage: MCPListeningCoverage }
private struct MCPListeningTracks: Encodable { var tracks: [ListeningTrackCount]; var coverage: MCPListeningCoverage }

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
  private let listeningRootURL: URL
  private var cachedListeningLog: ListeningLog?
  private var cachedListeningFiles: [URL: Date] = [:]
  private var cachedListeningIdentity: ArtistIdentity = .empty

  init(snapshotURL: URL?, inboxRoot: URL?, listeningRootURL: URL?) {
    self.snapshotURL = snapshotURL ?? Self.defaultSnapshotURL
    self.inbox = HandoffInbox(root: inboxRoot ?? Self.defaultInbox.root, fileExtension: "vfplaylist")
    self.listeningRootURL = listeningRootURL ?? Self.defaultListeningRootURL
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
  static var defaultListeningRootURL: URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Listening", directoryHint: .isDirectory)
  }

  func listeningLog(now: Date = Date()) throws -> ListeningLog {
    let identity = (try? index().0.artistIdentity) ?? .empty
    let fetches = listeningRootURL.appending(path: "fetches", directoryHint: .isDirectory)
    let files = FileManager.default.enumerator(at: fetches, includingPropertiesForKeys: [.contentModificationDateKey])?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" } ?? []
    guard !files.isEmpty else { throw ListeningHistoryNotSetUp() }
    let modified = Dictionary(uniqueKeysWithValues: files.compactMap { url in
      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return date.map { (url, $0) }
    })
    if let cachedListeningLog, modified == cachedListeningFiles,
      identity == cachedListeningIdentity { return cachedListeningLog }
    let streams = try files.map { try Self.readCoordinated($0) }.compactMap { $0 }
    let log = try ListeningLog(jsonlStreams: streams, now: now, identity: identity)
    cachedListeningFiles = modified
    cachedListeningLog = log
    cachedListeningIdentity = identity
    return log
  }

  private static func readCoordinated(_ url: URL) throws -> Data? {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<Data, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
      result = Result { try Data(contentsOf: target) }
    }
    if let coordinationError { throw coordinationError }
    return try result?.get()
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
private struct ListeningHistoryNotSetUp: LocalizedError {
  var errorDescription: String? { "Listening history isn't set up yet. See Vinyl Fever → Settings → Listening History." }
}

/// Factory for the standalone `vf-mcp` helper and the instructions used by every client.
public enum LibraryMCPServer {
  public static let instructionHead = """
  Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any claim about what Jon owns, has played, or has loved — never guess. Before proposing a final list, call check_tracks on it. For Jon's uploads, use an exact album from uploadedAlbums as the album hint. When Jon asks for the playlist, call stage_playlist with the final list instead of printing it; Jon reviews and creates it in Vinyl Fever. Snapshot age is in library_overview.
  """
  public static let instructions: String = {
    instructionHead + "\n\n" + PlaylistContract.trackRules
  }()

  public static func make(
    snapshotURL: URL? = nil,
    inboxRoot: URL? = nil,
    listeningRootURL: URL? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) -> MCPServer {
    let context = LibraryMCPContext(snapshotURL: snapshotURL, inboxRoot: inboxRoot, listeningRootURL: listeningRootURL)
    let readOnly = MCPToolAnnotations(readOnly: true, openWorld: false)
    let overviewSchema = schema([:])
    let topArtistsSchema = schema(["by": enumField(["plays", "favorites", "recently_added"]), "period": enumField(["all_time", "7d", "30d", "90d"]), "limit": integerField])
    let topTracksSchema = schema(["by": enumField(["plays", "favorites", "recently_added", "recently_played"]), "period": enumField(["all_time", "7d", "30d", "90d"]), "limit": integerField])
    let recentListeningSchema = schema(["period": enumField(["24h", "7d", "30d", "90d"]), "limit": integerField], required: ["period"])
    let searchSchema = schema(["artist": stringField, "title": stringField, "album": stringField, "genre": stringField, "year_from": integerField, "year_to": integerField, "min_plays": integerField, "max_plays": integerField, "favorited": boolField, "availability": enumField(LibraryAvailability.allCases.map(\.rawValue)), "sort": enumField(["plays", "favorites", "recently_added", "recently_played", "title", "artist"]), "limit": integerField])
    let artistSchema = schema(["artist": stringField], required: ["artist"])
    let checksSchema = schema(["tracks": .object(["type": .string("array"), "maxItems": .integer(LibraryIndex.maximumCheckTracks), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])])], required: ["tracks"])
    let stageSchema = schema(["name": stringField, "description": .object(["type": .string("string"), "description": .string(stageDescriptionGuidance)]), "tracks": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField, "album": stringField, "year": integerField]), "required": .array([.string("artist"), .string("title")])])])], required: ["name", "tracks"])
    return MCPServer(name: "Vinyl Fever", version: "1.0.0", instructions: instructions, tools: [
      MCPTool(name: "library_overview", description: "Summarize Jon's Apple Music library, including track, artist, album, genre and decade counts.", inputSchema: overviewSchema, annotations: readOnly) { _ in
        return .json(try await context.overview())
      },
      MCPTool(name: "top_artists", description: "Without period, ranks Mac library counts, which miss device plays. Periods count songs started in the listening log since polling began; skips and brief autoplay count. Only by: plays is allowed with periods.", inputSchema: topArtistsSchema, annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input, schema: topArtistsSchema)
        if let value = p.period, value != "all_time" {
          guard p.by == nil || p.by == "plays" else { throw ArgumentError.periodRanking }
          let log = try await context.listeningLog()
          let period = try listeningPeriod(value)
          let instant = now()
          return .json(MCPListeningArtists(artists: log.topArtists(period: period, now: instant, limit: p.limit ?? LibraryIndex.defaultLimit), coverage: MCPListeningCoverage(log.coverage, now: instant, period: period)))
        }
        let (index, _) = try await context.index()
        return .json(index.topArtists(by: try ranking(p.by, allowed: ["plays", "favorites", "recently_added"]), limit: p.limit ?? LibraryIndex.defaultLimit))
      },
      MCPTool(name: "top_tracks", description: "Without period, ranks Mac library counts, which miss device plays. Periods count songs started in the listening log since polling began; skips and brief autoplay count. Only by: plays is allowed with periods.", inputSchema: topTracksSchema, annotations: readOnly) { input in
        let p = try decode(RankingPayload.self, from: input, schema: topTracksSchema)
        if let value = p.period, value != "all_time" {
          guard p.by == nil || p.by == "plays" else { throw ArgumentError.periodRanking }
          let log = try await context.listeningLog()
          let period = try listeningPeriod(value)
          let instant = now()
          return .json(MCPListeningTracks(tracks: log.topTracks(period: period, now: instant, limit: p.limit ?? LibraryIndex.defaultLimit), coverage: MCPListeningCoverage(log.coverage, now: instant, period: period)))
        }
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
      MCPTool(name: "recent_listening", description: "Show songs started in Jon's listening log, newest first. Skips and brief autoplay count as plays, not full listens. Coverage begins when polling started.", inputSchema: recentListeningSchema, annotations: readOnly) { input in
        let p = try decode(ListeningPayload.self, from: input, schema: recentListeningSchema)
        let period = try listeningPeriod(p.period ?? "24h")
        let instant = now()
        let log = try await context.listeningLog()
        let (index, _) = try await context.index()
        let plays = log.recentPlays(period: period, now: instant, limit: p.limit ?? LibraryIndex.defaultLimit)
        let checks = index.checkTracks(plays.map { (artist: $0.item.artist, title: $0.item.title) })
        let rows = zip(plays, checks).map { play, check in MCPRecentListening.Play(artist: play.item.artist, title: play.item.title, album: play.item.album, windowStart: play.windowStart, windowEnd: play.windowEnd, inLibrary: check.owned) }
        return .json(MCPRecentListening(plays: rows, coverage: MCPListeningCoverage(log.coverage, now: instant, period: period)))
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

  /// Create writes the description into Apple Music, so keep chat's process notes out of it.
  private static let stageDescriptionGuidance =
    "One sentence about the music; it becomes the playlist's description in Apple Music. No library stats, availability notes, or dates."
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

  private static func listeningPeriod(_ value: String) throws -> ListeningPeriod {
    switch value {
    case "24h": .day
    case "7d": .week
    case "30d": .month
    case "90d": .quarter
    default: throw ArgumentError.invalidEnum(value)
    }
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
  case periodRanking
  var errorDescription: String? {
    switch self {
    case .expectedObject: "Expected an object of tool arguments."
    case .unknown(let key): "Unknown argument \"\(key)\"."
    case .invalidEnum(let value): "Unrecognized value \"\(value)\"."
    case .periodRanking: "Only by: plays is allowed with a listening period."
    }
  }
}
