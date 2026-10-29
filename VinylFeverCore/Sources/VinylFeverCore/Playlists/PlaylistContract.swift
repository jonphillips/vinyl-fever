import Foundation
import CoreFoundation
import LLMHandoffKit

public struct TrackRequest: Equatable, Sendable {
  public let index: Int
  public let artist: String
  public let title: String
  public let album: String?
  public let year: Int?

  public init(index: Int, artist: String, title: String, album: String? = nil, year: Int? = nil) {
    self.index = index
    self.artist = artist
    self.title = title
    self.album = album
    self.year = year
  }
}

public struct PlaylistRequest: Equatable, Sendable {
  public let name: String
  public let description: String?
  public let tracks: [TrackRequest]

  public init(name: String, description: String? = nil, tracks: [TrackRequest]) {
    self.name = name
    self.description = description
    self.tracks = tracks
  }
}

public struct DroppedPlaylistTrack: Equatable, Sendable {
  public let index: Int
  public let artist: String
  public let title: String

  public init(index: Int, artist: String, title: String) {
    self.index = index
    self.artist = artist
    self.title = title
  }
}

public struct PlaylistDecodeResult: Equatable, Sendable {
  public let request: PlaylistRequest
  public let warning: String?
  public let droppedTracks: [DroppedPlaylistTrack]

  public init(request: PlaylistRequest, warning: String?, droppedTracks: [DroppedPlaylistTrack]) {
    self.request = request
    self.warning = warning
    self.droppedTracks = droppedTracks
  }
}

public enum PlaylistContractError: LocalizedError, Equatable, Sendable {
  case invalidJSON
  case invalidShape(String)
  case unsupportedMarker(found: String, expected: String)

  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      "The playlist reply isn't valid JSON. Copy the complete playlist block from your Project."
    case let .invalidShape(detail):
      "The playlist reply doesn't match the Vinyl Fever contract: \(detail)"
    case let .unsupportedMarker(found, expected):
      "This result uses a newer playlist contract (\(found)) than this app understands (\(expected)). Update Vinyl Fever, or re-copy the instructions from Settings."
    }
  }
}

public enum PlaylistContract {
  public static let marker = HandoffContractMarker(
    prefix: "VF-PLAYLIST",
    version: "v1",
    remediation: "re-copy the instructions from Settings."
  )

  private static let formatInstructionsBeforeRules = """
  When Jon asks you to emit the playlist, reply with exactly this format: a marker line, then one JSON object. Do not include a code fence, preamble, or sign-off. Use straight ASCII quotes.

  VF-PLAYLIST: v1
  {"name":"Playlist name","description":"optional one sentence","tracks":[{"artist":"Artist name","title":"Song title","album":"optional album hint","year":1979}]}

  """ + "\n"

  public static let trackRules = """
  The JSON object must have a non-empty name and at least one track. Each track needs artist and title; album is an optional hint. year is the original release year: `stage_playlist` requires it on every track, with null when you can't verify it. For one of Jon's own recordings, such as a live show, set album to the exact album name from his library. Omit any track you are not confident exists as a released recording by that artist; do not substitute another song. Include a specific version in the title only when that version is the point, such as "Song (Live at the Fillmore)". Do not include IDs, ISRCs, URLs, or commentary fields.
  """

  public static let formatInstructions = formatInstructionsBeforeRules
    + "This format applies only when Jon asks you to emit the playlist. Otherwise, continue the conversation normally.\n"
  public static let projectInstructions = formatInstructionsBeforeRules + trackRules + "\n\n"
    + "This format applies only when Jon asks you to emit the playlist. Otherwise, continue the conversation normally.\n"

  /// Decodes the pinned marker plus one JSON object. Invalid tracks with blank artist or title
  /// are omitted and returned in `droppedTracks` so the caller can show them to the user.
  public static func decode(_ pasted: String) throws -> PlaylistDecodeResult {
    let handoff: HandoffContractResult
    do {
      handoff = try marker.strippingMarker(from: pasted)
    } catch let error as HandoffContractError {
      if case let .unsupportedMarker(found, expected) = error {
        throw PlaylistContractError.unsupportedMarker(found: found, expected: expected)
      }
      throw PlaylistContractError.invalidShape(error.localizedDescription)
    }

    let body = stripWrappingFence(handoff.text)
    guard let root = parseJSON(body) ?? parseJSON(normalizeQuotes(body)) else {
      throw PlaylistContractError.invalidJSON
    }
    guard let object = root as? [String: Any] else {
      throw PlaylistContractError.invalidShape("expected one JSON object")
    }
    try requireOnly(keys: Set(["name", "description", "tracks"]), in: object, at: "playlist")

    guard let rawName = object["name"] as? String else {
      throw PlaylistContractError.invalidShape("name must be a string")
    }
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw PlaylistContractError.invalidShape("name must not be empty") }

    let description: String?
    if let rawDescription = object["description"] {
      guard let value = rawDescription as? String else {
        throw PlaylistContractError.invalidShape("description must be a string when present")
      }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      description = trimmed.isEmpty ? nil : trimmed
    } else {
      description = nil
    }

    guard let rawTracks = object["tracks"] as? [Any], !rawTracks.isEmpty else {
      throw PlaylistContractError.invalidShape("tracks must contain at least one track")
    }

    var tracks: [TrackRequest] = []
    var dropped: [DroppedPlaylistTrack] = []
    for (offset, rawTrack) in rawTracks.enumerated() {
      let index = offset + 1
      guard let track = rawTrack as? [String: Any] else {
        throw PlaylistContractError.invalidShape("track \(index) must be an object")
      }
      try requireOnly(keys: Set(["artist", "title", "album", "year"]), in: track, at: "track \(index)")
      let artist = try optionalString(track["artist"], field: "track \(index) artist") ?? ""
      let title = try optionalString(track["title"], field: "track \(index) title") ?? ""
      let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedArtist.isEmpty || trimmedTitle.isEmpty {
        dropped.append(DroppedPlaylistTrack(index: index, artist: trimmedArtist, title: trimmedTitle))
        continue
      }
      let album = try optionalString(track["album"], field: "track \(index) album")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let year = try optionalYear(track["year"], field: "track \(index) year")
      tracks.append(TrackRequest(
        index: index,
        artist: trimmedArtist,
        title: trimmedTitle,
        album: album?.isEmpty == true ? nil : album,
        year: year
      ))
    }
    return PlaylistDecodeResult(
      request: PlaylistRequest(name: name, description: description, tracks: tracks),
      warning: handoff.warning,
      droppedTracks: dropped
    )
  }

  private static func requireOnly(keys allowed: Set<String>, in object: [String: Any], at path: String) throws {
    let unexpected = Set(object.keys).subtracting(allowed).sorted()
    guard unexpected.isEmpty else {
      throw PlaylistContractError.invalidShape("\(path) contains unsupported field(s): \(unexpected.joined(separator: ", "))")
    }
  }

  private static func parseJSON(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  }

  private static func optionalString(_ value: Any?, field: String) throws -> String? {
    guard let value else { return nil }
    if value is NSNull { return nil }
    guard let string = value as? String else {
      throw PlaylistContractError.invalidShape("\(field) must be a string")
    }
    return string
  }

  private static func optionalYear(_ value: Any?, field: String) throws -> Int? {
    guard let value else { return nil }
    if value is NSNull { return nil }
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.rounded(.towardZero) == number.doubleValue,
      (1...9999).contains(number.intValue)
    else {
      throw PlaylistContractError.invalidShape("\(field) must be a four-digit year")
    }
    return number.intValue
  }

  private static func stripWrappingFence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = trimmed.components(separatedBy: .newlines)
    guard lines.count >= 3,
      lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true,
      lines.last?.trimmingCharacters(in: .whitespaces) == "```"
    else { return trimmed }
    return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizeQuotes(_ text: String) -> String {
    text
      .replacingOccurrences(of: "“", with: "\"")
      .replacingOccurrences(of: "”", with: "\"")
      .replacingOccurrences(of: "‘", with: "'")
      .replacingOccurrences(of: "’", with: "'")
  }
}
