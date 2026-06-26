import Foundation

public struct SetlistDraft: Equatable, Sendable {
  public var tags: ShowTags
  public var tracks: [SetlistTrack]

  public init(tags: ShowTags = ShowTags(), tracks: [SetlistTrack] = []) {
    self.tags = tags
    self.tracks = tracks
  }
}

public struct SetlistTrack: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var title: String

  public init(id: UUID, title: String) {
    self.id = id
    self.title = title
  }
}

public struct ShowTags: Equatable, Sendable {
  public var artist: Field
  public var album: Field
  public var albumArtist: Field
  public var date: DateField
  public var venue: Field
  public var location: Field

  public init(
    artist: Field = .unknown,
    album: Field = .unknown,
    albumArtist: Field = .unknown,
    date: DateField = .unknown,
    venue: Field = .unknown,
    location: Field = .unknown
  ) {
    self.artist = artist
    self.album = album
    self.albumArtist = albumArtist
    self.date = date
    self.venue = venue
    self.location = location
  }
}

public enum Field: Equatable, Sendable {
  case value(String)
  case unknown

  public init(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    self = trimmed.isEmpty ? .unknown : .value(trimmed)
  }

  public var text: String {
    get {
      switch self {
      case let .value(value):
        value
      case .unknown:
        ""
      }
    }
    set {
      self = Self(newValue)
    }
  }

  public var displayText: String {
    switch self {
    case let .value(value):
      value
    case .unknown:
      "Unknown"
    }
  }
}

public enum DateField: Equatable, Sendable {
  case iso(year: Int, month: Int, day: Int)
  case unknown

  public init(isoString: String) {
    let trimmed = isoString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      trimmed.count == 10,
      trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-",
      trimmed[trimmed.index(trimmed.startIndex, offsetBy: 7)] == "-",
      let year = Int(trimmed.prefix(4)),
      let month = Int(trimmed.dropFirst(5).prefix(2)),
      let day = Int(trimmed.suffix(2)),
      (1...12).contains(month),
      (1...31).contains(day)
    else {
      self = .unknown
      return
    }
    self = .iso(year: year, month: month, day: day)
  }

  public var text: String {
    get {
      switch self {
      case let .iso(year, month, day):
        "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
      case .unknown:
        ""
      }
    }
    set {
      self = Self(isoString: newValue)
    }
  }

  public var displayText: String {
    text.isEmpty ? "Unknown Date" : text
  }
}
