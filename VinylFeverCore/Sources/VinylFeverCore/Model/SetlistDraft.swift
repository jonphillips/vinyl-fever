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
  /// A trading-note annotation the Normalizer chose to keep with the track (e.g.
  /// `>` segue, guest performer). Preview/audit only — it is **not** rendered into
  /// the stacked track list of `setlist.txt` (the format keeps tracks plain).
  public var note: String?

  public init(id: UUID, title: String, note: String? = nil) {
    self.id = id
    self.title = title
    self.note = note
  }
}

public struct ShowTags: Equatable, Sendable {
  public var artist: Field
  public var album: Field
  public var albumArtist: Field
  public var date: DateField
  public var venue: Field
  public var location: Field
  /// The recording source, drawn from the controlled vocabulary (`SourceLabel`).
  /// A first-class field rather than a substring of `album`: the Normalizer infers
  /// it (with evidence) and the composed `ALBUM` line derives its `(Source)` suffix
  /// from it. `.unknown` renders as `(unknown)`.
  public var source: Field

  public init(
    artist: Field = .unknown,
    album: Field = .unknown,
    albumArtist: Field = .unknown,
    date: DateField = .unknown,
    venue: Field = .unknown,
    location: Field = .unknown,
    source: Field = .unknown
  ) {
    self.artist = artist
    self.album = album
    self.albumArtist = albumArtist
    self.date = date
    self.venue = venue
    self.location = location
    self.source = source
  }

  /// Fills missing show fields from the app's `YYYY-MM-DD: Location - Venue` album title.
  /// Explicit tag values remain authoritative.
  public func fillingFieldsFromAlbum() -> ShowTags {
    guard case let .value(album) = album else {
      return self
    }

    let prefix = String(album.prefix(10))
    guard
      prefix.count == 10,
      let delimiter = album.index(album.startIndex, offsetBy: 10, limitedBy: album.endIndex),
      album[delimiter...].hasPrefix(": ")
    else {
      return self
    }

    let date = DateField(isoString: prefix)
    guard case .iso = date else {
      return self
    }

    let detailsStart = album.index(delimiter, offsetBy: 2)
    let details = String(album[detailsStart...])
    guard let separator = details.range(of: " - ") else {
      return self
    }

    let locationText = String(details[..<separator.lowerBound])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let venueText = Self.removingTrailingParentheticalGroups(
      from: String(details[separator.upperBound...])
    )
    let venueValue = venueText.trimmingCharacters(in: .whitespacesAndNewlines)
    return fillingAvailableFields(date: date, location: locationText, venue: venueValue)
  }

  private func fillingAvailableFields(date parsedDate: DateField, location: String, venue: String) -> ShowTags {
    var tags = self
    if case .unknown = tags.date {
      tags.date = parsedDate
    }
    if case .unknown = tags.location, !location.isEmpty,
       location.caseInsensitiveCompare("Unknown City") != .orderedSame {
      tags.location = Field(location)
    }
    if case .unknown = tags.venue, !venue.isEmpty,
       venue.caseInsensitiveCompare("Unknown Venue") != .orderedSame {
      tags.venue = Field(venue)
    }
    return tags
  }

  private static func removingTrailingParentheticalGroups(from text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while result.last == ")" {
      var depth = 0
      var matchingOpen: String.Index?
      var index = result.index(before: result.endIndex)
      while true {
        if result[index] == ")" {
          depth += 1
        } else if result[index] == "(" {
          depth -= 1
          if depth == 0 {
            matchingOpen = index
            break
          }
        }
        guard index > result.startIndex else { break }
        index = result.index(before: index)
      }
      guard let matchingOpen else { break }
      result = String(result[..<matchingOpen]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return result
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
