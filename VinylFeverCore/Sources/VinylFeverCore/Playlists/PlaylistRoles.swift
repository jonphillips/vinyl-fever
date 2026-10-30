import Foundation
import VinylFeverListening
@_exported import VinylFeverNotes

public struct ResolvedPlaylistRole: Equatable, Sendable {
  public var playlist: LibraryPlaylist
  public var role: PlaylistRole?
}

public enum PlaylistRoleMatcher {
  public static func resolve(snapshot: LibrarySnapshot, roles: PlaylistRoles) -> [ResolvedPlaylistRole] {
    let byID = Dictionary(roles.playlists.map { ($0.persistentID, $0.role) }, uniquingKeysWith: { first, _ in first })
    let counts = Dictionary(grouping: snapshot.playlists, by: \.name).mapValues(\.count)
    let byName = Dictionary(grouping: roles.playlists, by: \.name)
    return snapshot.playlists.map { playlist in
      let saved = byID[playlist.persistentID] ?? (counts[playlist.name] == 1 ? byName[playlist.name]?.first?.role : nil)
      let matched = saved == .replay && PlaylistRoleSuggestion.isPreCutoffReplay(playlist.name) ? .ignore : saved
      return ResolvedPlaylistRole(playlist: playlist, role: matched)
    }
  }

  public static func missing(snapshot: LibrarySnapshot, roles: PlaylistRoles) -> [PlaylistRoleEntry] {
    let present = Set(snapshot.playlists.map(\.persistentID))
    let nameCounts = Dictionary(grouping: snapshot.playlists, by: \.name).mapValues(\.count)
    return roles.playlists.filter { entry in
      entry.pendingSince == nil && !present.contains(entry.persistentID) && nameCounts[entry.name] != 1
    }
  }

  public static func pending(roles: PlaylistRoles) -> [PlaylistRoleEntry] {
    roles.playlists.filter { $0.pendingSince != nil }
  }
}

public struct PlaylistRoleAdoptionResult: Equatable, Sendable {
  public var roles: PlaylistRoles
  public var didWrite: Bool

  public init(roles: PlaylistRoles, didWrite: Bool) {
    self.roles = roles
    self.didWrite = didWrite
  }
}

public enum PlaylistRoleAdoption {
  public static func adopt(snapshot: LibrarySnapshot, roles: PlaylistRoles, updatedAt: Date) -> PlaylistRoleAdoptionResult {
    let byName = Dictionary(grouping: snapshot.playlists, by: \.name)
    var heldIDs = Set(roles.playlists.filter { $0.pendingSince == nil }.map(\.persistentID))
    var changed = false
    let entries = roles.playlists.map { entry -> PlaylistRoleEntry in
      guard entry.pendingSince != nil,
        let matches = byName[entry.name]?.filter({ !heldIDs.contains($0.persistentID) }),
        matches.count == 1
      else { return entry }
      heldIDs.insert(matches[0].persistentID)
      changed = true
      return PlaylistRoleEntry(persistentID: matches[0].persistentID, name: entry.name, role: entry.role)
    }
    guard changed else { return PlaylistRoleAdoptionResult(roles: roles, didWrite: false) }
    return PlaylistRoleAdoptionResult(
      roles: PlaylistRoles(updatedAt: updatedAt, playlists: entries, version: roles.version), didWrite: true
    )
  }
}

public struct PlaylistRoleAutoLabelResult: Equatable, Sendable {
  public var roles: PlaylistRoles
  public var labeled: [LibraryPlaylist]

  public init(roles: PlaylistRoles, labeled: [LibraryPlaylist]) {
    self.roles = roles
    self.labeled = labeled
  }
}

public enum PlaylistRoleAutoLabeling {
  /// Applies only Vinyl Fever's own role, leaving every existing role untouched.
  public static func applyVinylFeverRole(
    snapshot: LibrarySnapshot, roles: PlaylistRoles, createdNames: Set<String>, updatedAt: Date
  ) -> PlaylistRoleAutoLabelResult {
    let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
    let labeled = resolved.compactMap { row -> LibraryPlaylist? in
      guard row.role == nil,
        PlaylistRoleSuggestion.suggest(name: row.playlist.name, kind: row.playlist.kind,
          folder: row.playlist.folder, createdNames: createdNames) == .vinylFever
      else { return nil }
      return row.playlist
    }
    guard !labeled.isEmpty else { return PlaylistRoleAutoLabelResult(roles: roles, labeled: []) }
    let entries = labeled.map { PlaylistRoleEntry(persistentID: $0.persistentID, name: $0.name, role: .vinylFever) }
    return PlaylistRoleAutoLabelResult(
      roles: PlaylistRoles(updatedAt: updatedAt, playlists: roles.playlists + entries), labeled: labeled
    )
  }
}

public enum PlaylistRoleSuggestion {
  /// M17 S1 defines this local-time boundary for separating shared-family Mac play history.
  public static let sharedAccountCutoffYear = 2018
  public static let sharedAccountCutoff: Date = {
    Calendar.current.date(from: DateComponents(year: sharedAccountCutoffYear, month: 1, day: 1))!
  }()

  public static func suggest(name: String, kind: LibraryPlaylistKind, folder: String?, createdNames: Set<String> = []) -> PlaylistRole? {
    if name.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil { return .keepers }
    if name == "Replay All Time" { return .ignore }
    if let match = name.range(of: #"^Replay (\d{4})$"#, options: .regularExpression) {
      let yearText = name[match].split(separator: " ").last ?? "0"
      return (Int(yearText) ?? 0) >= sharedAccountCutoffYear ? .replay : .ignore
    }
    if kind == .subscription && name == "New Music" { return .auditioned }
    if name == "My Shazam Tracks" { return .discoveryInbox }
    if name.hasPrefix("Collection: ") { return .collection }
    if createdNames.contains(name) { return .vinylFever }
    return nil
  }

  public static func isPreCutoffReplay(_ name: String) -> Bool {
    guard name.range(of: #"^Replay \d{4}$"#, options: .regularExpression) != nil,
      let year = Int(name.split(separator: " ").last ?? "0") else { return false }
    return year < sharedAccountCutoffYear
  }
}

public struct PlaylistIndex: Sendable {
  public struct Membership: Equatable, Sendable {
    public var playlistName: String
    public var role: PlaylistRole?
    public var position: Int
  }
  public let membershipsBySong: [String: [Membership]]

  public init(snapshot: LibrarySnapshot, roles: PlaylistRoles, identity: ArtistIdentity) {
    let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
    var result: [String: [Membership]] = [:]
    let tracksByID = Dictionary(uniqueKeysWithValues: snapshot.tracks.map { ($0.persistentID, $0) })
    let artists = Set(snapshot.tracks.map(\.artist) + snapshot.outsideTracks.values.map(\.artist))
    let artistCredits = Dictionary(uniqueKeysWithValues: artists.map { artist in
      let folded = artist.lowercased()
      let hasCollaboratorMarker = artist.contains("&") || artist.contains("+") || artist.contains(",") ||
        [" and ", " x ", " vs ", " feat", " ft.", " with "].contains(where: folded.contains)
      return (artist, hasCollaboratorMarker ? identity.credits(artist) : Set([identity.key(artist)]))
    })
    for row in resolved {
      for (position, persistentID) in row.playlist.members.enumerated() {
        let track = tracksByID[persistentID]
        let outside = snapshot.outsideTracks[persistentID]
        guard let title = track?.name ?? outside?.name,
          let artist = track?.artist ?? outside?.artist else { continue }
        for artistKey in artistCredits[artist] ?? [identity.key(artist)] {
          let key = "\(artistKey)|\(SongTextNormalizer.libraryTitle(title))"
          result[key, default: []].append(Membership(playlistName: row.playlist.name, role: row.role, position: position + 1))
        }
      }
    }
    membershipsBySong = result
  }

  public func evidence(artist: String, title: String, identity: ArtistIdentity, tracks: [LibraryTrack]) -> PlaylistSongEvidence {
    let key = "\(identity.key(artist))|\(SongTextNormalizer.libraryTitle(title))"
    let matchingTracks = tracks
    let memberships = membershipsBySong[key, default: []].filter { $0.role != .ignore && $0.role != .followed }
    let grouped = Dictionary(grouping: memberships.compactMap { item -> (String, String)? in
      guard let role = item.role else { return nil }
      return (role.rawValue, item.playlistName)
    }, by: \.0)
    let playlists = Dictionary(uniqueKeysWithValues: grouped.map { role, values in
      (role, Array(Set(values.map(\.1))).sorted())
    })
    let choosing = Set([PlaylistRole.keepers, .curated, .situational, .replay])
    let hasChoosingPlaylist = memberships.contains { membership in
      guard let role = membership.role, choosing.contains(role) else { return false }
      if role == .replay {
        let year = Int(membership.playlistName.split(separator: " ").last ?? "0") ?? 0
        return year >= PlaylistRoleSuggestion.sharedAccountCutoffYear
      }
      return true
    }
    let allBeforeCutoff = !matchingTracks.isEmpty && matchingTracks.allSatisfy { track in
      guard let dateAdded = track.dateAdded else { return false }
      return dateAdded < PlaylistRoleSuggestion.sharedAccountCutoff
    }
    return PlaylistSongEvidence(playlists: playlists, playlistCounts: playlists.mapValues(\.count),
      disliked: matchingTracks.contains(where: \.disliked), sharedAccountEra: allBeforeCutoff && !hasChoosingPlaylist)
  }
}

public struct PlaylistSongEvidence: Codable, Equatable, Sendable {
  /// The S1 tool contract caps each role's playlist names at ten to keep evidence compact.
  public static let maximumPlaylistNamesPerRole = 10
  public var playlists: [String: [String]]
  public var playlistCounts: [String: Int]
  public var disliked: Bool
  public var sharedAccountEra: Bool
  public init(playlists: [String: [String]], playlistCounts: [String: Int], disliked: Bool, sharedAccountEra: Bool) {
    self.playlists = playlists.mapValues { Array($0.prefix(Self.maximumPlaylistNamesPerRole)) }
    self.playlistCounts = playlistCounts
    self.disliked = disliked
    self.sharedAccountEra = sharedAccountEra
  }
}
