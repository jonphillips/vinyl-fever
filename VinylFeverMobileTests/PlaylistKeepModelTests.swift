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
