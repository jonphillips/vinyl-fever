import Foundation

public enum PlaylistReviewSource: String, Codable, Sendable {
  case jon
  case chat
}

public enum PlaylistReviewKind: String, Codable, Sendable {
  case finished
  case reopened
  case review
}

/// One append-only statement about a staged playlist. `recordedAt` and `host` identify the
/// recommendation batch; `playlistID` is the shelf's stable identity for that batch.
public struct PlaylistReviewEntry: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var source: PlaylistReviewSource
  public var kind: PlaylistReviewKind
  public var host: String
  public var recordedAt: Date
  public var playlistID: String
  public var playlist: String
  public var at: Date
  public var device: String?
  public var text: String?
  public var heard: Int?
  public var kept: Int?
  public var passed: Int?
  public var unheard: Int?

  public init(source: PlaylistReviewSource, kind: PlaylistReviewKind, host: String,
    recordedAt: Date, playlistID: String, playlist: String, at: Date,
    device: String? = nil, text: String? = nil, heard: Int? = nil, kept: Int? = nil,
    passed: Int? = nil, unheard: Int? = nil) {
    format = "vf-playlist-review"
    version = 1
    self.source = source
    self.kind = kind
    self.host = host
    self.recordedAt = recordedAt
    self.playlistID = playlistID
    self.playlist = playlist
    self.at = at
    self.device = device
    self.text = text
    self.heard = heard
    self.kept = kept
    self.passed = passed
    self.unheard = unheard
  }
}

public struct PlaylistReviewsReadResult: Equatable, Sendable {
  public var entries: [PlaylistReviewEntry]
  public var skippedLines: Int
  public var filesRead: Int
  public init(entries: [PlaylistReviewEntry], skippedLines: Int, filesRead: Int) {
    self.entries = entries
    self.skippedLines = skippedLines
    self.filesRead = filesRead
  }
}

public enum PlaylistReviewsCodec {
  public static func encode(_ entry: PlaylistReviewEntry) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    var data = try encoder.encode(entry)
    data.append(0x0A)
    return data
  }

  public static func readFiles(_ files: [Data]) -> PlaylistReviewsReadResult {
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
    var entries: [PlaylistReviewEntry] = []
    var skippedLines = 0
    for data in files {
      let bytes = [UInt8](data)
      let hasFinalNewline = bytes.last == 0x0A
      let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
      for (index, line) in lines.enumerated() {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let lineData = Data(line.utf8)
        let header = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        if header == nil && !hasFinalNewline && index == lines.count - 1 { continue }
        guard header?["format"] as? String == "vf-playlist-review",
          header?["version"] as? Int == 1,
          let entry = try? decoder.decode(PlaylistReviewEntry.self, from: lineData),
          isValid(entry)
        else {
          skippedLines += 1
          continue
        }
        entries.append(entry)
      }
    }
    return PlaylistReviewsReadResult(entries: entries, skippedLines: skippedLines, filesRead: files.count)
  }

  public static func latestJonState(in entries: [PlaylistReviewEntry]) -> [String: PlaylistReviewEntry] {
    entries.filter { $0.source == .jon && ($0.kind == .finished || $0.kind == .reopened) }
      .reduce(into: [:]) { result, entry in
        guard let previous = result[entry.playlistID], previous.at > entry.at else {
          result[entry.playlistID] = entry
          return
        }
      }
  }

  public static func latestReviews(in entries: [PlaylistReviewEntry]) -> [String: PlaylistReviewEntry] {
    entries.filter { $0.source == .chat && $0.kind == .review }
      .reduce(into: [:]) { result, entry in
        guard let previous = result[entry.playlistID], previous.at > entry.at else {
          result[entry.playlistID] = entry
          return
        }
      }
  }

  public static func append(_ entry: PlaylistReviewEntry, writer: String, folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let safeWriter = writer.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
    }.joined()
    let url = folder.appending(path: "\(safeWriter.isEmpty ? "device" : safeWriter).jsonl")
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
        try handle.write(contentsOf: encode(entry))
        try handle.synchronize()
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }

  private static func isValid(_ entry: PlaylistReviewEntry) -> Bool {
    guard !entry.host.isEmpty, !entry.playlistID.isEmpty, !entry.playlist.isEmpty else { return false }
    switch (entry.source, entry.kind) {
    case (.jon, .finished), (.jon, .reopened): return entry.device?.isEmpty == false
    case (.chat, .review):
      return entry.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        entry.heard != nil && entry.kept != nil && entry.passed != nil && entry.unheard != nil
    default: return false
    }
  }
}
