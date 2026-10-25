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
private struct PlaylistListPayload: Decodable, Sendable { var role: String?; var limit: Int? }
private struct PlaylistTracksPayload: Decodable, Sendable { var name: String; var limit: Int? }
private struct TasteNotesPayload: Decodable, Sendable {
  var artist: String?; var title: String?; var playlist: String?; var period: String?; var limit: Int?
}
private struct RecordTasteNotePayload: Decodable, Sendable {
  var note: String; var artist: String?; var title: String?; var album: String?; var playlist: String?
}

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
private struct MCPTasteCoverage: Encodable {
  var exposureGaps: Int
  var exposureSkippedLines: Int
  var listening: MCPListeningCoverage?
  var listeningStatus: String?
  var snapshotGeneratedAt: Date
  var snapshotAge: TimeInterval
}
private struct MCPKeptAndPassed: Encodable { var weeks: [NewMusicWeekResult]; var coverage: MCPTasteCoverage }
private struct MCPBaselines: Encodable { var baselines: TasteBaselines; var coverage: MCPTasteCoverage }
private struct MCPTasteNotesCoverage: Encodable {
  var filesRead: Int
  var skippedLines: Int
  var listening: MCPListeningCoverage?
  var listeningStatus: String?
}
private struct MCPTasteNote: Encodable {
  var title: String?
  var artist: String?
  var album: String?
  var playlist: String?
  var notedAt: Date
  var note: String
  var source: String
  var firstHearing: Bool?
  var candidates: [TasteNoteSongCandidate]?

  init(_ value: TasteNote, candidates: [TasteNoteSongCandidate]? = nil) {
    title = value.title?.isEmpty == true ? nil : value.title
    artist = value.artist?.isEmpty == true ? nil : value.artist
    album = value.album; playlist = value.playlist; notedAt = value.notedAt
    note = value.note; source = value.source; firstHearing = value.firstHearing
    self.candidates = candidates
  }
}
private struct MCPTasteNotes: Encodable { var notes: [MCPTasteNote]; var coverage: MCPTasteNotesCoverage }
private struct MCPRecordedTasteNote: Encodable { var recorded: Bool; var notedAt: Date; var source: String }
private struct MCPNoteEvidence: Encodable {
  var count: Int
  var newestNote: String?
  var newestNotedAt: Date?
  init(_ notes: [TasteNote]) {
    count = notes.count; newestNote = notes.first?.note; newestNotedAt = notes.first?.notedAt
  }
}

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
  private var aliasesURL: URL { snapshotURL.deletingLastPathComponent().appending(path: "artist-aliases.json") }
  private let inbox: HandoffInbox
  private var cachedIndex: LibraryIndex?
  private var cachedSnapshot: LibrarySnapshot?
  private var cachedModifiedAt: Date?
  private var cachedAliasesModifiedAt: Date?
  private var cachedGeneratedAt: Date?
  private var cachedOverview: LibraryOverview?
  private var cachedPlaylistIndex: PlaylistIndex?
  private var cachedPlaylistIndexSnapshotModifiedAt: Date?
  private var cachedPlaylistIndexRolesModifiedAt: Date?
  private var cachedPlaylistRolesModifiedAt: Date?
  private var cachedPlaylistRoles: PlaylistRoles?
  private let listeningRootURL: URL
  private let tasteRootURL: URL
  private let hostName: @Sendable () -> String
  private var cachedListeningLog: ListeningLog?
  private var cachedListeningFiles: [URL: Date] = [:]
  private var cachedListeningIdentity: ArtistIdentity = .empty
  private var cachedHeardBySong: [String: [Date]] = [:]
  private var cachedTasteNotes: TasteNotesReadResult?
  private var cachedTasteNoteFiles: [URL: Date] = [:]
  private var cachedRecommendationLedger: RecommendationLedgerReadResult?
  private var cachedRecommendationFiles: [URL: Date] = [:]
  private var cachedRecommendationEvidence: RecommendationLedgerEvidenceIndex?

  init(snapshotURL: URL?, inboxRoot: URL?, listeningRootURL: URL?, tasteRootURL: URL?, hostName: @escaping @Sendable () -> String) {
    self.snapshotURL = snapshotURL ?? Self.defaultSnapshotURL
    self.inbox = HandoffInbox(root: inboxRoot ?? Self.defaultInbox.root, fileExtension: "vfplaylist")
    self.listeningRootURL = listeningRootURL ?? Self.defaultListeningRootURL
    self.tasteRootURL = tasteRootURL ?? Self.defaultTasteRootURL
    self.hostName = hostName
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

  static var defaultTasteRootURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence", directoryHint: .isDirectory)
  }

  func playlistData() throws -> (LibrarySnapshot, PlaylistRoles, PlaylistIndex, Date, ArtistIdentity) {
    let (libraryIndex, generatedAt) = try index()
    let snapshotModified = cachedModifiedAt
    let rolesURL = tasteRootURL.appending(path: "playlist-roles.json")
    let modified = (try? FileManager.default.attributesOfItem(atPath: rolesURL.path)[.modificationDate]) as? Date
    let roles: PlaylistRoles
    if let cachedPlaylistRoles, cachedPlaylistRolesModifiedAt == modified {
      roles = cachedPlaylistRoles
    } else if let data = try? Self.readCoordinated(rolesURL), !data.isEmpty {
      roles = try PlaylistRolesCodec.decode(data)
      cachedPlaylistRoles = roles
      cachedPlaylistRolesModifiedAt = modified
    } else {
      roles = PlaylistRoles(updatedAt: .distantPast, playlists: [])
      cachedPlaylistRoles = roles
      cachedPlaylistRolesModifiedAt = modified
    }
    if let cachedPlaylistIndex, cachedPlaylistIndexRolesModifiedAt == modified,
      cachedPlaylistIndexSnapshotModifiedAt == snapshotModified {
      guard let snapshot = cachedSnapshot else { throw SnapshotUnavailable() }
      return (snapshot, roles, cachedPlaylistIndex, generatedAt, libraryIndex.artistIdentity)
    }
    guard let snapshot = cachedSnapshot else { throw SnapshotUnavailable() }
    let playlistIndex = PlaylistIndex(snapshot: snapshot, roles: roles, identity: libraryIndex.artistIdentity)
    cachedPlaylistIndex = playlistIndex
    cachedPlaylistIndexSnapshotModifiedAt = snapshotModified
    cachedPlaylistIndexRolesModifiedAt = modified
    return (snapshot, roles, playlistIndex, generatedAt, libraryIndex.artistIdentity)
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
    var heard: [String: [Date]] = [:]
    for play in log.plays {
      let title = SongTextNormalizer.libraryTitle(play.item.title)
      for credit in identity.credits(play.item.artist) where !credit.isEmpty {
        heard["\(credit)\u{0}\(title)", default: []].append(play.windowEnd)
      }
    }
    cachedHeardBySong = heard
    return log
  }

  func newMusicExposure() throws -> NewMusicExposureReadResult {
    let folder = tasteRootURL.appending(path: "exposure", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path) else { return NewMusicExposureReadResult(records: [], skippedLines: 0) }
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }
    var dataFiles: [Data] = []
    for url in files {
      guard let data = try Self.readCoordinated(url) else { continue }
      dataFiles.append(data)
    }
    return NewMusicExposureCodec.readFiles(dataFiles)
  }

  func tasteNotes() throws -> TasteNotesReadResult {
    guard FileManager.default.fileExists(atPath: tasteRootURL.path) else {
      return TasteNotesReadResult(notes: [], skippedLines: 0, filesRead: 0)
    }
    let files = try FileManager.default.contentsOfDirectory(at: tasteRootURL, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("notes") && $0.pathExtension == "jsonl" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let modified = Dictionary(uniqueKeysWithValues: files.compactMap { url in
      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return date.map { (url, $0) }
    })
    if let cachedTasteNotes, modified == cachedTasteNoteFiles { return cachedTasteNotes }
    let data = try files.compactMap { try Self.readCoordinated($0) }
    let result = TasteNotesCodec.readFiles(data)
    cachedTasteNotes = result
    cachedTasteNoteFiles = modified
    return result
  }

  func recordTasteNote(_ note: TasteNote) throws {
    try TasteNotesCodec.appendChatNote(note, host: hostName(), folder: tasteRootURL)
    cachedTasteNotes = nil
    cachedTasteNoteFiles = [:]
  }

  func recommendationLedger() throws -> RecommendationLedgerReadResult {
    let folder = tasteRootURL.appending(path: "recommendations", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path) else {
      let empty = RecommendationLedgerReadResult(batches: [], skippedLines: 0)
      cachedRecommendationLedger = empty
      cachedRecommendationFiles = [:]
      cachedRecommendationEvidence = nil
      return empty
    }
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let modified = Dictionary(uniqueKeysWithValues: files.compactMap { url in
      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return date.map { (url, $0) }
    })
    if let cachedRecommendationLedger, modified == cachedRecommendationFiles { return cachedRecommendationLedger }
    let data = try files.compactMap { try Self.readCoordinated($0) }
    let result = RecommendationLedgerCodec.readFiles(data)
    cachedRecommendationLedger = result
    cachedRecommendationFiles = modified
    cachedRecommendationEvidence = nil
    return result
  }

  func recommendationEvidenceIndex(identity: ArtistIdentity) throws -> RecommendationLedgerEvidenceIndex {
    if let cachedRecommendationEvidence, cachedRecommendationEvidence.identity == identity {
      return cachedRecommendationEvidence
    }
    let index = RecommendationLedgerEvidenceIndex(ledger: try recommendationLedger(), identity: identity)
    cachedRecommendationEvidence = index
    return index
  }

  func tasteNotesBySong(identity: ArtistIdentity) throws -> [String: [TasteNote]] {
    try tasteNotes().notes.reduce(into: [:]) { result, note in
      guard let artist = note.artist, let title = note.title, !title.isEmpty else { return }
      result[TasteIntelligence.songKey(artist: artist, title: title, identity: identity), default: []].append(note)
    }
  }

  func tasteCoverage(exposure: NewMusicExposureReadResult, now: Date, snapshotAt: Date) throws -> (MCPTasteCoverage, ListeningLog) {
    let exposureGaps = exposure.records.filter { if case .gap = $0 { true } else { false } }.count
    do {
      let log = try listeningLog(now: now)
      return (MCPTasteCoverage(exposureGaps: exposureGaps, exposureSkippedLines: exposure.skippedLines,
        listening: MCPListeningCoverage(log.coverage, now: now, period: .quarter),
        listeningStatus: nil, snapshotGeneratedAt: snapshotAt,
        snapshotAge: max(0, now.timeIntervalSince(snapshotAt))), log)
    } catch {
      let log = ListeningLog(streams: [], now: now)
      return (MCPTasteCoverage(exposureGaps: exposureGaps, exposureSkippedLines: exposure.skippedLines, listening: nil,
        listeningStatus: error is ListeningHistoryNotSetUp ? "not_set_up" : String(describing: error),
        snapshotGeneratedAt: snapshotAt, snapshotAge: max(0, now.timeIntervalSince(snapshotAt))), log)
    }
  }

  func heardDates(artist: String, title: String, identity: ArtistIdentity) -> [Date]? {
    guard cachedListeningLog != nil else { return nil }
    let normalizedTitle = SongTextNormalizer.libraryTitle(title)
    return identity.credits(artist).flatMap { cachedHeardBySong["\($0)\u{0}\(normalizedTitle)"] ?? [] }
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
    let aliasesModifiedAt = (try? FileManager.default.attributesOfItem(atPath: aliasesURL.path)[.modificationDate]) as? Date
    if let cachedIndex, let cachedGeneratedAt, cachedModifiedAt == modifiedAt,
      cachedAliasesModifiedAt == aliasesModifiedAt { return (cachedIndex, cachedGeneratedAt) }
    do {
      let snapshot = try LibrarySnapshotCodec.decode(Data(contentsOf: snapshotURL))
      let aliases = try aliasesModifiedAt == nil ? [:] : ArtistAliasesCodec.decode(Data(contentsOf: aliasesURL))
      let index = LibraryIndex(snapshot: snapshot, aliases: aliases)
      cachedIndex = index
      cachedSnapshot = snapshot
      cachedModifiedAt = modifiedAt
      cachedAliasesModifiedAt = aliasesModifiedAt
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

  func stage(_ payload: PlaylistToolPayload, recordedAt: Date) throws -> (name: String, trackCount: Int,
    dropped: [DroppedPlaylistTrack], ledgerRecorded: Bool, ledgerReason: String?) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = String(decoding: try encoder.encode(payload), as: UTF8.self)
    let contract = "VF-PLAYLIST: v1\n\(json)"
    let decoded = try PlaylistContract.decode(contract)
    guard !decoded.request.tracks.isEmpty else {
      throw PlaylistContractError.invalidShape("tracks must contain at least one track")
    }
    _ = try inbox.stage(contract, slug: payload.name, now: recordedAt)
    do {
      let (snapshot, _, playlistIndex, _, _) = try playlistData()
      let (index, _) = try self.index()
      let log = try? listeningLog(now: recordedAt)
      let noteKeys = Set((try? tasteNotesBySong(identity: index.artistIdentity).keys)
        ?? Dictionary<String, [TasteNote]>().keys)
      let recommendationEvidence = try recommendationEvidenceIndex(identity: index.artistIdentity)
      let familiarity = RecommendationFamiliarityIndex(snapshot: snapshot, index: index,
        playlistIndex: playlistIndex, listeningLog: log, tasteNoteKeys: noteKeys,
        recommendationEvidence: recommendationEvidence, recordedAt: recordedAt)
      let tracks = decoded.request.tracks.map { request in
        familiarity.evaluate(artist: request.artist, title: request.title, album: request.album, year: request.year)
      }
      let batch = RecommendationBatch(recordedAt: recordedAt, host: hostName(),
        playlist: decoded.request.name, tracks: tracks)
      let folder = tasteRootURL.appending(path: "recommendations", directoryHint: .isDirectory)
      try RecommendationLedgerCodec.append(batch, host: hostName(), folder: folder)
      cachedRecommendationLedger = nil
      cachedRecommendationFiles = [:]
      cachedRecommendationEvidence = nil
      return (decoded.request.name, decoded.request.tracks.count, decoded.droppedTracks, true, nil)
    } catch {
      return (decoded.request.name, decoded.request.tracks.count, decoded.droppedTracks, false,
        "ledger could not be read or written")
    }
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
    instructionHead + "\n\nFor taste questions, start with list_playlists. keepers are the strongest evidence and replay positions are ranks. Report evidence by role, not by counting playlists; don't infer taste from genre. sharedAccountEra play counts aren't Jon's alone. Stage discoveries with stage_playlist, because Vinyl Fever records which songs were new to Jon. Drop songs recommended before, unless Jon asks for them again.\n\n" + PlaylistContract.trackRules
  }()

  public static func make(
    snapshotURL: URL? = nil,
    inboxRoot: URL? = nil,
    listeningRootURL: URL? = nil,
    tasteRootURL: URL? = nil,
    hostName: @escaping @Sendable () -> String = { ListeningStore.liveHostName() },
    now: @escaping @Sendable () -> Date = { Date() }
  ) -> MCPServer {
    let context = LibraryMCPContext(snapshotURL: snapshotURL, inboxRoot: inboxRoot, listeningRootURL: listeningRootURL, tasteRootURL: tasteRootURL, hostName: hostName)
    let readOnly = MCPToolAnnotations(readOnly: true, openWorld: false)
    let overviewSchema = schema([:])
    let topArtistsSchema = schema(["by": enumField(["plays", "favorites", "recently_added"]), "period": enumField(["all_time", "7d", "30d", "90d"]), "limit": integerField])
    let topTracksSchema = schema(["by": enumField(["plays", "favorites", "recently_added", "recently_played"]), "period": enumField(["all_time", "7d", "30d", "90d"]), "limit": integerField])
    let recentListeningSchema = schema(["period": enumField(["24h", "7d", "30d", "90d"]), "limit": integerField], required: ["period"])
    let searchSchema = schema(["artist": stringField, "title": stringField, "album": stringField, "genre": stringField, "year_from": integerField, "year_to": integerField, "min_plays": integerField, "max_plays": integerField, "favorited": boolField, "availability": enumField(LibraryAvailability.allCases.map(\.rawValue)), "sort": enumField(["plays", "favorites", "recently_added", "recently_played", "title", "artist"]), "limit": integerField])
    let artistSchema = schema(["artist": stringField], required: ["artist"])
    let playlistListSchema = schema(["role": enumField(PlaylistRole.allCases.map(\.rawValue) + ["unlabeled"]), "limit": integerField])
    let playlistTracksSchema = schema(["name": stringField, "limit": integerField], required: ["name"])
    let keptPassedSchema = schema(["weeks": integerField])
    let tasteNotesSchema = schema(["artist": stringField, "title": stringField, "playlist": stringField,
      "period": enumField(["24h", "7d", "30d", "90d", "all_time"]), "limit": integerField])
    let recordTasteNoteSchema = schema(["note": .object(["type": .string("string"), "description": .string("Jon's words verbatim; do not paraphrase.")]),
      "artist": stringField, "title": stringField, "album": stringField, "playlist": stringField], required: ["note"])
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
      MCPTool(name: "check_tracks", description: "Check requested songs against Jon's library and playlist evidence, with unlabeled playlist count and listening history when available.", inputSchema: checksSchema, annotations: readOnly) { input in
        let p = try decode(CheckTracksPayload.self, from: input, schema: checksSchema)
        let (index, _) = try await context.index()
        let (snapshot, roles, playlistIndex, _, _) = try await context.playlistData()
        let recommendationEvidence = try? await context.recommendationEvidenceIndex(identity: index.artistIdentity)
        var listeningError: String?
        do { _ = try await context.listeningLog() }
        catch { listeningError = error is ListeningHistoryNotSetUp ? "not_set_up" : String(describing: error) }
        let tasteNotesBySong = try? await context.tasteNotesBySong(identity: index.artistIdentity)
        let calendar = Calendar.current
        var rows: [MCPCheckedTrack] = []
        for request in p.tracks.prefix(LibraryIndex.maximumCheckTracks) {
          let heard = await context.heardDates(artist: request.artist, title: request.title, identity: index.artistIdentity)
          let days = Set(heard?.map { calendar.startOfDay(for: $0) } ?? [])
          let evidence = playlistIndex.evidence(artist: request.artist, title: request.title, identity: index.artistIdentity,
            tracks: index.matchingTracks(artist: request.artist, title: request.title))
          let noteKey = TasteIntelligence.songKey(artist: request.artist, title: request.title, identity: index.artistIdentity)
          let notes = tasteNotesBySong.map { MCPNoteEvidence($0[noteKey] ?? []) }
          let check = index.checkTracks([(artist: request.artist, title: request.title)]).first!
          let recommended = recommendationEvidence?.forSong(artist: request.artist, title: request.title)
          rows.append(MCPCheckedTrack(check, evidence: evidence, heardDays: heard == nil ? nil : days.count,
            heardLast: heard?.max(), notes: notes, recommended: recommended)
          )
        }
        let unlabeled = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles).filter { $0.role == nil }.count
        return .json(MCPCheckResult(tracks: rows, unlabeledPlaylistCount: unlabeled, listening: listeningError))
      },
      MCPTool(name: "list_playlists", description: "List Jon's playlists and their taste roles. Unlabeled playlists are visible but are not evidence.", inputSchema: playlistListSchema, annotations: readOnly) { input in
        let p = try decode(PlaylistListPayload.self, from: input, schema: playlistListSchema)
        let (snapshot, roles, _, generatedAt, _) = try await context.playlistData()
        let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
        let unlabeledCount = resolved.filter { $0.role == nil }.count
        let filtered = resolved.filter { row in
          if let role = p.role {
            return role == "unlabeled" ? row.role == nil : row.role?.rawValue == role
          }
          return row.role != .ignore
        }
        let limit = max(1, min(p.limit ?? LibraryIndex.maximumLimit, LibraryIndex.maximumLimit))
        let inLibrary = Set(snapshot.tracks.map(\.persistentID))
        let rows = filtered.prefix(limit).map { row in
          MCPPlaylistSummary(name: row.playlist.name, role: row.role?.rawValue, folder: row.playlist.folder,
            kind: row.playlist.kind.rawValue, songCount: row.playlist.members.count,
            inLibraryCount: row.playlist.members.filter { inLibrary.contains($0) }.count)
        }
        return .json(MCPPlaylistList(playlists: Array(rows), unlabeledCount: unlabeledCount, matchingCount: filtered.count, snapshotGeneratedAt: generatedAt))
      },
      MCPTool(name: "playlist_tracks", description: "List tracks in a playlist in order; Replay positions are ranks.", inputSchema: playlistTracksSchema, annotations: readOnly) { input in
        let p = try decode(PlaylistTracksPayload.self, from: input, schema: playlistTracksSchema)
        let (snapshot, roles, playlistIndex, generatedAt, identity) = try await context.playlistData()
        let match = snapshot.playlists.first(where: { $0.name == p.name }) ?? snapshot.playlists.first(where: { $0.name.localizedCaseInsensitiveCompare(p.name) == .orderedSame })
        guard let match else { throw ArgumentError.unknown(p.name) }
        let tracksByID = Dictionary(snapshot.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
        let (libraryIndex, _) = try await context.index()
        var listeningError: String?
        do { _ = try await context.listeningLog() }
        catch { listeningError = error is ListeningHistoryNotSetUp ? "not_set_up" : String(describing: error) }
        let tasteNotesBySong = try? await context.tasteNotesBySong(identity: identity)
        let recommendationEvidence = try? await context.recommendationEvidenceIndex(identity: identity)
        var rows: [MCPPlaylistTrack] = []
        for (position, id) in match.members.enumerated() {
          let track = tracksByID[id]
          let outside = snapshot.outsideTracks[id]
          guard let title = track?.name ?? outside?.name, let artist = track?.artist ?? outside?.artist else { continue }
          let evidence = playlistIndex.evidence(artist: artist, title: title, identity: identity,
            tracks: libraryIndex.matchingTracks(artist: artist, title: title))
          let heard = await context.heardDates(artist: artist, title: title, identity: identity)
          let heardDays = heard.map { Set($0.map { Calendar.current.startOfDay(for: $0) }).count }
          let noteKey = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
          let notes = tasteNotesBySong.map { MCPNoteEvidence($0[noteKey] ?? []) }
          let check = libraryIndex.checkTracks([(artist: artist, title: title)]).first!
          let recommended = recommendationEvidence?.forSong(artist: artist, title: title)
          rows.append(MCPPlaylistTrack(position: position + 1, artist: artist, title: title,
            album: track?.album ?? outside?.album ?? "", year: track?.year ?? outside?.year,
            evidence: MCPPlaylistSongEvidence(evidence, check: check, heardDays: heardDays, heardLast: heard?.max(), notes: notes, recommended: recommended)))
        }
        let limit = max(1, min(p.limit ?? 100, 200))
        let unlabeled = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles).filter { $0.role == nil }.count
        return .json(MCPPlaylistTracks(name: match.name, role: PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles).first(where: { $0.playlist.persistentID == match.persistentID })?.role?.rawValue,
          tracks: Array(rows.prefix(limit)), unlabeledPlaylistCount: unlabeled, listening: listeningError, snapshotGeneratedAt: generatedAt))
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
      MCPTool(name: "kept_and_passed", description: "Show New Music weeks and classify each song as kept, passed, unheard, or pending using keeper playlists and listening history.", inputSchema: keptPassedSchema, annotations: readOnly) { input in
        let payload = try decode(KeptPassedPayload.self, from: input, schema: keptPassedSchema)
        let instant = now()
        let (snapshot, roles, _, generatedAt, _) = try await context.playlistData()
        let exposure = try await context.newMusicExposure()
        let weeks = exposure.records.compactMap { record -> NewMusicWeek? in if case let .week(value) = record { value } else { nil } }
        let (coverage, log) = try await context.tasteCoverage(exposure: exposure, now: instant, snapshotAt: generatedAt)
        let results = TasteIntelligence.keptAndPassed(weeks: weeks, snapshot: snapshot,
          roles: roles, log: log, now: instant, limit: payload.weeks ?? 8)
        return .json(MCPKeptAndPassed(weeks: results, coverage: coverage))
      },
      MCPTool(name: "taste_baselines", description: "Summarize Apple's kept-to-passed yield by New Music week and Jon's yearly Selections stick rate, with counts.", inputSchema: schema([:]), annotations: readOnly) { _ in
        let instant = now()
        let (snapshot, roles, _, generatedAt, _) = try await context.playlistData()
        let exposure = try await context.newMusicExposure()
        let weeks = exposure.records.compactMap { record -> NewMusicWeek? in if case let .week(value) = record { value } else { nil } }
        let (coverage, log) = try await context.tasteCoverage(exposure: exposure, now: instant, snapshotAt: generatedAt)
        let classified = TasteIntelligence.keptAndPassed(weeks: weeks, snapshot: snapshot,
          roles: roles, log: log, now: instant, limit: max(1, weeks.count))
        return .json(MCPBaselines(baselines: TasteIntelligence.baselines(weeks: classified, snapshot: snapshot), coverage: coverage))
      },
      MCPTool(name: "taste_notes", description: "Read Jon's taste notes verbatim. Time-only notes include nearby listening-log candidates when available.", inputSchema: tasteNotesSchema, annotations: readOnly) { input in
        let payload = try decode(TasteNotesPayload.self, from: input, schema: tasteNotesSchema)
        let instant = now()
        let period = try payload.period.map { value -> TasteNotePeriod in
          guard let period = TasteNotePeriod(rawValue: value) else { throw ArgumentError.invalidEnum(value) }
          return period
        } ?? .allTime
        let result = try await context.tasteNotes()
        var log: ListeningLog?
        var listeningError: String?
        do { log = try await context.listeningLog(now: instant) }
        catch { listeningError = error is ListeningHistoryNotSetUp ? "not_set_up" : String(describing: error) }
        let matches = result.notes.filter { note in
          guard period.contains(note.notedAt, now: instant) else { return false }
          if let artist = payload.artist, note.artist?.localizedCaseInsensitiveContains(artist) != true { return false }
          if let title = payload.title, note.title?.localizedCaseInsensitiveContains(title) != true { return false }
          if let playlist = payload.playlist, note.playlist?.localizedCaseInsensitiveContains(playlist) != true { return false }
          return true
        }
        let limit = max(1, min(payload.limit ?? 50, 100))
        let rows = matches.prefix(limit).map { note -> MCPTasteNote in
          let candidates = note.isTimeOnly ? log.map { TasteNoteCandidates.forNote(note, log: $0) } : nil
          return MCPTasteNote(note, candidates: candidates)
        }
        let listeningCoverage = log.map { MCPListeningCoverage($0.coverage, now: instant, period: .quarter) }
        return .json(MCPTasteNotes(notes: Array(rows), coverage: MCPTasteNotesCoverage(
          filesRead: result.filesRead, skippedLines: result.skippedLines,
          listening: listeningCoverage, listeningStatus: listeningError)))
      },
      MCPTool(name: "record_taste_note", description: "Record Jon's words verbatim about a song or playlist in Vinyl Fever's chat-note log. Never writes the VF Note shortcut file.", inputSchema: recordTasteNoteSchema,
        annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
        let payload = try decode(RecordTasteNotePayload.self, from: input, schema: recordTasteNoteSchema)
        guard !payload.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ArgumentError.invalidShape("note must not be empty")
        }
        let hasSong = payload.artist != nil || payload.title != nil || payload.album != nil
        let hasPlaylist = payload.playlist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasSong != hasPlaylist else { throw ArgumentError.invalidShape("provide either artist and title, or playlist") }
        let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasSong || (artist?.isEmpty == false && title?.isEmpty == false) else {
          throw ArgumentError.invalidShape("song notes require artist and title")
        }
        let note = TasteNote(notedAt: now(), note: payload.note, source: "chat",
          title: title, artist: artist, album: payload.album, playlist: payload.playlist)
        try await context.recordTasteNote(note)
        return .json(MCPRecordedTasteNote(recorded: true, notedAt: note.notedAt, source: note.source))
      },
      MCPTool(name: "stage_playlist", description: "Stage a playlist proposal for Jon to review in Vinyl Fever; it does not change Apple Music.", inputSchema: stageSchema, annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
        let payload = try decode(PlaylistToolPayload.self, from: input, schema: stageSchema)
        let staged = try await context.stage(payload, recordedAt: now())
        let json = MCPToolResult.json(StagedPlaylistResult(staged: true, name: staged.name, trackCount: staged.trackCount,
          dropped: staged.dropped, ledgerRecorded: staged.ledgerRecorded, ledgerReason: staged.ledgerReason))
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

private struct KeptPassedPayload: Decodable, Sendable { var weeks: Int? }

private struct MCPPlaylistSummary: Encodable {
  var name: String; var role: String?; var folder: String?; var kind: String
  var songCount: Int; var inLibraryCount: Int
}
private struct MCPPlaylistList: Encodable {
  var playlists: [MCPPlaylistSummary]; var unlabeledCount: Int; var matchingCount: Int; var snapshotGeneratedAt: Date
}
private struct MCPPlaylistTrack: Encodable {
  var position: Int; var artist: String; var title: String; var album: String; var year: Int?
  var evidence: MCPPlaylistSongEvidence
}
private struct MCPPlaylistTracks: Encodable {
  var name: String; var role: String?; var tracks: [MCPPlaylistTrack]; var unlabeledPlaylistCount: Int; var listening: String?; var snapshotGeneratedAt: Date
}
private struct MCPCheckResult: Encodable { var tracks: [MCPCheckedTrack]; var unlabeledPlaylistCount: Int; var listening: String? }
private struct MCPCheckedTrack: Encodable {
  var artist: String; var title: String; var owned: Bool; var plays: Int; var versionCount: Int
  var favorited: Bool; var lastPlayed: Date?; var availability: [LibraryAvailability]
  var uploadedAlbums: [String]; var playlists: [String: [String]]; var playlistCounts: [String: Int]
  var disliked: Bool; var sharedAccountEra: Bool; var heardDays: Int?; var heardLast: Date?
  var notes: MCPNoteEvidence?
  var recommended: RecommendationEvidence?

  init(_ check: LibraryTrackCheck, evidence: PlaylistSongEvidence, heardDays: Int?, heardLast: Date?, notes: MCPNoteEvidence?, recommended: RecommendationEvidence?) {
    artist = check.artist; title = check.title; owned = check.owned; plays = check.plays
    versionCount = check.versionCount; favorited = check.favorited; lastPlayed = check.lastPlayed
    availability = check.availability; uploadedAlbums = check.uploadedAlbums
    playlists = evidence.playlists; playlistCounts = evidence.playlistCounts
    disliked = evidence.disliked; sharedAccountEra = evidence.sharedAccountEra
    self.heardDays = heardDays; self.heardLast = heardLast
    self.notes = notes; self.recommended = recommended
  }

  private enum CodingKeys: String, CodingKey {
    case artist, title, owned, plays, versionCount, favorited, lastPlayed, availability, uploadedAlbums
    case playlists, playlistCounts, disliked, sharedAccountEra, heardDays, heardLast, notes, recommended
  }
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(artist, forKey: .artist); try values.encode(title, forKey: .title)
    try values.encode(owned, forKey: .owned); try values.encode(plays, forKey: .plays)
    try values.encode(versionCount, forKey: .versionCount); try values.encode(favorited, forKey: .favorited)
    try values.encodeIfPresent(lastPlayed, forKey: .lastPlayed); try values.encode(availability, forKey: .availability)
    try values.encode(uploadedAlbums, forKey: .uploadedAlbums); try values.encode(playlists, forKey: .playlists)
    try values.encode(playlistCounts, forKey: .playlistCounts); try values.encode(disliked, forKey: .disliked)
    try values.encode(sharedAccountEra, forKey: .sharedAccountEra)
    try values.encodeIfPresent(heardDays, forKey: .heardDays); try values.encodeIfPresent(heardLast, forKey: .heardLast)
    try values.encodeIfPresent(notes, forKey: .notes)
    try values.encodeIfPresent(recommended, forKey: .recommended)
  }
}
private struct MCPPlaylistSongEvidence: Encodable {
  var playlists: [String: [String]]; var playlistCounts: [String: Int]
  var disliked: Bool; var sharedAccountEra: Bool; var heardDays: Int?; var heardLast: Date?
  var owned: Bool; var plays: Int; var favorited: Bool; var lastPlayed: Date?
  var availability: [LibraryAvailability]
  var notes: MCPNoteEvidence?
  var recommended: RecommendationEvidence?
  init(_ value: PlaylistSongEvidence, check: LibraryTrackCheck, heardDays: Int?, heardLast: Date?, notes: MCPNoteEvidence?, recommended: RecommendationEvidence?) {
    playlists = value.playlists; playlistCounts = value.playlistCounts; disliked = value.disliked
    sharedAccountEra = value.sharedAccountEra; self.heardDays = heardDays; self.heardLast = heardLast
    owned = check.owned; plays = check.plays; favorited = check.favorited
    lastPlayed = check.lastPlayed; availability = check.availability
    self.notes = notes; self.recommended = recommended
  }
  private enum CodingKeys: String, CodingKey { case playlists, playlistCounts, disliked, sharedAccountEra, heardDays, heardLast, owned, plays, favorited, lastPlayed, availability, notes, recommended }
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(playlists, forKey: .playlists); try values.encode(playlistCounts, forKey: .playlistCounts)
    try values.encode(disliked, forKey: .disliked); try values.encode(sharedAccountEra, forKey: .sharedAccountEra)
    try values.encodeIfPresent(heardDays, forKey: .heardDays); try values.encodeIfPresent(heardLast, forKey: .heardLast)
    try values.encode(owned, forKey: .owned); try values.encode(plays, forKey: .plays)
    try values.encode(favorited, forKey: .favorited); try values.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
    try values.encode(availability, forKey: .availability)
    try values.encodeIfPresent(notes, forKey: .notes)
    try values.encodeIfPresent(recommended, forKey: .recommended)
  }
}

private struct StagedPlaylistResult: Encodable {
  struct Dropped: Encodable { var index: Int; var artist: String; var title: String }
  var staged: Bool; var name: String; var trackCount: Int; var dropped: [Dropped]
  var ledgerRecorded: Bool; var ledgerReason: String?
  init(staged: Bool, name: String, trackCount: Int, dropped: [DroppedPlaylistTrack], ledgerRecorded: Bool, ledgerReason: String?) {
    self.staged = staged; self.name = name; self.trackCount = trackCount
    self.dropped = dropped.map { Dropped(index: $0.index, artist: $0.artist, title: $0.title) }
    self.ledgerRecorded = ledgerRecorded; self.ledgerReason = ledgerReason
  }
}

private enum ArgumentError: LocalizedError {
  case expectedObject
  case unknown(String)
  case invalidEnum(String)
  case periodRanking
  case invalidShape(String)
  var errorDescription: String? {
    switch self {
    case .expectedObject: "Expected an object of tool arguments."
    case .unknown(let key): "Unknown argument \"\(key)\"."
    case .invalidEnum(let value): "Unrecognized value \"\(value)\"."
    case .periodRanking: "Only by: plays is allowed with a listening period."
    case .invalidShape(let detail): "Invalid arguments: \(detail)."
    }
  }
}
