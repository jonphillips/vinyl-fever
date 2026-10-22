import Foundation

public struct ListeningItem: Codable, Equatable, Hashable, Sendable, Identifiable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case song
    case librarySong = "library-song"
  }

  public var kind: Kind
  public var id: String
  public var title: String
  public var artist: String
  public var album: String?
  public var durationSeconds: Double?

  public init(
    kind: Kind, id: String, title: String, artist: String, album: String? = nil,
    durationSeconds: Double? = nil
  ) {
    self.kind = kind
    self.id = id
    self.title = title
    self.artist = artist
    self.album = album
    self.durationSeconds = durationSeconds
  }

  public var identity: ListeningIdentity { ListeningIdentity(kind: kind, id: id) }
}

public struct ListeningIdentity: Codable, Equatable, Hashable, Sendable {
  public var kind: ListeningItem.Kind
  public var id: String

  public init(kind: ListeningItem.Kind, id: String) {
    self.kind = kind
    self.id = id
  }
}

public struct ListeningFetch: Codable, Equatable, Sendable {
  public static let formatName = "vf-listening-fetch"
  public static let currentVersion = 2

  public enum Outcome: String, Codable, Sendable {
    case baseline
    case plays
    case none
    case gap
    case failed
  }

  public var format: String
  public var version: Int
  public var poller: UUID
  public var host: String
  public var fetchedAt: Date
  public var outcome: Outcome
  public var newCount: Int
  public var pagesRead: Int
  public var items: [ListeningItem]
  public var since: ListeningSince?
  public var error: String?

  public init(
    poller: UUID, host: String, fetchedAt: Date, outcome: Outcome, newCount: Int = 0,
    pagesRead: Int, items: [ListeningItem] = [], since: ListeningSince? = nil,
    error: String? = nil
  ) {
    self.format = Self.formatName
    self.version = since == nil ? 1 : 2
    self.poller = poller
    self.host = host
    self.fetchedAt = fetchedAt
    self.outcome = outcome
    self.newCount = newCount
    self.pagesRead = pagesRead
    self.items = items
    self.since = since
    self.error = error
  }

  private enum CodingKeys: String, CodingKey {
    case format, version, poller, host, fetchedAt, outcome, newCount, pagesRead, items, since, error
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    format = try values.decode(String.self, forKey: .format)
    version = try values.decode(Int.self, forKey: .version)
    poller = try values.decode(UUID.self, forKey: .poller)
    host = try values.decode(String.self, forKey: .host)
    fetchedAt = try values.decode(Date.self, forKey: .fetchedAt)
    outcome = try values.decode(Outcome.self, forKey: .outcome)
    newCount = try values.decodeIfPresent(Int.self, forKey: .newCount) ?? 0
    pagesRead = try values.decodeIfPresent(Int.self, forKey: .pagesRead) ?? 0
    items = try values.decodeIfPresent([ListeningItem].self, forKey: .items) ?? []
    since = try values.decodeIfPresent(ListeningSince.self, forKey: .since)
    error = try values.decodeIfPresent(String.self, forKey: .error)
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(format, forKey: .format)
    try values.encode(version, forKey: .version)
    try values.encode(poller, forKey: .poller)
    try values.encode(host, forKey: .host)
    try values.encode(fetchedAt, forKey: .fetchedAt)
    try values.encode(outcome, forKey: .outcome)
    try values.encode(newCount, forKey: .newCount)
    try values.encode(pagesRead, forKey: .pagesRead)
    try values.encodeIfPresent(since, forKey: .since)
    switch outcome {
    case .baseline, .plays, .gap:
      try values.encode(items, forKey: .items)
    case .none, .failed:
      break
    }
    if outcome == .failed {
      try values.encodeIfPresent(error, forKey: .error)
    }
  }
}

public struct ListeningSince: Codable, Equatable, Sendable {
  public var poller: UUID
  public var fetchedAt: Date

  public init(poller: UUID, fetchedAt: Date) {
    self.poller = poller
    self.fetchedAt = fetchedAt
  }
}

public struct ListeningHandoverMarker: Codable, Equatable, Sendable {
  public var previousPoller: UUID
  public var fallbackSince: Date

  public init(previousPoller: UUID, fallbackSince: Date) {
    self.previousPoller = previousPoller
    self.fallbackSince = fallbackSince
  }
}

public struct ListeningLease: Codable, Equatable, Sendable {
  public static let formatName = "vf-listening-lease"
  public static let currentVersion = 1

  public var format: String
  public var version: Int
  public var poller: UUID
  public var host: String
  public var takenAt: Date

  public init(poller: UUID, host: String, takenAt: Date) {
    self.format = Self.formatName
    self.version = Self.currentVersion
    self.poller = poller
    self.host = host
    self.takenAt = takenAt
  }

  public func permitsWrites(by poller: UUID) -> Bool { self.poller == poller }
}

public struct ListeningPlay: Codable, Equatable, Sendable, Identifiable {
  public var item: ListeningItem
  public var windowStart: Date
  public var windowEnd: Date
  public var poller: UUID

  public init(item: ListeningItem, windowStart: Date, windowEnd: Date, poller: UUID) {
    self.item = item
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.poller = poller
  }

  public var id: String {
    "\(poller.uuidString)|\(windowEnd.timeIntervalSince1970)|\(item.kind.rawValue)|\(item.id)"
  }
}

public enum ListeningPeriod: String, CaseIterable, Codable, Sendable {
  case day = "24h"
  case week = "7d"
  case month = "30d"
  case quarter = "90d"

  public var duration: TimeInterval {
    switch self {
    case .day: 24 * 60 * 60
    case .week: 7 * 24 * 60 * 60
    case .month: 30 * 24 * 60 * 60
    case .quarter: 90 * 24 * 60 * 60
    }
  }
}

public struct ListeningArtistCount: Codable, Equatable, Sendable, Identifiable {
  public var artist: String
  public var plays: Int
  public var id: String { artist }

  public init(artist: String, plays: Int) {
    self.artist = artist
    self.plays = plays
  }
}

public struct ListeningTrackCount: Codable, Equatable, Sendable, Identifiable {
  public var title: String
  public var artist: String
  public var album: String?
  public var plays: Int
  public var id: String { "\(artist)\u{0}\(title)" }

  public init(title: String, artist: String, album: String?, plays: Int) {
    self.title = title
    self.artist = artist
    self.album = album
    self.plays = plays
  }
}
