import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

@Suite("Playlist roles")
struct PlaylistRolesTests {
  @Test("roles resolve by persistent ID, then only by a unique name")
  func roleMatching() {
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "current", name: "Selections", kind: .user, members: []),
      LibraryPlaylist(persistentID: "other-a", name: "Duplicate", kind: .user, members: []),
      LibraryPlaylist(persistentID: "other-b", name: "Duplicate", kind: .user, members: []),
    ])
    let roles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "old-id", name: "Selections", role: .keepers),
      PlaylistRoleEntry(persistentID: "old-duplicate", name: "Duplicate", role: .curated),
    ])
    let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
    #expect(resolved[0].role == .keepers)
    #expect(resolved[1].role == nil)
    #expect(resolved[2].role == nil)
    #expect(PlaylistRoleMatcher.missing(snapshot: snapshot, roles: roles).count == 1)
  }

  @Test("roles with a repeated persistent ID resolve with the first entry")
  func repeatedPersistentID() {
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "same", name: "One", kind: .user, members: []),
    ])
    let roles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "same", name: "One", role: .keepers),
      PlaylistRoleEntry(persistentID: "same", name: "One", role: .ignore),
    ])
    #expect(PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles).first?.role == .keepers)
  }

  @Test("suggestions include the 2018 cutoff and exact New Music name")
  func suggestions() {
    #expect(PlaylistRoleSuggestion.suggest(name: "2025: Jon's Selections", kind: .user, folder: nil) == .keepers)
    #expect(PlaylistRoleSuggestion.suggest(name: "Replay 2017", kind: .subscription, folder: nil) == .ignore)
    #expect(PlaylistRoleSuggestion.suggest(name: "Replay 2018", kind: .subscription, folder: nil) == .replay)
    #expect(PlaylistRoleSuggestion.suggest(name: "Replay All Time", kind: .subscription, folder: nil) == .ignore)
    #expect(PlaylistRoleSuggestion.suggest(name: "New Music", kind: .subscription, folder: nil) == .auditioned)
    #expect(PlaylistRoleSuggestion.suggest(name: "New Music Daily", kind: .subscription, folder: nil) == nil)
    #expect(PlaylistRoleSuggestion.suggest(name: "My Shazam Tracks", kind: .user, folder: nil) == .discoveryInbox)
    #expect(PlaylistRoleSuggestion.suggest(name: "Collection: Jazz", kind: .user, folder: nil) == .collection)
  }

  @Test("playlist roles codec rejects unknown values with the role name")
  func unknownRole() throws {
    let data = Data(#"{"format":"vf-playlist-roles","version":1,"updatedAt":"2026-10-23T00:00:00Z","playlists":[{"persistentID":"x","name":"X","role":"mystery"}]}"#.utf8)
    #expect(throws: PlaylistRolesError.unknownRole("mystery")) {
      try PlaylistRolesCodec.decode(data)
    }
  }

  @Test("song evidence groups playlist roles and identifies shared-account plays")
  func songEvidence() {
    let beforeCutoff = ISO8601DateFormatter().date(from: "2017-06-01T12:00:00Z")!
    let tracks = [
      LibraryTrack(persistentID: "song", name: "Song", artist: "Artist", playCount: 12, disliked: true, dateAdded: beforeCutoff),
    ]
    let playlists = [
      LibraryPlaylist(persistentID: "selection", name: "2025: Jon's Selections", kind: .user, members: ["song"]),
      LibraryPlaylist(persistentID: "replay", name: "Replay 2017", kind: .subscription, members: ["song"]),
    ]
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: tracks, playlists: playlists)
    let roles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "selection", name: "Selections", role: .keepers),
      PlaylistRoleEntry(persistentID: "replay", name: "Replay 2017", role: .replay),
    ])
    let identity = ArtistIdentity(aliases: [:], knownArtists: ["Artist"])
    let index = PlaylistIndex(snapshot: snapshot, roles: roles, identity: identity)
    let evidence = index.evidence(artist: "Artist", title: "Song", identity: identity, tracks: snapshot.tracks)
    #expect(evidence.playlists["keepers"] == ["2025: Jon's Selections"])
    #expect(evidence.playlists["replay"] == nil)
    #expect(evidence.disliked)
    #expect(!evidence.sharedAccountEra)

    let replayOnly = LibrarySnapshot(generatedAt: .now, tracks: tracks, playlists: [playlists[1]])
    let replayRoles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "replay", name: "Replay 2017", role: .replay),
    ])
    let oldReplayEvidence = PlaylistIndex(snapshot: replayOnly, roles: replayRoles, identity: identity)
      .evidence(artist: "Artist", title: "Song", identity: identity, tracks: replayOnly.tracks)
    #expect(oldReplayEvidence.sharedAccountEra)
    #expect(PlaylistRoleMatcher.resolve(snapshot: replayOnly, roles: replayRoles).first?.role == .ignore)
  }

  @Test("song evidence counts distinct playlists by role and caps reported names")
  func roleEvidenceCaps() {
    let track = LibraryTrack(persistentID: "song", name: "Song", artist: "Artist")
    let playlists = (0..<11).map { index in
      LibraryPlaylist(persistentID: "curated-\(index)", name: "Curated \(index)", kind: .user, members: ["song"])
    } + [
      LibraryPlaylist(persistentID: "ignore", name: "Ignore", kind: .user, members: ["song"]),
      LibraryPlaylist(persistentID: "followed", name: "Followed", kind: .user, members: ["song"]),
    ]
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [track], playlists: playlists)
    let roles = PlaylistRoles(updatedAt: .now, playlists: playlists.enumerated().map { index, playlist in
      PlaylistRoleEntry(persistentID: playlist.persistentID, name: playlist.name,
        role: index < 11 ? .curated : (index == 11 ? .ignore : .followed))
    })
    let identity = ArtistIdentity(aliases: [:], knownArtists: ["Artist"])
    let evidence = PlaylistIndex(snapshot: snapshot, roles: roles, identity: identity)
      .evidence(artist: "Artist", title: "Song", identity: identity, tracks: [track])
    #expect(evidence.playlists["curated"]?.count == 10)
    #expect(evidence.playlistCounts["curated"] == 11)
    #expect(evidence.playlists["ignore"] == nil)
    #expect(evidence.playlists["followed"] == nil)
  }
}
