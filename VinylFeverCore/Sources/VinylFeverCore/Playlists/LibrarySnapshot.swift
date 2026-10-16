import Foundation

public enum LibraryAvailability: String, Codable, Equatable, Sendable, CaseIterable {
  case subscription
  case purchased
  case matched
  case uploaded
  case other
}

public struct LibraryTrack: Codable, Equatable, Sendable, Identifiable {
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
  public var rating: Int?
  public var dateAdded: Date?
  public var lastPlayed: Date?
  public var availability: LibraryAvailability
  public var id: String { persistentID }

  public init(
    persistentID: String, name: String, artist: String, albumArtist: String = "",
    album: String = "", genre: String? = nil, year: Int? = nil, durationSeconds: Double? = nil,
    playCount: Int = 0, skipCount: Int = 0, favorited: Bool = false, rating: Int? = nil,
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
    self.rating = rating
    self.dateAdded = dateAdded
    self.lastPlayed = lastPlayed
    self.availability = availability
  }
}

public struct LibrarySnapshot: Codable, Equatable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case format, version, generatedAt, trackCount, tracks, lastfm
  }
  public static let formatName = "vf-library-snapshot"
  public static let currentVersion = 1
  public var format: String
  public var version: Int
  public var generatedAt: Date
  public var trackCount: Int
  public var tracks: [LibraryTrack]
  public var lastfm: Data?

  public init(
    generatedAt: Date, tracks: [LibraryTrack], lastfm: Data? = nil, version: Int = currentVersion
  ) {
    self.format = Self.formatName
    self.version = version
    self.generatedAt = generatedAt
    self.trackCount = tracks.count
    self.tracks = tracks
    self.lastfm = lastfm
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(format, forKey: .format)
    try container.encode(version, forKey: .version)
    try container.encode(generatedAt, forKey: .generatedAt)
    try container.encode(trackCount, forKey: .trackCount)
    try container.encode(tracks, forKey: .tracks)
    try container.encode(lastfm, forKey: .lastfm)
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

  private static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func parseISO8601(_ value: String) -> Date? {
    for options: ISO8601DateFormatter.Options in [
      [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
    ] {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }
}

public enum LibraryAnnotation: Equatable, Sendable {
  case inLibrary(plays: Int, lastPlayed: Date?, favorited: Bool, versionCount: Int)
  case notInLibrary
  case snapshotUnavailable
}
