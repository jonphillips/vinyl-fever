import Foundation

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
  public var description: String?
  public var coverage: RecommendationCoverage?
  public var batchDate: Date?

  public init(kind: String = "staged-playlist", source: String = "chat", recordedAt: Date,
    host: String, playlist: String? = nil, tracks: [RecommendationTrack], version: Int = 1,
    request: String? = nil, description: String? = nil, coverage: RecommendationCoverage? = nil,
    batchDate: Date? = nil) {
    format = "vf-recommendation-batch"; self.version = version; self.kind = kind
    self.source = source; self.recordedAt = recordedAt; self.host = host
    self.playlist = playlist; self.tracks = tracks
    self.request = request; self.description = description; self.coverage = coverage
    self.batchDate = batchDate
  }
}

public enum PlaylistRequestHeader: Equatable, Sendable {
  case jonWords
  case unattributed

  public static func forBatch(_ batch: RecommendationBatch) -> Self {
    guard let description = batch.description,
      !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .unattributed
    }
    return .jonWords
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

public struct PlaylistShelfSong: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var artist: String
  public var album: String?
  public var year: Int?
  public var familiarity: String
  public var why: String?
  public var like: [RecommendationLike]

  public init(id: String, title: String, artist: String, album: String?, year: Int?, familiarity: String,
    why: String?, like: [RecommendationLike]) {
    self.id = id; self.title = title; self.artist = artist; self.album = album; self.year = year
    self.familiarity = familiarity; self.why = why; self.like = like
  }
}

public struct PlaylistShelfPlaylist: Equatable, Sendable, Identifiable {
  public var id: String
  public var batch: RecommendationBatch
  public var stagedDate: String
  public var songCount: Int
  public var newSongCount: Int
  public var songs: [PlaylistShelfSong]
  public var hasReasons: Bool { songs.contains { $0.why != nil } }

  public init(id: String, batch: RecommendationBatch, stagedDate: String, songCount: Int,
    newSongCount: Int, songs: [PlaylistShelfSong]) {
    self.id = id; self.batch = batch; self.stagedDate = stagedDate
    self.songCount = songCount; self.newSongCount = newSongCount; self.songs = songs
  }
}

public enum PlaylistShelf {
  public static func make(
    from ledger: RecommendationLedgerReadResult,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) -> [PlaylistShelfPlaylist] {
    let batches = ledger.batches
      .filter { $0.kind == "staged-playlist" }
      .sorted { $0.recordedAt > $1.recordedAt }

    return batches.map { batch in
      let playlistID = "\(batch.host)|\(batch.recordedAt.timeIntervalSince1970)"
      let songs = batch.tracks.enumerated().map { songIndex, track in
        PlaylistShelfSong(
          id: "\(playlistID)|\(songIndex)",
          title: track.title,
          artist: track.artist,
          album: track.album,
          year: track.year,
          familiarity: familiarity(for: track),
          why: nonempty(track.why),
          like: track.like ?? []
        )
      }
      return PlaylistShelfPlaylist(
        id: playlistID,
        batch: batch,
        stagedDate: RecommendationDatePhrase.format(batch.recordedAt, relativeTo: now,
          calendar: calendar, timeZone: timeZone),
        songCount: batch.tracks.count,
        newSongCount: batch.tracks.filter { !$0.familiar }.count,
        songs: songs
      )
    }
  }

  public static func noReasonsText(for playlist: PlaylistShelfPlaylist) -> String? {
    playlist.hasReasons ? nil : "No reasons were recorded for this playlist."
  }

  private static func familiarity(for track: RecommendationTrack) -> String {
    guard track.familiar else { return "New to you" }
    if track.reasons.contains("playlist:keepers") { return "You kept it" }
    if track.reasons.contains("owned") { return "In your library" }
    if let playlist = track.reasons.first(where: { $0.hasPrefix("playlist:") }) {
      let role = String(playlist.dropFirst("playlist:".count))
      return role == "unlabeled" ? "In one of your playlists" : "In a \(role) playlist"
    }
    if track.reasons.contains("heard") { return "You've heard it" }
    if track.reasons.contains("noted") { return "You left a note on it" }
    if track.reasons.contains("recommended") { return "Recommended before" }
    return "You knew it"
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

public enum RecommendationDatePhrase {
  public static func format(_ date: Date, relativeTo now: Date, calendar: Calendar, timeZone: TimeZone) -> String {
    var calendar = calendar
    calendar.timeZone = timeZone
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
      ? "MMMM d" : "MMMM d, yyyy"
    return formatter.string(from: date)
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

  public static func playlistNames(inFolder folder: URL) throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "jsonl" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let data = try files.map { try Data(contentsOf: $0) }
    return Set(readFiles(data).batches.compactMap(\.playlist).filter { !$0.isEmpty })
  }
}
