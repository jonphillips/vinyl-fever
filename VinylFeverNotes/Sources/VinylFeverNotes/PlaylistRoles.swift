import Foundation

public enum SelectionPlaylistName {
  public static let pattern = #"^\d{4}: Jon's Selections$"#
}

public enum PlaylistRole: String, Codable, CaseIterable, Sendable {
  case keepers, replay, curated, situational, auditioned, discoveryInbox = "discovery-inbox"
  case followed, appleMix = "apple-mix", collection, vinylFever = "vinyl-fever", ignore
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
  case unsupportedFormat(String), unsupportedVersion(Int), unknownRole(String)
  public var errorDescription: String? {
    switch self {
    case .unsupportedFormat(let value): "Unsupported playlist roles format: \(value)."
    case .unsupportedVersion(let value): "Playlist roles version \(value) is not supported."
    case .unknownRole(let value): "Unknown playlist role '\(value)'."
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
    if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rows = object["playlists"] as? [[String: Any]] {
      for row in rows {
        if let role = row["role"] as? String, PlaylistRole(rawValue: role) == nil {
          throw PlaylistRolesError.unknownRole(role)
        }
      }
    }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(PlaylistRoles.self, from: data)
  }
}
