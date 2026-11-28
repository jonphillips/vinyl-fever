import Foundation

public enum SelectionPlaylistName {
  public static let pattern = #"^\d{4}: Jon's Selections$"#
}

public struct PlaylistRole: RawRepresentable, Codable, CaseIterable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let keepers = Self(rawValue: "keepers")
  public static let replay = Self(rawValue: "replay")
  public static let curated = Self(rawValue: "curated")
  public static let situational = Self(rawValue: "situational")
  public static let auditioned = Self(rawValue: "auditioned")
  public static let discoveryInbox = Self(rawValue: "discovery-inbox")
  public static let followed = Self(rawValue: "followed")
  public static let tracked = Self(rawValue: "tracked")
  public static let appleMix = Self(rawValue: "apple-mix")
  public static let collection = Self(rawValue: "collection")
  public static let vinylFever = Self(rawValue: "vinyl-fever")
  public static let ignore = Self(rawValue: "ignore")
  public static let allCases = [keepers, replay, curated, situational, auditioned, discoveryInbox,
    followed, tracked, appleMix, collection, vinylFever, ignore]

  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self.init(rawValue: value)
  }

  public func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    try value.encode(rawValue)
  }
}

public struct PlaylistRoleEntry: Codable, Equatable, Sendable {
  public var persistentID: String
  public var name: String
  public var role: PlaylistRole
  public var pendingSince: Date?
  public init(persistentID: String, name: String, role: PlaylistRole, pendingSince: Date? = nil) {
    self.persistentID = persistentID; self.name = name; self.role = role; self.pendingSince = pendingSince
  }
}

public struct PlaylistRoles: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var updatedAt: Date
  public var playlists: [PlaylistRoleEntry]
  public init(updatedAt: Date, playlists: [PlaylistRoleEntry], version: Int = 1) {
    format = "vf-playlist-roles"; self.version = version; self.updatedAt = updatedAt; self.playlists = playlists
  }
}

public enum PlaylistRolesError: Error, Equatable, LocalizedError, Sendable {
  case unsupportedFormat(String), unsupportedVersion(Int)
  public var errorDescription: String? {
    switch self {
    case .unsupportedFormat(let value): "Unsupported playlist roles format: \(value)."
    case .unsupportedVersion(let value): "Playlist roles version \(value) is not supported."
    }
  }
}

public enum PlaylistRolesCodec {
  public static func encode(_ value: PlaylistRoles) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }

  public static func decode(_ data: Data) throws -> PlaylistRoles {
    struct Header: Decodable { var format: String; var version: Int }
    let header = try JSONDecoder().decode(Header.self, from: data)
    guard header.format == "vf-playlist-roles" else { throw PlaylistRolesError.unsupportedFormat(header.format) }
    guard header.version == 1 else { throw PlaylistRolesError.unsupportedVersion(header.version) }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(PlaylistRoles.self, from: data)
  }
}
