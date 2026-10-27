import Foundation
import VinylFeverListening

public struct RecommendationTrack: Codable, Equatable, Sendable {
  public var artist: String
  public var title: String
  public var album: String?
  public var year: Int?
  public var familiar: Bool
  public var reasons: [String]
  public var artistKnown: Bool
  public var why: String?
  public var like: [RecommendationLike]?
  public var heardBeforePick: Bool?
  public var picked: Bool?

  public init(artist: String, title: String, album: String? = nil, year: Int? = nil,
    familiar: Bool, reasons: [String], artistKnown: Bool, why: String? = nil,
    like: [RecommendationLike]? = nil, heardBeforePick: Bool? = nil, picked: Bool? = nil) {
    self.artist = artist; self.title = title; self.album = album; self.year = year
    self.familiar = familiar; self.reasons = reasons; self.artistKnown = artistKnown
    self.why = why; self.like = like; self.heardBeforePick = heardBeforePick
    self.picked = picked
  }
}

public struct RecommendationLike: Codable, Equatable, Sendable {
  public var artist: String
  public var title: String
  public var from: String?
  public var found: String?
  public init(artist: String, title: String, from: String? = nil, found: String? = nil) {
    self.artist = artist; self.title = title; self.from = from; self.found = found
  }
}

public struct RecommendationBatch: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var kind: String
  public var source: String
  public var recordedAt: Date
  public var host: String
  public var playlist: String?
  public var tracks: [RecommendationTrack]
  public var request: String?
  public var coverage: RecommendationCoverage?
  public var batchDate: Date?

  public init(kind: String = "staged-playlist", source: String = "chat", recordedAt: Date,
    host: String, playlist: String? = nil, tracks: [RecommendationTrack], version: Int = 1,
    request: String? = nil, coverage: RecommendationCoverage? = nil, batchDate: Date? = nil) {
    format = "vf-recommendation-batch"; self.version = version; self.kind = kind
    self.source = source; self.recordedAt = recordedAt; self.host = host
    self.playlist = playlist; self.tracks = tracks
    self.request = request; self.coverage = coverage
    self.batchDate = batchDate
  }
}

public struct RecommendationCoverage: Codable, Equatable, Sendable {
  public var listening: Bool
  public var notes: Bool
  public var snapshotAt: Date?
  public init(listening: Bool, notes: Bool, snapshotAt: Date?) {
    self.listening = listening; self.notes = notes; self.snapshotAt = snapshotAt
  }
}

public struct RecommendationLedgerReadResult: Equatable, Sendable {
  public var batches: [RecommendationBatch]
  public var skippedLines: Int
  public init(batches: [RecommendationBatch], skippedLines: Int) {
    self.batches = batches; self.skippedLines = skippedLines
  }
}

public struct RecommendationEvidence: Codable, Equatable, Sendable {
  public var count: Int
  public var latestRecordedAt: Date
  public var latestWhy: String?
  public var latestOutcome: String?
  public init(count: Int, latestRecordedAt: Date, latestWhy: String? = nil, latestOutcome: String? = nil) {
    self.count = count; self.latestRecordedAt = latestRecordedAt
    self.latestWhy = latestWhy; self.latestOutcome = latestOutcome
  }
  private enum CodingKeys: String, CodingKey { case count, latestRecordedAt, latestWhy, latestOutcome }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(count, forKey: .count); try values.encode(latestRecordedAt, forKey: .latestRecordedAt)
    try values.encodeIfPresent(latestWhy, forKey: .latestWhy)
    try values.encodeIfPresent(latestOutcome, forKey: .latestOutcome)
  }
}

public enum RecommendationLedgerCodec {
  public static func encode(_ batch: RecommendationBatch) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    var data = try encoder.encode(batch)
    data.append(0x0A)
    return data
  }

  public static func readFiles(_ files: [Data]) -> RecommendationLedgerReadResult {
    var batches: [RecommendationBatch] = []
    var skippedLines = 0
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: value) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO timestamp")
      }
      return date
    }

    for data in files {
      let bytes = [UInt8](data)
      let hasFinalNewline = bytes.last == 0x0A
      let lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
      for (index, line) in lines.enumerated() {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let lineData = Data(line.utf8)
        let header = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        if header == nil && !hasFinalNewline && index == lines.count - 1 { continue }
        guard header?["format"] as? String == "vf-recommendation-batch",
          header?["version"] as? Int == 1,
          let batch = try? decoder.decode(RecommendationBatch.self, from: lineData)
        else {
          skippedLines += 1
          continue
        }
        batches.append(batch)
      }
    }
    return RecommendationLedgerReadResult(batches: batches, skippedLines: skippedLines)
  }

  public static func append(_ batch: RecommendationBatch, host: String, folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let safeHost = host.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
    }.joined()
    let url = folder.appending(path: "\(safeHost.isEmpty ? "Mac" : safeHost).jsonl")
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
      do {
        if !FileManager.default.fileExists(atPath: target.path) {
          _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: encode(batch))
        try handle.synchronize()
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }
}

/// One-pass index of unfamiliar songs in the recommendation ledger.
public struct RecommendationLedgerEvidenceIndex: Sendable {
  public let identity: ArtistIdentity
  private let evidenceBySong: [String: RecommendationEvidence]

  public init(ledger: RecommendationLedgerReadResult, identity: ArtistIdentity) {
    self.identity = identity
    var evidence: [String: RecommendationEvidence] = [:]
    for batch in ledger.batches where batch.kind == "staged-playlist" {
      // A batch contributes at most once per song, even if its input repeats a row.
      let keys = Set(batch.tracks.lazy.filter { !$0.familiar }.map {
        TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity)
      })
      for key in keys {
        if let current = evidence[key] {
          let latest = batch.recordedAt >= current.latestRecordedAt
          let why = batch.tracks.first(where: { !$0.familiar && TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) == key })?.why
          evidence[key] = RecommendationEvidence(count: current.count + 1,
            latestRecordedAt: max(current.latestRecordedAt, batch.recordedAt), latestWhy: latest ? why : current.latestWhy)
        } else {
          let why = batch.tracks.first(where: { !$0.familiar && TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) == key })?.why
          evidence[key] = RecommendationEvidence(count: 1, latestRecordedAt: batch.recordedAt, latestWhy: why)
        }
      }
    }
    evidenceBySong = evidence
  }

  public func forSong(artist: String, title: String) -> RecommendationEvidence? {
    evidenceBySong[TasteIntelligence.songKey(artist: artist, title: title, identity: identity)]
  }
}

/// Immutable lookups shared by every row in one stage request.
public struct RecommendationFamiliarityIndex: Sendable {
  private let identity: ArtistIdentity
  private let libraryIndex: LibraryIndex
  private let playlistIndex: PlaylistIndex
  private let tasteNoteKeys: Set<String>
  private let recommendationEvidence: RecommendationLedgerEvidenceIndex
  private let knownArtistKeys: Set<String>
  private let heardArtistsByTitle: [String: Set<String>]
  private let heardArtistKeys: Set<String>
  private let recordedAt: Date

  public init(snapshot: LibrarySnapshot, index: LibraryIndex, playlistIndex: PlaylistIndex,
    listeningLog: ListeningLog?, tasteNoteKeys: Set<String>, ledger: RecommendationLedgerReadResult,
    recordedAt: Date) {
    self.init(snapshot: snapshot, index: index, playlistIndex: playlistIndex,
      listeningLog: listeningLog, tasteNoteKeys: tasteNoteKeys,
      recommendationEvidence: RecommendationLedgerEvidenceIndex(ledger: ledger, identity: index.artistIdentity),
      recordedAt: recordedAt)
  }

  public init(snapshot: LibrarySnapshot, index: LibraryIndex, playlistIndex: PlaylistIndex,
    listeningLog: ListeningLog?, tasteNoteKeys: Set<String>, recommendationEvidence: RecommendationLedgerEvidenceIndex,
    recordedAt: Date) {
    let identity = index.artistIdentity
    self.identity = identity
    self.libraryIndex = index
    self.playlistIndex = playlistIndex
    self.tasteNoteKeys = tasteNoteKeys
    self.recommendationEvidence = recommendationEvidence
    self.recordedAt = recordedAt

    let uniqueLibraryArtists = Set(snapshot.tracks.lazy.map(\.artist))
    knownArtistKeys = Set(uniqueLibraryArtists.map { identity.key($0) })

    var artistsByTitle: [String: Set<String>] = [:]
    var heardArtists = Set<String>()
    for play in listeningLog?.plays ?? [] where play.windowStart < recordedAt {
      let credits = identity.credits(play.item.artist)
      heardArtists.formUnion(credits)
      let title = SongTextNormalizer.libraryTitle(play.item.title)
      for credit in credits { artistsByTitle["\(credit)\u{0}\(title)", default: []].formUnion(credits) }
    }
    heardArtistsByTitle = artistsByTitle
    heardArtistKeys = heardArtists
  }

  public func evaluate(artist: String, title: String, album: String? = nil, year: Int? = nil) -> RecommendationTrack {
    let credits = identity.credits(artist)
    let titleKey = SongTextNormalizer.libraryTitle(title)
    let key = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
    let heard = credits.contains { heardArtistsByTitle["\($0)\u{0}\(titleKey)"] != nil }
    let memberships = playlistIndex.membershipsBySong[key, default: []].filter {
      $0.role != .ignore && $0.role != .followed
    }
    let playlistReasons = Set(memberships.map { "playlist:\($0.role?.rawValue ?? "unlabeled")" }).sorted()
    let noted = tasteNoteKeys.contains(key)
    let recommended = recommendationEvidence.forSong(artist: artist, title: title) != nil
    var reasons: [String] = []
    if libraryIndex.checkTracks([(artist: artist, title: title)]).first?.owned == true { reasons.append("owned") }
    if heard { reasons.append("heard") }
    reasons += playlistReasons
    if noted { reasons.append("noted") }
    if recommended { reasons.append("recommended") }
    let artistKnown = knownArtistKeys.contains(identity.key(artist)) || credits.contains { heardArtistKeys.contains($0) }
    return RecommendationTrack(artist: artist, title: title, album: album, year: year,
      familiar: !reasons.isEmpty, reasons: reasons, artistKnown: artistKnown)
  }
}

public enum RecommendationLedgerEvidence {
  public static func forSong(artist: String, title: String, identity: ArtistIdentity,
    ledger: RecommendationLedgerReadResult) -> RecommendationEvidence? {
    RecommendationLedgerEvidenceIndex(ledger: ledger, identity: identity).forSong(artist: artist, title: title)
  }
}
