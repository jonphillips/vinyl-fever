import Foundation

public enum PlaylistCreationKind: String, Codable, Sendable {
  case created
  case dismissed
  case needsReview = "needs-review"
}

public struct PlaylistCreationSkippedSong: Codable, Equatable, Sendable {
  public var title: String
  public var artist: String
  public var reason: String
  public init(title: String, artist: String, reason: String) {
    self.title = title; self.artist = artist; self.reason = reason
  }
}

/// One creator's append-only statement about a staged playlist batch.
public struct PlaylistCreationEvent: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var kind: PlaylistCreationKind
  public var host: String
  public var recordedAt: Date
  public var playlist: String
  public var at: Date
  public var device: String?
  public var writerHost: String?
  public var musicID: String?
  public var songs: Int?
  public var skipped: [PlaylistCreationSkippedSong]?
  public var error: String?

  public init(kind: PlaylistCreationKind, host: String, recordedAt: Date, playlist: String,
    at: Date, device: String? = nil, writerHost: String? = nil, musicID: String? = nil,
    songs: Int? = nil, skipped: [PlaylistCreationSkippedSong]? = nil, error: String? = nil) {
    format = "vf-playlist-creation"; version = 1; self.kind = kind
    self.host = host; self.recordedAt = recordedAt; self.playlist = playlist
    self.at = at; self.device = device; self.writerHost = writerHost
    self.musicID = musicID; self.songs = songs; self.skipped = skipped; self.error = error
  }

  public var writerName: String { device ?? writerHost ?? "another device" }
}

public struct PlaylistCreationsReadResult: Equatable, Sendable {
  public var events: [PlaylistCreationEvent]
  public var skippedLines: Int
  public var filesRead: Int
  public var unreadableFileCount: Int
  public var unknownKindCount: Int
  public init(events: [PlaylistCreationEvent], skippedLines: Int, filesRead: Int, unreadableFileCount: Int = 0,
    unknownKindCount: Int = 0) {
    self.events = events; self.skippedLines = skippedLines; self.filesRead = filesRead
    self.unreadableFileCount = unreadableFileCount
    self.unknownKindCount = unknownKindCount
  }
}

public enum PlaylistCreationsCodec {
  public static func batchKey(host: String, recordedAt: Date) -> String {
    "\(host)|\(Int(recordedAt.timeIntervalSince1970.rounded(.down)))"
  }

  /// Lossless-or-loud: malformed events are omitted and counted by the reader.
  public static func encode(_ event: PlaylistCreationEvent) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    var data = try encoder.encode(event)
    data.append(0x0A)
    return data
  }

  public static func readFiles(_ files: [Data], unreadableFileCount: Int = 0) -> PlaylistCreationsReadResult {
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
    var events: [PlaylistCreationEvent] = []
    var skipped = 0
    var unknownKinds = 0
    for data in files {
      let text = String(decoding: data, as: UTF8.self)
      let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
      for line in lines {
        let bytes = Data(line.utf8)
        let header = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        if header?["format"] as? String == "vf-playlist-creation",
          header?["version"] as? Int == 1,
          let rawKind = header?["kind"] as? String,
          PlaylistCreationKind(rawValue: rawKind) == nil {
          unknownKinds += 1
          continue
        }
        guard header?["format"] as? String == "vf-playlist-creation",
          header?["version"] as? Int == 1,
          let event = try? decoder.decode(PlaylistCreationEvent.self, from: bytes),
          valid(event)
        else { skipped += 1; continue }
        events.append(event)
      }
    }
    return PlaylistCreationsReadResult(events: events, skippedLines: skipped, filesRead: files.count,
      unreadableFileCount: unreadableFileCount, unknownKindCount: unknownKinds)
  }

  public static func latestEvents(_ events: [PlaylistCreationEvent]) -> [String: PlaylistCreationEvent] {
    var latest: [String: PlaylistCreationEvent] = [:]
    for event in events {
      let key = batchKey(host: event.host, recordedAt: event.recordedAt)
      guard let previous = latest[key] else { latest[key] = event; continue }
      let previousIsTerminal = previous.kind == .created || previous.kind == .dismissed
      let eventIsTerminal = event.kind == .created || event.kind == .dismissed
      if eventIsTerminal && !previousIsTerminal || eventIsTerminal == previousIsTerminal && previous.at <= event.at {
        latest[key] = event
      }
    }
    return latest
  }

  private static func valid(_ event: PlaylistCreationEvent) -> Bool {
    guard !event.host.isEmpty, !event.playlist.isEmpty,
      (event.device != nil) != (event.writerHost != nil) else { return false }
    switch event.kind {
    case .created:
      return event.musicID != nil && event.songs != nil && event.skipped != nil
        && event.error == nil && event.songs! >= 0 && event.skipped!.allSatisfy { ["not-found", "skipped", "duplicate"].contains($0.reason) }
    case .dismissed:
      return event.musicID == nil && event.songs == nil && event.skipped == nil && event.error == nil
    case .needsReview:
      return event.musicID == nil && event.songs == nil
        && (event.skipped?.isEmpty == false || event.error != nil)
        && (event.skipped ?? []).allSatisfy { ["ambiguous", "not-found", "error"].contains($0.reason) }
    }
  }
}
