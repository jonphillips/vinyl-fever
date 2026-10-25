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

  public init(artist: String, title: String, album: String? = nil, year: Int? = nil,
    familiar: Bool, reasons: [String], artistKnown: Bool) {
    self.artist = artist; self.title = title; self.album = album; self.year = year
    self.familiar = familiar; self.reasons = reasons; self.artistKnown = artistKnown
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

  public init(kind: String = "staged-playlist", source: String = "chat", recordedAt: Date,
    host: String, playlist: String? = nil, tracks: [RecommendationTrack], version: Int = 1) {
    format = "vf-recommendation-batch"; self.version = version; self.kind = kind
    self.source = source; self.recordedAt = recordedAt; self.host = host
    self.playlist = playlist; self.tracks = tracks
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
  public init(count: Int, latestRecordedAt: Date) {
    self.count = count; self.latestRecordedAt = latestRecordedAt
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

public enum RecommendationFamiliarity {
  public static func evaluate(artist: String, title: String, album: String? = nil, year: Int? = nil,
    snapshot: LibrarySnapshot,
    index: LibraryIndex, playlistIndex: PlaylistIndex, listeningLog: ListeningLog?,
    tasteNoteKeys: Set<String>, ledger: RecommendationLedgerReadResult, recordedAt: Date
  ) -> RecommendationTrack {
    let identity = index.artistIdentity
    let key = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
    let owned = index.checkTracks([(artist: artist, title: title)]).first?.owned == true
    let heard = listeningLog?.plays.contains { play in
      play.windowStart < recordedAt && TasteIntelligence.songKey(artist: play.item.artist,
        title: play.item.title, identity: identity) == key
    } == true
    let memberships = playlistIndex.membershipsBySong[key, default: []].filter {
      $0.role != .ignore && $0.role != .followed
    }
    let playlistReasons = Set(memberships.map { "playlist:\($0.role?.rawValue ?? "unlabeled")" }).sorted()
    let noted = tasteNoteKeys.contains(key)
    let recommended = ledger.batches.contains { batch in
      batch.tracks.contains {
        !$0.familiar && TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) == key
      }
    }
    var reasons: [String] = []
    if owned { reasons.append("owned") }
    if heard { reasons.append("heard") }
    reasons += playlistReasons
    if noted { reasons.append("noted") }
    if recommended { reasons.append("recommended") }
    let knownArtists = Set(snapshot.tracks.map(\.artist))
    let artistKnownInLibrary = knownArtists.contains { identity.key($0) == identity.key(artist) }
    let artistKnownInLog = listeningLog?.plays.contains {
      $0.windowStart < recordedAt && identity.key($0.item.artist) == identity.key(artist)
    } == true
    return RecommendationTrack(artist: artist, title: title, album: album, year: year, familiar: !reasons.isEmpty,
      reasons: reasons, artistKnown: artistKnownInLibrary || artistKnownInLog)
  }
}

public enum RecommendationLedgerEvidence {
  public static func forSong(artist: String, title: String, identity: ArtistIdentity,
    ledger: RecommendationLedgerReadResult) -> RecommendationEvidence? {
    let matching = ledger.batches.filter { batch in
      batch.tracks.contains { !$0.familiar && TasteIntelligence.songKey(artist: $0.artist,
        title: $0.title, identity: identity) == TasteIntelligence.songKey(artist: artist, title: title, identity: identity) }
    }
    guard !matching.isEmpty else { return nil }
    return RecommendationEvidence(count: matching.count, latestRecordedAt: matching.map(\.recordedAt).max()!)
  }
}
