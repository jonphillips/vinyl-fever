import Dependencies
import Foundation
import MusicKit
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistKeepModelTests {
  @Test @MainActor
  func savesCatalogAndLibraryReferencesToCheckedPlaylists() async throws {
    for (id, expected) in [("catalog-id", PlaylistSongSource.catalog), ("i.library-id", .libraryUpload)] {
      let appended = AppendRecorder()
      let model = withDependencies({ dependencies in
        dependencies.keepLibraryClient.isAuthorized = { true }
        dependencies.keepLibraryClient.readRoles = { try roles() }
        dependencies.keepLibraryClient.editablePlaylists = { [
          KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers"),
          KeepLibraryPlaylist(id: "selections", name: "2023: Jon's Selections"),
        ] }
        dependencies.keepLibraryClient.tracks = { _ in [] }
        dependencies.keepLibraryClient.append = { playlistID, reference in await appended.add(playlistID, reference) }
      }) { PlaylistKeepModel() }
      await model.keepButtonTapped(for: shelfSong(year: 2023), resolvedSong: try song(id: id))
      await model.save()
      let saved = await appended.values
      #expect(saved.map(\.0) == ["keepers", "selections"])
      #expect(saved.map { $0.1.source } == [expected, expected])
      #expect(saved.map { $0.1.id } == [id, id])
      #expect(model.destination == nil)
    }
  }

  @Test @MainActor
  func alreadyThereIsCheckedDisabledAndSkipped() async throws {
    let appendCount = AppendRecorder()
    let model = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.editablePlaylists = { [KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers")] }
      dependencies.keepLibraryClient.tracks = { _ in [KeepLibraryTrack(title: "Cafe", artist: "Band")] }
      dependencies.keepLibraryClient.append = { _, _ in await appendCount.add("", PlaylistSongReference(id: "", source: .catalog)) }
    }) { PlaylistKeepModel() }
    await model.keepButtonTapped(for: shelfSong(title: "Café", artist: "Bánd"), resolvedSong: try song(id: "catalog"))

    #expect(model.playlists.first?.isAlreadyThere == true)
    #expect(model.playlists.first?.isChecked == true)
    #expect(model.playlists.first?.isDisabled == true)
    await model.save()
    #expect(await appendCount.values.isEmpty)
  }

  @Test @MainActor
  func usesResolvedReleaseYearWhenLedgerHasNoYear() async throws {
    let model = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.editablePlaylists = { [
        KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers"),
        KeepLibraryPlaylist(id: "selections", name: "2023: Jon's Selections"),
      ] }
      dependencies.keepLibraryClient.tracks = { _ in [] }
    }) { PlaylistKeepModel() }
    await model.keepButtonTapped(for: shelfSong(year: nil), resolvedSong: try song(id: "catalog"))

    #expect(model.currentRequest?.year == 2023)
    #expect(model.playlists.map(\.isChecked) == [true, true])
  }

  @Test @MainActor
  func failedLoadForNextSongClearsPreviousChoicesAndCannotPostThem() async throws {
    let appended = AppendRecorder()
    let trackReads = TrackReadRecorder()
    let model = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try rolesIncludingYears() }
      dependencies.keepLibraryClient.editablePlaylists = { [
        KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers"),
        KeepLibraryPlaylist(id: "2023", name: "2023: Jon's Selections"),
        KeepLibraryPlaylist(id: "2024", name: "2024: Jon's Selections"),
      ] }
      dependencies.keepLibraryClient.tracks = { id in try await trackReads.read(id) }
      dependencies.keepLibraryClient.append = { id, reference in await appended.add(id, reference) }
    }) { PlaylistKeepModel() }

    await model.keepButtonTapped(for: shelfSong(year: 2023), resolvedSong: try song(id: "catalog-a"))
    #expect(model.errorMessage == nil)
    #expect(model.playlists.map(\.name) == ["Vinyl Fever Keepers", "2023: Jon's Selections", "2024: Jon's Selections"])
    #expect(model.playlists.map(\.isChecked) == [true, true, false])
    await model.save()
    let writesAfterSongA = await appended.values.count
    #expect(writesAfterSongA == 2)

    await model.keepButtonTapped(for: shelfSong(title: "Second", year: 2024), resolvedSong: try song(id: "catalog-b"))
    #expect(model.playlists.isEmpty)
    #expect(model.errorMessage?.contains("Unavailable") == true)
    await model.save()
    #expect(await appended.values.count == writesAfterSongA)
  }

  @Test @MainActor
  func failedRolesReadIsRetriedOnTheNextOpen() async throws {
    let sequence = RolesReadSequence(roles: PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "keepers", name: "Vinyl Fever Keepers", role: .keepers),
      PlaylistRoleEntry(persistentID: "alternative", name: "Alternative JP", role: .keepers),
    ]))
    let model = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try await sequence.read() }
      dependencies.keepLibraryClient.editablePlaylists = { [
        KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers"),
        KeepLibraryPlaylist(id: "alternative", name: "Alternative JP"),
      ] }
      dependencies.keepLibraryClient.tracks = { _ in [] }
    }) { PlaylistKeepModel() }

    await model.prepare(keepRequest(songID: "first", year: nil))
    #expect(model.rolesReadFallback)
    #expect(model.playlists.map(\.name) == ["Vinyl Fever Keepers"])

    await model.prepare(keepRequest(songID: "second", year: nil))
    #expect(!model.rolesReadFallback)
    #expect(model.playlists.map(\.name) == ["Vinyl Fever Keepers", "Alternative JP"])
  }

  @Test @MainActor
  func partialAppendFailureKeepsOtherResultAndReportsPlaylistAndReason() async throws {
    let appended = AppendRecorder()
    let model = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.editablePlaylists = { [
        KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers"),
        KeepLibraryPlaylist(id: "selections", name: "2023: Jon's Selections"),
      ] }
      dependencies.keepLibraryClient.tracks = { _ in [] }
      dependencies.keepLibraryClient.append = { id, _ in
        await appended.add(id, PlaylistSongReference(id: "", source: .catalog))
        if id == "selections" { throw NSError(domain: "Music", code: 403, userInfo: [NSLocalizedDescriptionKey: "Not allowed"]) }
      }
    }) { PlaylistKeepModel() }
    await model.keepButtonTapped(for: shelfSong(year: 2023), resolvedSong: try song(id: "catalog"))
    await model.save()

    #expect(await appended.values.map(\.0) == ["keepers", "selections"])
    #expect(model.savedPlaylistNames == ["Vinyl Fever Keepers"])
    #expect(model.errorMessage?.contains("2023: Jon's Selections") == true)
    #expect(model.errorMessage?.contains("Not allowed") == true)
  }

  @Test @MainActor
  func cancelAndUnauthorizedDoNotAppend() async throws {
    let appendCount = AppendRecorder()
    let authorized = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.readRoles = { try roles() }
      dependencies.keepLibraryClient.editablePlaylists = { [KeepLibraryPlaylist(id: "keepers", name: "Vinyl Fever Keepers")] }
      dependencies.keepLibraryClient.tracks = { _ in [] }
      dependencies.keepLibraryClient.append = { _, _ in await appendCount.add("", PlaylistSongReference(id: "", source: .catalog)) }
    }) { PlaylistKeepModel() }
    await authorized.keepButtonTapped(for: shelfSong(), resolvedSong: try song(id: "catalog"))
    authorized.cancel()
    #expect(await appendCount.values.isEmpty)

    let unauthorized = withDependencies({ dependencies in
      dependencies.keepLibraryClient.isAuthorized = { false }
      dependencies.keepLibraryClient.editablePlaylists = { throw NSError(domain: "should-not-run", code: 1) }
      dependencies.keepLibraryClient.append = { _, _ in await appendCount.add("", PlaylistSongReference(id: "", source: .catalog)) }
    }) { PlaylistKeepModel() }
    await unauthorized.keepButtonTapped(for: shelfSong(), resolvedSong: try song(id: "catalog"))
    #expect(unauthorized.destination == nil)
    #expect(await appendCount.values.isEmpty)
  }

  private func roles() throws -> PlaylistRoles {
    PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "keepers", name: "Vinyl Fever Keepers", role: .keepers),
      PlaylistRoleEntry(persistentID: "selections", name: "2023: Jon's Selections", role: .keepers),
    ])
  }

  private func rolesIncludingYears() throws -> PlaylistRoles {
    PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "keepers", name: "Vinyl Fever Keepers", role: .keepers),
      PlaylistRoleEntry(persistentID: "2023", name: "2023: Jon's Selections", role: .keepers),
      PlaylistRoleEntry(persistentID: "2024", name: "2024: Jon's Selections", role: .keepers),
    ])
  }

  private func keepRequest(songID: String, year: Int?) -> PlaylistKeepRequest {
    PlaylistKeepRequest(songID: songID, title: songID, artist: "Artist",
      reference: PlaylistSongReference(id: songID, source: .catalog), year: year)
  }

  private func song(id: String) throws -> Song {
    let type = id.hasPrefix("i.") ? "library-songs" : "songs"
    let data = try JSONSerialization.data(withJSONObject: ["id": id, "type": type,
      "attributes": ["name": "Song", "artistName": "Artist", "releaseDate": "2023-01-01"]])
    return try JSONDecoder().decode(Song.self, from: data)
  }

  private func shelfSong(title: String = "Song", artist: String = "Artist", year: Int? = 2023) -> PlaylistShelfSong {
    PlaylistShelfSong(id: "song", title: title, artist: artist, album: nil, year: year,
      familiarity: "New to you", why: nil, like: [])
  }
}

private actor AppendRecorder {
  private(set) var values: [(String, PlaylistSongReference)] = []
  func add(_ id: String, _ reference: PlaylistSongReference) { values.append((id, reference)) }
}

private actor RolesReadSequence {
  private(set) var didFailOnce = false
  let roles: PlaylistRoles

  init(roles: PlaylistRoles) { self.roles = roles }

  func read() throws -> PlaylistRoles {
    guard didFailOnce else {
      didFailOnce = true
      throw NSError(domain: "Roles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Temporarily unavailable"])
    }
    return roles
  }
}

private actor TrackReadRecorder {
  private var keeperReads = 0

  func read(_ playlistID: String) throws -> [KeepLibraryTrack] {
    if playlistID == "keepers" {
      keeperReads += 1
      if keeperReads >= 2 {
        throw NSError(domain: "Music", code: 503, userInfo: [NSLocalizedDescriptionKey: "Unavailable"])
      }
    }
    return []
  }
}
