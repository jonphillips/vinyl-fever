import Foundation
import Testing
import VinylFeverNotes

@Suite("Playlist Catchup")
struct PlaylistCatchupTests {
  @Test("uses the latest snapshot for each tracked playlist and deduplicates with all sources")
  func latestAndDeduplication() {
    let old = snapshot("Antidote", id: "playlist-a", modified: 1, tracks: [
      track("old", "Old Song", artist: "Band")
    ])
    let antidote = snapshot("Antidote", id: "playlist-a", modified: 3, tracks: [
      track("song-a", "New Song", artist: "The Band", releaseDate: "2026-02-01")
    ])
    let altCtrl = snapshot("ALT-CTRL", id: "playlist-b", modified: 2, tracks: [
      track("song-b", "New Song", artist: "Band", dateAdded: Date(timeIntervalSince1970: 1_800_000_000)),
      track("song-c", "Second Song", artist: "Singer", releaseDate: "2025-03-01")
    ])

    let songs = PlaylistCatchup.make(snapshots: [old, antidote, altCtrl], heardTrackKeys: [], keeperTrackKeys: [])
    #expect(songs.map(\.id) == ["song-b", "song-c"])
    #expect(songs[0].sources == ["ALT-CTRL", "Antidote"])
    #expect(songs[0].dateAdded == Date(timeIntervalSince1970: 1_800_000_000))
  }

  @Test("removes heard, kept, and current weekly songs")
  func excludesKnownSongs() {
    let value = snapshot("Antidote", id: "playlist", modified: 1, tracks: [
      track("heard", "Heard", artist: "Artist"),
      track("kept", "Kept", artist: "Artist"),
      track("weekly", "Weekly", artist: "Artist"),
      track("new", "New", artist: "Artist"),
    ])
    let songs = PlaylistCatchup.make(snapshots: [value],
      heardTrackKeys: [ListeningTextNormalizer.trackKey(artist: "Artist", title: "Heard")],
      keeperTrackKeys: [ListeningTextNormalizer.trackKey(artist: "Artist", title: "Kept")],
      currentWeeklyCatalogIDs: ["weekly"])
    #expect(songs.map(\.id) == ["new"])
  }

  @Test("orders newest first and filters by one source")
  func orderingAndFilter() {
    let first = snapshot("Antidote", id: "a", modified: 1, tracks: [
      track("older", "Older", artist: "A", releaseDate: "2025-01-01"),
      track("shared", "Shared", artist: "B", releaseDate: "2026-01-01"),
    ])
    let second = snapshot("AltPop", id: "b", modified: 1, tracks: [
      track("shared", "Shared", artist: "B", releaseDate: "2026-01-01"),
      track("newest", "Newest", artist: "C", releaseDate: "2027-01-01"),
    ])
    let songs = PlaylistCatchup.make(snapshots: [first, second], heardTrackKeys: [], keeperTrackKeys: [])
    #expect(songs.map(\.id) == ["newest", "shared", "older"])
    #expect(PlaylistCatchup.filtered(songs, source: "Antidote").map(\.id) == ["shared", "older"])
    #expect(PlaylistCatchup.sources(in: songs) == ["AltPop", "Antidote"])
  }

  @Test("round trips tracked snapshots and ignores unreadable lines")
  func snapshotCodec() throws {
    let value = snapshot("Antidote", id: "playlist", modified: 1,
      tracks: [track("song", "Song", artist: "Artist", dateAdded: Date(timeIntervalSince1970: 10))])
    let encoded = try TrackedPlaylistExposureCodec.encode(value)
    let decoded = TrackedPlaylistExposureCodec.readFiles([Data("{bad}\n".utf8) + encoded])
    #expect(decoded == [.snapshot(value)])
  }

  @Test("the tracked role reads")
  func trackedRole() throws {
    let data = Data(#"{"format":"vf-playlist-roles","version":1,"updatedAt":"2026-11-27T12:00:00Z","playlists":[{"persistentID":"a","name":"Antidote","role":"tracked"}]}"#.utf8)
    #expect(try PlaylistRolesCodec.decode(data).playlists.map(\.role) == [.tracked])
    #expect(PlaylistRole.allCases.contains(.tracked))
  }

  @Test("role decoding retains unfamiliar values for a later writer")
  func unknownRoleIsSkipped() throws {
    let data = Data(#"{"format":"vf-playlist-roles","version":1,"updatedAt":"2026-10-30T12:00:00Z","playlists":[{"persistentID":"a","name":"Known","role":"keepers"},{"persistentID":"b","name":"Future","role":"new-future-role"}]}"#.utf8)
    let roles = try PlaylistRolesCodec.decode(data)
    #expect(roles.playlists.map(\.name) == ["Known", "Future"])
    #expect(roles.playlists.last?.role.rawValue == "new-future-role")
    let roundTrip = try PlaylistRolesCodec.decode(PlaylistRolesCodec.encode(roles))
    #expect(roundTrip == roles)
  }

  private func snapshot(_ name: String, id: String, modified: TimeInterval,
    tracks: [TrackedPlaylistTrack]) -> TrackedPlaylistSnapshot {
    TrackedPlaylistSnapshot(name: name, catalogID: id, lastModifiedDate: Date(timeIntervalSince1970: modified),
      fetchedAt: Date(timeIntervalSince1970: modified), host: "Mac", tracks: tracks)
  }

  private func track(_ id: String, _ title: String, artist: String, releaseDate: String? = nil,
    dateAdded: Date? = nil) -> TrackedPlaylistTrack {
    TrackedPlaylistTrack(catalogID: id, title: title, artist: artist,
      releaseDate: releaseDate, dateAdded: dateAdded)
  }
}
