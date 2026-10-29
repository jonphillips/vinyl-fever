import Foundation
import LLMHandoffKit
import MCPServerKit
import VinylFeverListening

private struct PlaylistToolPayload: Decodable, Sendable {
  struct Track: Decodable, Sendable {
    var artist: String
    var title: String
    var album: String?
    var year: Int?
    var why: String?
    var like: [RecommendationLikeInput]?
    var hasYear: Bool
    enum CodingKeys: String, CodingKey { case artist, title, album, year, why, like }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      artist = try values.decode(String.self, forKey: .artist)
      title = try values.decode(String.self, forKey: .title)
      album = try values.decodeIfPresent(String.self, forKey: .album)
      year = try values.decodeIfPresent(Int.self, forKey: .year)
      why = try values.decodeIfPresent(String.self, forKey: .why)
      like = try values.decodeIfPresent([RecommendationLikeInput].self, forKey: .like)
      hasYear = values.contains(.year)
    }
  }
  var name: String
  var description: String?
  var request: String?
  var tracks: [Track]
}
private struct RecordNewMusicPicksPayload: Decodable, Sendable {
  struct Song: Decodable, Sendable { var artist: String; var title: String }
  var songs: [Song]
}

private struct RecommendationLikeInput: Codable, Sendable {
  var artist: String
  var title: String
  var from: String?
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
  var kind: String?; var answers: String?; var skipped: Bool?
  var about: TasteNote.About?
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
private struct MCPOverview: Encodable {
  var overview: LibraryOverview
  var connector: ConnectorBuildStamp

  init(_ overview: LibraryOverview, connector: ConnectorBuildStamp) {
    self.overview = overview
    self.connector = connector
  }

  private enum CodingKeys: String, CodingKey { case connector }

  func encode(to encoder: Encoder) throws {
    try overview.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(connector, forKey: .connector)
  }
}
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
private struct MCPRecommendationOutcomes: Encodable { var outcomes: RecommendationOutcomes; var coverage: MCPTasteCoverage }
private struct MCPRecordPicks: Encodable { var recorded: Bool; var recordedAt: Date; var songCount: Int }
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
  var kind: String
  var id: String?
  var answers: String?
  var skipped: Bool?
  var about: TasteNote.About?
  var answer: MCPTasteAnswer?
  var firstHearing: Bool?
  var candidates: [TasteNoteSongCandidate]?

  init(_ value: TasteNote, answer: MCPTasteAnswer? = nil, candidates: [TasteNoteSongCandidate]? = nil) {
    title = value.title?.isEmpty == true ? nil : value.title
    artist = value.artist?.isEmpty == true ? nil : value.artist
    album = value.album; playlist = value.playlist; notedAt = value.notedAt
    note = value.note; source = value.source; firstHearing = value.firstHearing
    kind = value.resolvedKind; id = value.id; answers = value.answers; skipped = value.skipped; about = value.about
    self.answer = answer
    self.candidates = candidates
  }
}
private struct MCPTasteAnswer: Encodable {
  var note: String
  var notedAt: Date
  var skipped: Bool
  init(_ value: TasteNote) { note = value.note; notedAt = value.notedAt; skipped = value.skipped ?? false }
}
private struct MCPOpenQuestion: Encodable {
  var id: String
  var note: String
  var about: TasteNote.About?
  var age: TimeInterval
  init?(_ value: TasteNote, now: Date) {
    guard let id = value.id else { return nil }
    self.id = id; note = value.note; about = value.about; age = max(0, now.timeIntervalSince(value.notedAt))
  }
}
private struct MCPTasteNotes: Encodable { var openQuestions: [MCPOpenQuestion]; var notes: [MCPTasteNote]; var coverage: MCPTasteNotesCoverage }
private struct MCPRecordedTasteNote: Encodable { var recorded: Bool; var notedAt: Date; var source: String; var id: String }
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
  private var cachedExposure: NewMusicExposureReadResult?
  private var cachedExposureFiles: [URL: Date] = [:]
  private var hasCachedExposure = false
  private var cachedRecommendationLedger: RecommendationLedgerReadResult?
  private var cachedRecommendationFiles: [URL: Date] = [:]
  private var cachedRecommendationEvidence: RecommendationLedgerEvidenceIndex?
  private var cachedLatestRecommendationOutcomes: [String: String]?

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
      if cachedPlaylistRolesModifiedAt != modified { invalidateLatestRecommendationOutcomes() }
      roles = try PlaylistRolesCodec.decode(data)
      cachedPlaylistRoles = roles
      cachedPlaylistRolesModifiedAt = modified
    } else {
      if cachedPlaylistRolesModifiedAt != modified { invalidateLatestRecommendationOutcomes() }
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
    guard !files.isEmpty else {
      if cachedListeningLog != nil {
        cachedListeningLog = nil
        cachedListeningFiles = [:]
        cachedHeardBySong = [:]
        invalidateLatestRecommendationOutcomes()
      }
      throw ListeningHistoryNotSetUp()
    }
    let modified = Dictionary(uniqueKeysWithValues: files.compactMap { url in
      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return date.map { (url, $0) }
    })
    if let cachedListeningLog, modified == cachedListeningFiles,
      identity == cachedListeningIdentity { return cachedListeningLog }
    let streams = try files.map { try Self.readCoordinated($0) }.compactMap { $0 }
    let log = try ListeningLog(jsonlStreams: streams, now: now, identity: identity)
    invalidateLatestRecommendationOutcomes()
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
    let files = FileManager.default.fileExists(atPath: folder.path)
      ? try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "jsonl" }
      : []
    let modified = Dictionary(uniqueKeysWithValues: files.compactMap { url in
      let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return date.map { (url, $0) }
    })
    if hasCachedExposure, modified == cachedExposureFiles, let cachedExposure { return cachedExposure }
    var dataFiles: [Data] = []
    for url in files {
      guard let data = try Self.readCoordinated(url) else { continue }
      dataFiles.append(data)
    }
    let result = NewMusicExposureCodec.readFiles(dataFiles)
    cachedExposure = result
    cachedExposureFiles = modified
    hasCachedExposure = true
    invalidateLatestRecommendationOutcomes()
    return result
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
      invalidateLatestRecommendationOutcomes()
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
    invalidateLatestRecommendationOutcomes()
    return result
  }

  func curationChanges() -> [CurationChange] {
    let folder = tasteRootURL.appending(path: "curation", directoryHint: .isDirectory)
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return files.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      .flatMap { url -> [CurationChange] in
        guard let data = try? Self.readCoordinated(url) else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { try? decoder.decode(CurationChange.self, from: Data($0.utf8)) }
      }
  }

  func recordNewMusicPicks(_ songs: [(artist: String, title: String)], recordedAt: Date) throws -> Int {
    guard !songs.isEmpty else { throw ArgumentError.invalidShape("songs must contain at least one pick") }
    let weeks = try newMusicExposure().records.compactMap { record -> NewMusicWeek? in
      if case let .week(week) = record { week } else { nil }
    }
    guard let week = weeks.max(by: { $0.lastModifiedDate < $1.lastModifiedDate }) else {
      throw ArgumentError.invalidShape("there is no saved New Music week")
    }
    let (snapshot, _, _, _, identity) = try playlistData()
    let available = Set(week.tracks.map { TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) })
    for song in songs where !available.contains(TasteIntelligence.songKey(artist: song.artist, title: song.title, identity: identity)) {
      throw ArgumentError.invalidShape("\(song.artist) — \(song.title) isn't in the latest saved New Music week")
    }
    let heardKeys: Set<String>
    if let log = try? listeningLog(now: recordedAt) {
      heardKeys = Set(log.plays.filter { $0.windowEnd <= recordedAt }.map {
        TasteIntelligence.songKey(artist: $0.item.artist, title: $0.item.title, identity: identity)
      })
    } else { heardKeys = [] }
    let picked = Set(songs.map { TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) })
    let tracks = week.tracks.map { track in
      let key = TasteIntelligence.songKey(artist: track.artist, title: track.title, identity: identity)
      return RecommendationTrack(artist: track.artist, title: track.title, album: track.album,
        year: track.releaseDate.flatMap { Int($0.prefix(4)) }, familiar: false, reasons: [], artistKnown: false,
        heardBeforePick: heardKeys.contains(key), picked: picked.contains(key))
    }
    let batch = RecommendationBatch(kind: "new-music-picks", recordedAt: recordedAt,
      host: hostName(), playlist: nil, tracks: tracks,
      coverage: RecommendationCoverage(listening: (try? listeningLog(now: recordedAt)) != nil,
        notes: (try? tasteNotes()) != nil, snapshotAt: snapshot.generatedAt),
      batchDate: week.lastModifiedDate)
    try RecommendationLedgerCodec.append(batch, host: hostName(), folder: tasteRootURL.appending(path: "recommendations", directoryHint: .isDirectory))
    cachedRecommendationLedger = nil; cachedRecommendationFiles = [:]; cachedRecommendationEvidence = nil
    invalidateLatestRecommendationOutcomes()
    return songs.count
  }

  func recommendationEvidenceIndex(identity: ArtistIdentity) throws -> RecommendationLedgerEvidenceIndex {
    let ledger = try recommendationLedger()
    if let cachedRecommendationEvidence, cachedRecommendationEvidence.identity == identity {
      return cachedRecommendationEvidence
    }
    let index = RecommendationLedgerEvidenceIndex(ledger: ledger, identity: identity)
    cachedRecommendationEvidence = index
    return index
  }

  func tasteNotesBySong(_ notes: [TasteNote], identity: ArtistIdentity) -> [String: [TasteNote]] {
    notes.reduce(into: [:]) { result, note in
      guard note.resolvedKind == "note" else { return }
      guard let artist = note.artist, let title = note.title, !title.isEmpty else { return }
      result[TasteIntelligence.songKey(artist: artist, title: title, identity: identity), default: []].append(note)
    }
  }

  func tasteNotesBySong(identity: ArtistIdentity) throws -> [String: [TasteNote]] {
    tasteNotesBySong(try tasteNotes().notes, identity: identity)
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

  func recommendationOutcomes(now: Date, limit: Int) throws -> (RecommendationOutcomes, MCPTasteCoverage) {
    let (snapshot, roles, _, generatedAt, _) = try playlistData()
    let exposure = try newMusicExposure()
    let (coverage, log) = try tasteCoverage(exposure: exposure, now: now, snapshotAt: generatedAt)
    let ledger = (try? recommendationLedger()) ?? RecommendationLedgerReadResult(batches: [], skippedLines: 0)
    let weeks = exposure.records.compactMap { record -> NewMusicWeek? in
      if case let .week(week) = record { return week }
      return nil
    }
    let outcomes = TasteIntelligence.recommendationOutcomes(ledger: ledger, weeks: weeks,
      snapshot: snapshot, roles: roles, log: log, now: now, limit: limit)
    return (outcomes, coverage)
  }

  func latestRecommendationOutcomes(now: Date) throws -> [String: String] {
    if let cachedLatestRecommendationOutcomes { return cachedLatestRecommendationOutcomes }
    let (outcomes, _) = try recommendationOutcomes(now: now, limit: 50)
    let identity = try index().0.artistIdentity
    var latest: [String: String] = [:]
    for batch in outcomes.batches {
      guard batch.kind == "staged-playlist" else { continue }
      for song in batch.songs {
        guard let classification = song.classification else { continue }
        let key = TasteIntelligence.songKey(artist: song.artist, title: song.title, identity: identity)
        if latest[key] == nil { latest[key] = classification.rawValue }
      }
    }
    cachedLatestRecommendationOutcomes = latest
    return latest
  }

  private func invalidateLatestRecommendationOutcomes() {
    cachedLatestRecommendationOutcomes = nil
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
    invalidateLatestRecommendationOutcomes()
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
    dropped: [DroppedPlaylistTrack], ledgerRecorded: Bool, ledgerReason: String?, missingYear: [String],
    unverifiedReferences: [String], truncated: Bool) {
    struct ContractTrack: Encodable { var artist: String; var title: String; var album: String?; var year: Int? }
    struct ContractPayload: Encodable { var name: String; var description: String?; var tracks: [ContractTrack] }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let contractPayload = ContractPayload(name: payload.name, description: payload.description,
      tracks: payload.tracks.map { ContractTrack(artist: $0.artist, title: $0.title, album: $0.album, year: $0.year) })
    let json = String(decoding: try encoder.encode(contractPayload), as: UTF8.self)
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
      let notesBySong = try? tasteNotesBySong(identity: index.artistIdentity)
      let noteKeys = Set(notesBySong?.keys ?? Dictionary<String, [TasteNote]>().keys)
      let recommendationEvidence = try recommendationEvidenceIndex(identity: index.artistIdentity)
      let familiarity = RecommendationFamiliarityIndex(snapshot: snapshot, index: index,
        playlistIndex: playlistIndex, listeningLog: log, tasteNoteKeys: noteKeys,
        recommendationEvidence: recommendationEvidence, recordedAt: recordedAt)
      let survivingInputs = decoded.request.tracks.map { request in
        payload.tracks.first { $0.artist.localizedCaseInsensitiveCompare(request.artist) == .orderedSame &&
          $0.title.localizedCaseInsensitiveCompare(request.title) == .orderedSame }
      }
      let tracks = decoded.request.tracks.map { request in
        familiarity.evaluate(artist: request.artist, title: request.title, album: request.album, year: request.year)
      }
      var truncated = false
      let references = survivingInputs.map { input -> [RecommendationLike] in
        guard let request = input else { return [] }
        let likes: [RecommendationLikeInput] = request.like ?? []
        let refs = likes.prefix(3).map { (like: RecommendationLikeInput) -> RecommendationLike in
          let from: String? = like.from?.trimmingCharacters(in: .whitespacesAndNewlines)
          let matchingPlaylist = from.flatMap { (name: String) -> LibraryPlaylist? in
            snapshot.playlists.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
          }
          let found: String
          let matchingTracks: [LibraryTrack] = index.matchingTracks(artist: like.artist, title: like.title)
          var matchingIDs = Set(matchingTracks.map(\.persistentID))
          let likeKey = TasteIntelligence.songKey(artist: like.artist, title: like.title, identity: index.artistIdentity)
          for (persistentID, outsideTrack) in snapshot.outsideTracks {
            let outsideKey = TasteIntelligence.songKey(artist: outsideTrack.artist, title: outsideTrack.name,
              identity: index.artistIdentity)
            if outsideKey == likeKey { matchingIDs.insert(persistentID) }
          }
          let isInCitedPlaylist = matchingPlaylist.map { playlist in
            playlist.members.contains { matchingIDs.contains($0) }
          } ?? false
          if isInCitedPlaylist {
            found = "playlist"
          } else if !matchingTracks.isEmpty || !matchingIDs.isEmpty { found = "library" }
          else { found = "none" }
          return RecommendationLike(artist: like.artist, title: like.title, from: like.from, found: found)
        }
        return refs
      }
      let enriched = zip(tracks, survivingInputs).enumerated().map { index, pair -> RecommendationTrack in
        let (track, input) = pair
        var result = track
        if let why = input?.why {
          if why.count > 300 { truncated = true }
          result.why = String(why.prefix(300))
        }
        result.like = references[index]
        return result
      }
      if let request = payload.request, request.count > 500 { truncated = true }
      let batch = RecommendationBatch(recordedAt: recordedAt, host: hostName(),
        playlist: decoded.request.name, tracks: enriched, request: payload.request.map { String($0.prefix(500)) },
        coverage: RecommendationCoverage(listening: log != nil, notes: notesBySong != nil, snapshotAt: snapshot.generatedAt))
      let folder = tasteRootURL.appending(path: "recommendations", directoryHint: .isDirectory)
      try RecommendationLedgerCodec.append(batch, host: hostName(), folder: folder)
      cachedRecommendationLedger = nil
      cachedRecommendationFiles = [:]
      cachedRecommendationEvidence = nil
      invalidateLatestRecommendationOutcomes()
      if payload.tracks.contains(where: { ($0.like?.count ?? 0) > 3 }) { truncated = true }
      let unverified = enriched.flatMap { (track: RecommendationTrack) -> [String] in
        let likes: [RecommendationLike] = track.like ?? []
        return likes.filter { ($0.found != "playlist" && $0.from != nil) || $0.found == "none" }
          .map { "\(track.artist) — \(track.title): \($0.artist) — \($0.title)" }
      }
      let missingYear = decoded.request.tracks.filter { $0.year == nil }.map { "\($0.artist) — \($0.title)" }
      return (decoded.request.name, decoded.request.tracks.count, decoded.droppedTracks, true, nil, missingYear, unverified, truncated)
    } catch {
      return (decoded.request.name, decoded.request.tracks.count, decoded.droppedTracks, false,
        "ledger could not be read or written", [], [], false)
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
    instructionHead + "\n\nFor taste questions, start with list_playlists. keepers are the strongest evidence and replay positions are ranks. Report evidence by role, not by counting playlists; don't infer taste from genre. sharedAccountEra play counts aren't Jon's alone. Stage discoveries with stage_playlist, because Vinyl Fever records which songs were new to Jon. Give every discovery its original release year, Jon's request as request, a one-sentence why, and up to three songs in `like`. Cite only songs read from a Vinyl Fever tool in this conversation, and name the playlist you read each one from in `from`. Drop songs recommended before, unless Jon asks for them again. When Jon asks which New Music songs he'll keep, read kept_and_passed, choose before he listens, then call record_new_music_picks. `list_playlists` and `check_tracks` return `openQuestions` when there are any. In a taste conversation, ask at most one without waiting to be asked, and only when it bears on what Jon is doing. Record his reply word for word as `note` with the question's id in `answers`. Record 'skip' or 'not now' the same way, with `skipped: true`. When you stage, show Jon each song's year and why. If the result lists `missingYear` or `unverifiedReferences`, tell Jon which songs. Don't stage the same batch again: a second staging marks every song as recommended before. Record a new question when evidence leaves a meaningful contrast unresolved, even if Jon isn't there; ask only when the answer could change your next recommendation, cite the evidence, and never ask what tools can tell you.\n\n" + PlaylistContract.trackRules
  }()

  public static func make(
    snapshotURL: URL? = nil,
    inboxRoot: URL? = nil,
    listeningRootURL: URL? = nil,
    tasteRootURL: URL? = nil,
    buildStamp: ConnectorBuildStamp = ConnectorBuildStamp.fromMainAppBundle(),
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
    let recommendationOutcomesSchema = schema(["batches": integerField])
    let recordPicksSchema = schema(["songs": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])])], required: ["songs"])
    let tasteNotesSchema = schema(["artist": stringField, "title": stringField, "playlist": stringField,
      "period": enumField(["24h", "7d", "30d", "90d", "all_time"]), "limit": integerField])
    let recordTasteNoteSchema = schema(["note": .object(["type": .string("string"), "description": .string("Jon's words verbatim; do not paraphrase.")]),
      "artist": stringField, "title": stringField, "album": stringField, "playlist": stringField,
      "kind": enumField(["note", "question", "answer"]), "answers": stringField, "skipped": .object(["type": .string("boolean")]),
      "about": .object(["type": .string("object"), "properties": .object([
        "songs": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])]),
        "playlists": .object(["type": .string("array"), "items": stringField])])])], required: ["note"])
    let checksSchema = schema(["tracks": .object(["type": .string("array"), "maxItems": .integer(LibraryIndex.maximumCheckTracks), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField]), "required": .array([.string("artist"), .string("title")])])])], required: ["tracks"])
    let likeSchema = MCPValue.object(["type": .string("array"), "maxItems": .integer(3), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField, "from": stringField]), "required": .array([.string("artist"), .string("title")])])])
    let stageYearField = MCPValue.object(["type": .array([.string("integer"), .string("null")]),
      "description": .string("The song's original release year, not a reissue's or compilation's. Use null only when you can't verify it.")])
    let stageSchema = schema(["name": stringField, "description": .object(["type": .string("string"), "description": .string(stageDescriptionGuidance)]), "request": stringField, "tracks": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object(["artist": stringField, "title": stringField, "album": stringField, "year": stageYearField, "why": stringField, "like": likeSchema]), "required": .array([.string("artist"), .string("title"), .string("year")])])])], required: ["name", "tracks"])
    return MCPServer(name: "Vinyl Fever", version: "1.0.0", instructions: instructions, tools: [
      MCPTool(name: "library_overview", description: "Summarize Jon's Apple Music library, including track, artist, album, genre and decade counts, plus the connector's build stamp (commit, dirty state, and build time).", inputSchema: overviewSchema, annotations: readOnly) { _ in
        return .json(MCPOverview(try await context.overview(), connector: buildStamp))
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
        let requests = Array(p.tracks.prefix(LibraryIndex.maximumCheckTracks))
        let recommendedRows = requests.map { recommendationEvidence?.forSong(artist: $0.artist, title: $0.title) }
        var listeningError: String?
        do { _ = try await context.listeningLog() }
        catch { listeningError = error is ListeningHistoryNotSetUp ? "not_set_up" : String(describing: error) }
        let recommendationOutcomes = recommendedRows.contains(where: { $0 != nil })
          ? try? await context.latestRecommendationOutcomes(now: now()) : nil
        let tasteNoteResult = try? await context.tasteNotes()
        let tasteNotesBySong: [String: [TasteNote]]?
        if let tasteNoteResult {
          tasteNotesBySong = await context.tasteNotesBySong(tasteNoteResult.notes, identity: index.artistIdentity)
        } else {
          tasteNotesBySong = nil
        }
        let instant = now()
        let openQuestions = tasteNoteResult.map {
          TasteNotesCodec.openQuestions(in: $0.notes, now: instant).compactMap { MCPOpenQuestion($0, now: instant) }
        }.flatMap { $0.isEmpty ? nil : $0 }
        let calendar = Calendar.current
        var rows: [MCPCheckedTrack] = []
        for (request, ledgerEvidence) in zip(requests, recommendedRows) {
          let heard = await context.heardDates(artist: request.artist, title: request.title, identity: index.artistIdentity)
          let days = Set(heard?.map { calendar.startOfDay(for: $0) } ?? [])
          let evidence = playlistIndex.evidence(artist: request.artist, title: request.title, identity: index.artistIdentity,
            tracks: index.matchingTracks(artist: request.artist, title: request.title))
          let noteKey = TasteIntelligence.songKey(artist: request.artist, title: request.title, identity: index.artistIdentity)
          let notes = tasteNotesBySong.map { MCPNoteEvidence($0[noteKey] ?? []) }
          let check = index.checkTracks([(artist: request.artist, title: request.title)]).first!
          var recommended = ledgerEvidence
          let recommendationKey = TasteIntelligence.songKey(artist: request.artist, title: request.title, identity: index.artistIdentity)
          recommended?.latestOutcome = recommendationOutcomes?[recommendationKey]
          rows.append(MCPCheckedTrack(check, evidence: evidence, heardDays: heard == nil ? nil : days.count,
            heardLast: heard?.max(), notes: notes, recommended: recommended)
          )
        }
        let unlabeled = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles).filter { $0.role == nil }.count
        return .json(MCPCheckResult(tracks: rows, unlabeledPlaylistCount: unlabeled,
          listening: listeningError, openQuestions: openQuestions))
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
        let instant = now()
        let openQuestions = (try? await context.tasteNotes()).map {
          TasteNotesCodec.openQuestions(in: $0.notes, now: instant).compactMap { MCPOpenQuestion($0, now: instant) }
        }.flatMap { $0.isEmpty ? nil : $0 }
        return .json(MCPPlaylistList(playlists: Array(rows), unlabeledCount: unlabeledCount, matchingCount: filtered.count,
          snapshotGeneratedAt: generatedAt, openQuestions: openQuestions))
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
        let references = match.members.enumerated().compactMap { position, id -> (position: Int, id: String,
          track: LibraryTrack?, outside: LibraryOutsideTrack?, title: String, artist: String)? in
          let track = tracksByID[id]
          let outside = snapshot.outsideTracks[id]
          guard let title = track?.name ?? outside?.name, let artist = track?.artist ?? outside?.artist else { return nil }
          return (position, id, track, outside, title, artist)
        }
        let recommendedRows = references.map { row in recommendationEvidence?.forSong(artist: row.artist, title: row.title) }
        let recommendationOutcomes = recommendedRows.contains(where: { $0 != nil })
          ? try? await context.latestRecommendationOutcomes(now: now()) : nil
        var rows: [MCPPlaylistTrack] = []
        for (row, ledgerEvidence) in zip(references, recommendedRows) {
          let (position, _, track, outside, title, artist) = row
          let evidence = playlistIndex.evidence(artist: artist, title: title, identity: identity,
            tracks: libraryIndex.matchingTracks(artist: artist, title: title))
          let heard = await context.heardDates(artist: artist, title: title, identity: identity)
          let heardDays = heard.map { Set($0.map { Calendar.current.startOfDay(for: $0) }).count }
          let noteKey = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
          let notes = tasteNotesBySong.map { MCPNoteEvidence($0[noteKey] ?? []) }
          let check = libraryIndex.checkTracks([(artist: artist, title: title)]).first!
          var recommended = ledgerEvidence
          let recommendationKey = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
          recommended?.latestOutcome = recommendationOutcomes?[recommendationKey]
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
      tasteBaselinesTool(context: context, now: now, schema: schema([:]), annotations: readOnly),
      recommendationOutcomesTool(context: context, now: now, schema: recommendationOutcomesSchema, annotations: readOnly),
      recordNewMusicPicksTool(context: context, now: now, schema: recordPicksSchema),
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
        let answersByQuestionID = result.notes.reduce(into: [String: TasteNote]()) { answers, note in
          guard note.resolvedKind == "answer", let questionID = note.answers else { return }
          if let existing = answers[questionID], existing.notedAt >= note.notedAt { return }
          answers[questionID] = note
        }
        let rows = matches.prefix(limit).map { note -> MCPTasteNote in
          let candidates = note.isTimeOnly ? log.map { TasteNoteCandidates.forNote(note, log: $0) } : nil
          let answer = note.resolvedKind == "question" ? note.id.flatMap { answersByQuestionID[$0] }.map(MCPTasteAnswer.init) : nil
          return MCPTasteNote(note, answer: answer, candidates: candidates)
        }
        let listeningCoverage = log.map { MCPListeningCoverage($0.coverage, now: instant, period: .quarter) }
        return .json(MCPTasteNotes(openQuestions: TasteNotesCodec.openQuestions(in: result.notes, now: instant).compactMap { MCPOpenQuestion($0, now: instant) }, notes: Array(rows), coverage: MCPTasteNotesCoverage(
          filesRead: result.filesRead, skippedLines: result.skippedLines,
          listening: listeningCoverage, listeningStatus: listeningError)))
      },
      MCPTool(name: "record_taste_note", description: "Record Music Feedback or taste questions verbatim. Ask a question only when its answer could change your next recommendation, and cite the evidence contrast that prompted it. Put question context in about; answers name a known question by id and use skipped: true for a decline.", inputSchema: recordTasteNoteSchema,
        annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
        let payload = try decode(RecordTasteNotePayload.self, from: input, schema: recordTasteNoteSchema)
        guard !payload.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          throw ArgumentError.invalidShape("note must not be empty")
        }
        let kind = payload.kind ?? (payload.answers == nil && payload.skipped == nil ? "note" : "answer")
        guard ["note", "question", "answer"].contains(kind) else { throw ArgumentError.invalidShape("kind must be note, question, or answer") }
        var payloadAbout: TasteNote.About?
        if kind == "answer" {
          guard payload.answers != nil else { throw ArgumentError.invalidShape("answers must name a known question") }
          let knownNotes = try await context.tasteNotes()
          let questionIDs = Set(knownNotes.notes.compactMap { $0.resolvedKind == "question" ? $0.id : nil })
          guard let answers = payload.answers, questionIDs.contains(answers) else {
            throw ArgumentError.invalidShape("answers must name a known question")
          }
        } else if payload.answers != nil || payload.skipped != nil { throw ArgumentError.invalidShape("answers and skipped require an answer") }
        if kind == "question" {
          guard payload.artist == nil, payload.title == nil, payload.album == nil, payload.playlist == nil else {
            throw ArgumentError.invalidShape("question context belongs in about")
          }
          guard let about = payload.about, !about.songs.isEmpty || !about.playlists.isEmpty else {
            throw ArgumentError.invalidShape("questions require songs or playlists in about")
          }
          let songs = about.songs.map { TasteNote.About.Song(
            artist: $0.artist.trimmingCharacters(in: .whitespacesAndNewlines),
            title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines)) }
          let playlists = about.playlists.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          guard songs.allSatisfy({ !$0.artist.isEmpty && !$0.title.isEmpty }),
            playlists.allSatisfy({ !$0.isEmpty }), !songs.isEmpty || !playlists.isEmpty else {
            throw ArgumentError.invalidShape("about entries must have non-empty song names or playlist names")
          }
          payloadAbout = TasteNote.About(songs: songs, playlists: playlists)
        } else {
          if kind == "answer" {
            guard payload.artist == nil, payload.title == nil, payload.album == nil, payload.playlist == nil else {
              throw ArgumentError.invalidShape("answer lines cannot include song or playlist fields")
            }
          }
          guard payload.about == nil else { throw ArgumentError.invalidShape("about is only valid for questions") }
        }
        let hasSong = payload.artist != nil || payload.title != nil || payload.album != nil
        let hasPlaylist = payload.playlist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if kind == "note" { guard hasSong != hasPlaylist else { throw ArgumentError.invalidShape("provide either artist and title, or playlist") } }
        let artist = payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hasSong || (artist?.isEmpty == false && title?.isEmpty == false) else {
          throw ArgumentError.invalidShape("song notes require artist and title")
        }
        let id = UUID().uuidString
        let note = TasteNote(notedAt: now(), note: payload.note, source: "chat",
          title: title, artist: artist, album: payload.album, playlist: payload.playlist,
          kind: kind, id: id, answers: payload.answers, skipped: payload.skipped,
          about: payloadAbout)
        try await context.recordTasteNote(note)
        return .json(MCPRecordedTasteNote(recorded: true, notedAt: note.notedAt, source: note.source, id: id))
      },
      MCPTool(name: "stage_playlist", description: "Stage a playlist proposal for Jon to review in Vinyl Fever; it does not change Apple Music.", inputSchema: stageSchema, annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
        let payload = try decode(PlaylistToolPayload.self, from: input, schema: stageSchema)
        let tracksMissingYear = payload.tracks.filter { !$0.hasYear }
        guard tracksMissingYear.isEmpty else {
          let songs = tracksMissingYear.map { "\($0.artist) — \($0.title)" }.joined(separator: ", ")
          throw ArgumentError.invalidShape("year is required for every track; missing for: \(songs)")
        }
        let staged = try await context.stage(payload, recordedAt: now())
        let json = MCPToolResult.json(StagedPlaylistResult(staged: true, name: staged.name, trackCount: staged.trackCount,
          dropped: staged.dropped, ledgerRecorded: staged.ledgerRecorded, ledgerReason: staged.ledgerReason,
          missingYear: staged.missingYear, unverifiedReferences: staged.unverifiedReferences, truncated: staged.truncated))
        let payloadText = json.content.first?.text ?? "{}"
        return .text(payloadText + "\n\nJon reviews and creates it in Vinyl Fever; nothing is in Apple Music yet.")
      },
    ])
  }

  private static func tasteBaselinesTool(context: LibraryMCPContext, now: @escaping @Sendable () -> Date,
    schema: MCPValue, annotations: MCPToolAnnotations) -> MCPTool {
    MCPTool(name: "taste_baselines", description: "Summarize recommendation outcomes by source and release age, Apple's own New Music yield, and Jon's yearly Selections stick rate, with counts.", inputSchema: schema, annotations: annotations) { _ in
      let instant = now()
      let (snapshot, roles, _, generatedAt, _) = try await context.playlistData()
      let exposure = try await context.newMusicExposure()
      let weeks = exposure.records.compactMap { record -> NewMusicWeek? in
        if case let .week(value) = record { return value }; return nil
      }
      let (coverage, log) = try await context.tasteCoverage(exposure: exposure, now: instant, snapshotAt: generatedAt)
      let classified = TasteIntelligence.keptAndPassed(weeks: weeks, snapshot: snapshot, roles: roles,
        log: log, now: instant, limit: max(1, weeks.count))
      let ledger = (try? await context.recommendationLedger()) ?? RecommendationLedgerReadResult(batches: [], skippedLines: 0)
      let outcomes = TasteIntelligence.recommendationOutcomes(ledger: ledger, weeks: weeks, snapshot: snapshot,
        roles: roles, log: log, now: instant, limit: max(1, min(ledger.batches.count, 50)))
      let baselines = TasteIntelligence.baselines(weeks: classified, snapshot: snapshot, ledger: ledger,
        outcomes: outcomes, curation: await context.curationChanges())
      return .json(MCPBaselines(baselines: baselines, coverage: coverage))
    }
  }

  private static func recommendationOutcomesTool(context: LibraryMCPContext, now: @escaping @Sendable () -> Date,
    schema: MCPValue, annotations: MCPToolAnnotations) -> MCPTool {
    MCPTool(name: "recommendation_outcomes", description: "Classify recent unfamiliar songs from recommendation batches and show New Music pick outcomes, with coverage.", inputSchema: schema, annotations: annotations) { input in
      let payload = try decode(RecommendationOutcomesPayload.self, from: input, schema: schema)
      let limit = max(1, min(payload.batches ?? 10, 50))
      let result = try await context.recommendationOutcomes(now: now(), limit: limit)
      return .json(MCPRecommendationOutcomes(outcomes: result.0, coverage: result.1))
    }
  }

  private static func recordNewMusicPicksTool(context: LibraryMCPContext, now: @escaping @Sendable () -> Date,
    schema: MCPValue) -> MCPTool {
    MCPTool(name: "record_new_music_picks", description: "Record the chat's blind picks from the latest saved New Music week before Jon listens.", inputSchema: schema, annotations: MCPToolAnnotations(destructive: false, openWorld: false)) { input in
      let payload = try decode(RecordNewMusicPicksPayload.self, from: input, schema: schema)
      let instant = now()
      let songs = payload.songs.map { (artist: $0.artist, title: $0.title) }
      let count = try await context.recordNewMusicPicks(songs, recordedAt: instant)
      return .json(MCPRecordPicks(recorded: true, recordedAt: instant, songCount: count))
    }
  }

  /// Create writes the description into Apple Music, so keep chat's process notes out of it.
  private static let stageDescriptionGuidance =
    "One sentence about the music; it becomes the playlist's description in Apple Music. No library stats, availability notes, or dates. Don't stage the same batch again to fix a year; that marks every song as recommended before."
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
private struct RecommendationOutcomesPayload: Decodable, Sendable { var batches: Int? }

private struct MCPPlaylistSummary: Encodable {
  var name: String; var role: String?; var folder: String?; var kind: String
  var songCount: Int; var inLibraryCount: Int
}
private struct MCPPlaylistList: Encodable {
  var playlists: [MCPPlaylistSummary]; var unlabeledCount: Int; var matchingCount: Int; var snapshotGeneratedAt: Date
  var openQuestions: [MCPOpenQuestion]?
}
private struct MCPPlaylistTrack: Encodable {
  var position: Int; var artist: String; var title: String; var album: String; var year: Int?
  var evidence: MCPPlaylistSongEvidence
}
private struct MCPPlaylistTracks: Encodable {
  var name: String; var role: String?; var tracks: [MCPPlaylistTrack]; var unlabeledPlaylistCount: Int; var listening: String?; var snapshotGeneratedAt: Date
}
private struct MCPCheckResult: Encodable {
  var tracks: [MCPCheckedTrack]
  var unlabeledPlaylistCount: Int
  var listening: String?
  var openQuestions: [MCPOpenQuestion]?
}
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
  var ledgerRecorded: Bool; var ledgerReason: String?; var missingYear: [String]
  var unverifiedReferences: [String]; var truncated: Bool
  init(staged: Bool, name: String, trackCount: Int, dropped: [DroppedPlaylistTrack], ledgerRecorded: Bool,
    ledgerReason: String?, missingYear: [String], unverifiedReferences: [String], truncated: Bool) {
    self.staged = staged; self.name = name; self.trackCount = trackCount
    self.dropped = dropped.map { Dropped(index: $0.index, artist: $0.artist, title: $0.title) }
    self.ledgerRecorded = ledgerRecorded; self.ledgerReason = ledgerReason
    self.missingYear = missingYear; self.unverifiedReferences = unverifiedReferences; self.truncated = truncated
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
