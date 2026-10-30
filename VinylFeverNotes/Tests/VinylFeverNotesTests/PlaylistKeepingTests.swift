import Foundation
import Testing
import VinylFeverNotes

struct PlaylistKeepingTests {
  @Test func appendBodyKeepsTheAppleMusicRequestBytes() throws {
    let body = try AppleMusicPlaylistRequestEncoder.appendBody(songs: [
      PlaylistSongReference(id: "catalog-id", source: .catalog),
      PlaylistSongReference(id: "i.library-id", source: .libraryUpload),
    ])
    #expect(String(decoding: body, as: UTF8.self) ==
      #"{"data":[{"id":"catalog-id","type":"songs"},{"id":"i.library-id","type":"library-songs"}]}"#)
  }

  @Test func rolesCodecReadsThePlaylistRolesFileShape() throws {
    let data = Data(#"{"format":"vf-playlist-roles","version":1,"updatedAt":"2026-10-30T12:00:00Z","playlists":[{"persistentID":"keepers-id","name":"Vinyl Fever Keepers","role":"keepers"},{"persistentID":"selection-id","name":"2023: Jon's Selections","role":"keepers"}]}"#.utf8)
    let roles = try PlaylistRolesCodec.decode(data)
    #expect(roles.playlists.map(\.name) == ["Vinyl Fever Keepers", "2023: Jon's Selections"])
    #expect(roles.playlists.allSatisfy { $0.role == .keepers })
  }

  @Test func keepOptionsOrderAndPrecheckTargetsByYear() {
    let roles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "one", name: "Vinyl Fever Keepers", role: .keepers),
      PlaylistRoleEntry(persistentID: "two", name: "2023: Jon's Selections", role: .keepers),
      PlaylistRoleEntry(persistentID: "three", name: "Alternative JP", role: .keepers),
      PlaylistRoleEntry(persistentID: "four", name: "Subscription", role: .keepers),
      PlaylistRoleEntry(persistentID: "five", name: "Not a keeper", role: .curated),
    ])
    let options = PlaylistKeepOptions.make(roles: roles, editablePlaylists: [
      ("other", "Undeniable"), ("selections", "2023: Jon's Selections"),
      ("alt", "Alternative JP"),
      ("keepers", "Vinyl Fever Keepers"), ("noneditable", "Not a keeper"),
    ], year: 2023)
    #expect(options.playlists.map(\.name) == ["Vinyl Fever Keepers", "2023: Jon's Selections", "Alternative JP"])
    #expect(options.playlists.map(\.isChecked) == [true, true, false])
    #expect(!options.rolesReadFallback)
  }

  @Test func oldOrMissingYearDoesNotPrecheckSelectionsAndRolesFailureFallsBack() {
    let editable = [("vfk", "Vinyl Fever Keepers"), ("2023", "2023: Jon's Selections"),
      ("2019", "2019: Jon's Selections"), ("other", "Replay 2025")]
    let old = PlaylistKeepOptions.make(roles: nil, editablePlaylists: editable, year: 2019)
    #expect(old.playlists.map(\.name) == ["Vinyl Fever Keepers", "2019: Jon's Selections", "2023: Jon's Selections"])
    #expect(old.playlists.map(\.isChecked) == [true, false, false])
    #expect(old.rolesReadFallback)
    let missing = PlaylistKeepOptions.make(roles: nil, editablePlaylists: editable, year: nil)
    #expect(missing.playlists.filter { $0.name.contains("Selections") }.allSatisfy { !$0.isChecked })
  }

  @Test func releaseYearKeepsTheMusicCatalogCalendarDateAcrossTimeZones() {
    let formatter = ISO8601DateFormatter()
    let releaseDate = formatter.date(from: "2023-01-01T00:00:00Z")!
    #expect(PlaylistKeepOptions.releaseYear(from: releaseDate) == 2023)
  }
}
