import Foundation

public enum PlaylistSongSource: String, Equatable, Sendable {
  case catalog, libraryUpload
}

public struct PlaylistSongReference: Equatable, Sendable {
  public var id: String
  public var source: PlaylistSongSource
  public init(id: String, source: PlaylistSongSource) { self.id = id; self.source = source }
}

public struct PlaylistSongPayload: Encodable, Equatable, Sendable {
  public var id: String
  public var type: String
  public init(_ reference: PlaylistSongReference) {
    id = reference.id
    type = reference.source == .libraryUpload ? "library-songs" : "songs"
  }
}

public enum AppleMusicPlaylistRequestEncoder {
  public static func createBody(name: String, description: String?, songs: [PlaylistSongReference]) throws -> Data {
    try JSONEncoder().encode(CreateBody(
      attributes: .init(name: name, description: description),
      relationships: .init(tracks: .init(data: songs.map(PlaylistSongPayload.init)))))
  }

  public static func appendBody(songs: [PlaylistSongReference]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(TracksBody(data: songs.map(PlaylistSongPayload.init)))
  }

  private struct CreateBody: Encodable {
    var attributes: Attributes
    var relationships: Relationships
    struct Attributes: Encodable { var name: String; var description: String? }
    struct Relationships: Encodable { var tracks: Tracks }
    struct Tracks: Encodable { var data: [PlaylistSongPayload] }
  }
  private struct TracksBody: Encodable { var data: [PlaylistSongPayload] }
}

public struct KeepPlaylist: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var isChecked: Bool
  public var isAlreadyThere: Bool
  public var isDisabled: Bool { isAlreadyThere }
  public init(id: String, name: String, isChecked: Bool, isAlreadyThere: Bool = false) {
    self.id = id; self.name = name; self.isChecked = isChecked; self.isAlreadyThere = isAlreadyThere
  }
}

public enum PlaylistKeepOptions {
  public static let rolesReadFallback = "Couldn't read your playlist roles, so only Selections and Vinyl Fever Keepers are shown."

  /// Apple Music release dates are calendar dates; UTC prevents local midnight from changing the year.
  public static func releaseYear(from releaseDate: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.component(.year, from: releaseDate)
  }

  public static func make(
    roles: PlaylistRoles?, editablePlaylists: [(id: String, name: String)], year: Int?
  ) -> (playlists: [KeepPlaylist], rolesReadFallback: Bool) {
    let targets: [(id: String, name: String)]
    if let roles {
      let names = Set(roles.playlists.filter { $0.role == .keepers }.map(\.name))
      targets = editablePlaylists.filter { names.contains($0.name) }
    } else {
      targets = editablePlaylists.filter {
        $0.name == "Vinyl Fever Keepers" || $0.name.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil
      }
    }

    let ordered = targets.sorted { $0.name < $1.name }
    let selectionName = year.flatMap { $0 >= 2020 ? "\($0): Jon's Selections" : nil }
    let options = ordered.map { playlist in
      KeepPlaylist(id: playlist.id, name: playlist.name,
        isChecked: playlist.name == "Vinyl Fever Keepers" || playlist.name == selectionName)
    }
    let sorted = options.sorted { lhs, rhs in
      if lhs.name == "Vinyl Fever Keepers" { return true }
      if rhs.name == "Vinyl Fever Keepers" { return false }
      if lhs.name == selectionName { return true }
      if rhs.name == selectionName { return false }
      return lhs.name < rhs.name
    }
    return (sorted, roles == nil)
  }
}
