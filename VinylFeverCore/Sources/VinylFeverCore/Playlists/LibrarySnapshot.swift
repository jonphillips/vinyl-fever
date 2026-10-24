import Foundation

public enum LibraryAvailability: String, Codable, Equatable, Sendable, CaseIterable {
  case subscription
  case purchased
  case matched
  case uploaded
  case other
}

public struct LibraryTrack: Codable, Equatable, Sendable, Identifiable {
  public enum BulkColumnsError: Error, Equatable, LocalizedError, Sendable {
    case missingRequiredField(String, index: Int)

    public var errorDescription: String? {
      switch self {
      case .missingRequiredField(let field, let index):
        "Music library data is missing required field '\(field)' at track \(index)."
      }
    }
  }

  public var persistentID: String
  public var name: String
  public var artist: String
  public var albumArtist: String
  public var album: String
  public var genre: String?
  public var year: Int?
  public var durationSeconds: Double?
  public var playCount: Int
  public var skipCount: Int
  public var favorited: Bool
  public var disliked: Bool
  public var rating: Int?
  public var dateAdded: Date?
  public var lastPlayed: Date?
  public var availability: LibraryAvailability
  public var id: String { persistentID }

  public init(
    persistentID: String, name: String, artist: String, albumArtist: String = "",
    album: String = "", genre: String? = nil, year: Int? = nil, durationSeconds: Double? = nil,
    playCount: Int = 0, skipCount: Int = 0, favorited: Bool = false, disliked: Bool = false, rating: Int? = nil,
    dateAdded: Date? = nil, lastPlayed: Date? = nil, availability: LibraryAvailability = .other
  ) {
    self.persistentID = persistentID
    self.name = name
    self.artist = artist
    self.albumArtist = albumArtist
    self.album = album
    self.genre = genre
    self.year = year
    self.durationSeconds = durationSeconds
    self.playCount = playCount
    self.skipCount = skipCount
    self.favorited = favorited
    self.disliked = disliked
    self.rating = rating
    self.dateAdded = dateAdded
    self.lastPlayed = lastPlayed
    self.availability = availability
  }

  /// Projects one row from ScriptingBridge's bulk KVC columns.
  /// Kept in Core so the property mapping is pure and directly testable.
  public init(bulkColumns: [String: [Any]], index: Int) throws {
    func value(_ key: String) -> Any? {
      guard let column = bulkColumns[key], column.indices.contains(index),
        !(column[index] is NSNull)
      else { return nil }
      return column[index]
    }
    func string(_ key: String) -> String? { value(key) as? String }
    func integer(_ key: String) -> Int? {
      (value(key) as? NSNumber)?.intValue ?? (value(key) as? Int)
    }
    func decimal(_ key: String) -> Double? {
      (value(key) as? NSNumber)?.doubleValue ?? (value(key) as? Double)
    }

    guard let persistentID = string("persistentID") else {
      throw BulkColumnsError.missingRequiredField("persistentID", index: index)
    }
    guard let name = string("name") else {
      throw BulkColumnsError.missingRequiredField("name", index: index)
    }
    guard let artist = string("artist") else {
      throw BulkColumnsError.missingRequiredField("artist", index: index)
    }
    let rawYear = integer("year")
    self.init(
      persistentID: persistentID,
      name: name,
      artist: artist,
      albumArtist: string("albumArtist") ?? "",
      album: string("album") ?? "",
      genre: string("genre"),
      year: rawYear == 0 ? nil : rawYear,
      durationSeconds: decimal("duration"),
      playCount: integer("playedCount") ?? 0,
      skipCount: integer("skippedCount") ?? 0,
      favorited: (value("favorited") as? NSNumber)?.boolValue
        ?? (value("favorited") as? Bool ?? false),
      disliked: (value("disliked") as? NSNumber)?.boolValue
        ?? (value("disliked") as? Bool ?? false),
      rating: integer("rating"),
      dateAdded: value("dateAdded") as? Date,
      lastPlayed: value("playedDate") as? Date,
      availability: Self.availability(from: value("cloudStatus")))
  }

  private static func availability(from value: Any?) -> LibraryAvailability {
    if let string = value as? String {
      switch string.lowercased() {
      case "subscription", "ksub": return .subscription
      case "purchased", "kpur": return .purchased
      case "matched", "kmat": return .matched
      case "uploaded", "kupl", "kupp", "krej": return .uploaded
      default: return .other
      }
    }
    guard let code = (value as? NSNumber)?.uint32Value else { return .other }
    return switch code {
    case Self.fourCC("kSub"): .subscription
    case Self.fourCC("kPur"): .purchased
    case Self.fourCC("kMat"): .matched
    case Self.fourCC("kUpl"), Self.fourCC("kUpP"), Self.fourCC("kRej"): .uploaded
    default: .other
    }
  }

  private static func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
  }

  private enum CodingKeys: String, CodingKey {
    case persistentID, name, artist, albumArtist, album, genre, year, durationSeconds
    case playCount, skipCount, favorited, disliked, rating, dateAdded, lastPlayed, availability
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    persistentID = try values.decode(String.self, forKey: .persistentID)
    name = try values.decode(String.self, forKey: .name)
    artist = try values.decode(String.self, forKey: .artist)
    albumArtist = try values.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
    album = try values.decodeIfPresent(String.self, forKey: .album) ?? ""
    genre = try values.decodeIfPresent(String.self, forKey: .genre)
    year = try values.decodeIfPresent(Int.self, forKey: .year)
    durationSeconds = try values.decodeIfPresent(Double.self, forKey: .durationSeconds)
    playCount = try values.decodeIfPresent(Int.self, forKey: .playCount) ?? 0
    skipCount = try values.decodeIfPresent(Int.self, forKey: .skipCount) ?? 0
    favorited = try values.decodeIfPresent(Bool.self, forKey: .favorited) ?? false
    disliked = try values.decodeIfPresent(Bool.self, forKey: .disliked) ?? false
    rating = try values.decodeIfPresent(Int.self, forKey: .rating)
    dateAdded = try values.decodeIfPresent(Date.self, forKey: .dateAdded)
    lastPlayed = try values.decodeIfPresent(Date.self, forKey: .lastPlayed)
    availability = try values.decodeIfPresent(LibraryAvailability.self, forKey: .availability) ?? .other
  }
}

public enum LibraryPlaylistKind: String, Codable, CaseIterable, Sendable {
  case user, smart, subscription
}

public struct LibraryPlaylist: Codable, Equatable, Sendable, Identifiable {
  public var persistentID: String
  public var name: String
  public var folder: String?
  public var kind: LibraryPlaylistKind
  public var members: [String]
  public var id: String { persistentID }

  public init(persistentID: String, name: String, folder: String? = nil, kind: LibraryPlaylistKind, members: [String]) {
    self.persistentID = persistentID
    self.name = name
    self.folder = folder
    self.kind = kind
    self.members = members
  }
}

public struct LibraryOutsideTrack: Codable, Equatable, Sendable {
  public var name: String
  public var artist: String
  public var album: String
  public var year: Int?
  public var durationSeconds: Double?

  public init(name: String, artist: String, album: String, year: Int? = nil, durationSeconds: Double? = nil) {
    self.name = name
    self.artist = artist
    self.album = album
    self.year = year
    self.durationSeconds = durationSeconds
  }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case format, version, generatedAt, trackCount, tracks, lastfm, playlists, outsideTracks
  }
  public static let formatName = "vf-library-snapshot"
  public static let currentVersion = 2
  public static let heavilyPlayedThreshold = 20
  public var format: String
  public var version: Int
  public var generatedAt: Date
  public var trackCount: Int
  public var tracks: [LibraryTrack]
  public var lastfm: Data?
  public var playlists: [LibraryPlaylist]
  public var outsideTracks: [String: LibraryOutsideTrack]

  public init(
    generatedAt: Date, tracks: [LibraryTrack], lastfm: Data? = nil, version: Int = currentVersion,
    playlists: [LibraryPlaylist] = [], outsideTracks: [String: LibraryOutsideTrack] = [:]
  ) {
    self.format = Self.formatName
    self.version = version
    self.generatedAt = generatedAt
    self.trackCount = tracks.count
    self.tracks = tracks
    self.lastfm = lastfm
    self.playlists = playlists
    self.outsideTracks = outsideTracks
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    format = try values.decode(String.self, forKey: .format)
    version = try values.decode(Int.self, forKey: .version)
    generatedAt = try values.decode(Date.self, forKey: .generatedAt)
    trackCount = try values.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    tracks = try values.decodeIfPresent([LibraryTrack].self, forKey: .tracks) ?? []
    lastfm = try values.decodeIfPresent(Data.self, forKey: .lastfm)
    playlists = try values.decodeIfPresent([LibraryPlaylist].self, forKey: .playlists) ?? []
    outsideTracks = try values.decodeIfPresent([String: LibraryOutsideTrack].self, forKey: .outsideTracks) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(format, forKey: .format)
    try container.encode(version, forKey: .version)
    try container.encode(generatedAt, forKey: .generatedAt)
    try container.encode(trackCount, forKey: .trackCount)
    try container.encode(tracks, forKey: .tracks)
    try container.encode(lastfm, forKey: .lastfm)
    try container.encode(playlists, forKey: .playlists)
    try container.encode(outsideTracks, forKey: .outsideTracks)
  }
}

public enum LibrarySnapshotCodecError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedFormat(String)
  case newerVersion(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedFormat(let value): "Unsupported library snapshot format: \(value)."
    case .newerVersion(let version):
      "Library snapshot version \(version) is newer than this app supports."
    }
  }
}

public enum LibrarySnapshotCodec {
  public static func encode(_ snapshot: LibrarySnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(iso8601(date))
    }
    return try encoder.encode(snapshot)
  }

  public static func decode(_ data: Data) throws -> LibrarySnapshot {
    struct Header: Decodable {
      var format: String
      var version: Int
    }
    let header = try JSONDecoder().decode(Header.self, from: data)
    guard header.format == LibrarySnapshot.formatName else {
      throw LibrarySnapshotCodecError.unsupportedFormat(header.format)
    }
    guard header.version <= LibrarySnapshot.currentVersion else {
      throw LibrarySnapshotCodecError.newerVersion(header.version)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      guard let date = parseISO8601(value) else {
        throw DecodingError.dataCorruptedError(
          in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO 8601 date.")
      }
      return date
    }
    return try decoder.decode(LibrarySnapshot.self, from: data)
  }

  // Format styles are values, so they're built once. A new `ISO8601DateFormatter` per date
  // made a real library (~87k tracks, two dates each) take over 20 s to encode or decode.
  private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let wholeSecondStyle = Date.ISO8601FormatStyle()

  private static func iso8601(_ date: Date) -> String {
    fractionalStyle.format(date)
  }

  private static func parseISO8601(_ value: String) -> Date? {
    (try? fractionalStyle.parse(value)) ?? (try? wholeSecondStyle.parse(value))
  }
}

public enum LibraryAnnotation: Equatable, Sendable {
  case inLibrary(plays: Int, lastPlayed: Date?, favorited: Bool, versionCount: Int)
  case notInLibrary
  case snapshotUnavailable
}
