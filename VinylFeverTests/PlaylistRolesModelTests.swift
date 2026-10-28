import Dependencies
import Foundation
import Testing
import VinylFeverCore

@testable import VinylFever

@MainActor
@Suite("Playlist roles editor")
struct PlaylistRolesModelTests {
  @Test("the banner's Label action opens roles filtered to unlabeled playlists")
  func labelStartsFiltered() {
    #expect(PlaylistRolesModel(initialFilter: "unlabeled").filter == "unlabeled")
  }

  @Test("a queued Settings request is consumed once when Settings first appears")
  func takesQueuedPlaylistRolesRequest() {
    let model = withDependencies { _ in } operation: { AppModel() }
    model.requestPlaylistRoles()
    #expect(model.takePlaylistRolesRequest())
    #expect(!model.takePlaylistRolesRequest())
  }

  @Test("suggestions only fill unlabeled playlists and Save writes the selected roles")
  func suggestionsAndSave() async {
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "selection", name: "2025: Jon's Selections", kind: .user, members: []),
      LibraryPlaylist(persistentID: "new", name: "New Music Daily", kind: .subscription, members: []),
      LibraryPlaylist(persistentID: "vf", name: "From Vinyl Fever", kind: .user, members: []),
    ])
    let memory = RolesStoreMemory()
    let model = withDependencies {
      $0.librarySnapshotStore.read = { snapshot }
      $0.playlistRolesStore.read = { nil }
      $0.playlistRolesStore.write = { await memory.write($0) }
      $0.playlistRolesStore.fileURL = { URL(fileURLWithPath: "/test/playlist-roles.json") }
      $0.playlistInboxClient.processedNames = { ["From Vinyl Fever"] }
    } operation: {
      PlaylistRolesModel()
    }
    await model.load()
    model.selections["new"] = .curated
    model.useSuggestions()
    #expect(model.selections["selection"] == .keepers)
    #expect(model.selections["new"] == .curated)
    #expect(model.selections["vf"] == .vinylFever)
    await model.save()
    let saved = await memory.value
    #expect(saved?.playlists.count == 3)
    #expect(saved?.playlists.first(where: { $0.persistentID == "selection" })?.role == .keepers)
    #expect(saved?.playlists.first(where: { $0.persistentID == "new" })?.role == .curated)
    #expect(saved?.playlists.first(where: { $0.persistentID == "vf" })?.role == .vinylFever)
  }

  @Test("unmatched roles remain visible and survive saving")
  func preservesMissingRole() async {
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "one", name: "Same", kind: .user, members: []),
      LibraryPlaylist(persistentID: "two", name: "Same", kind: .user, members: []),
    ])
    let existing = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "old", name: "Same", role: .curated),
    ])
    let memory = RolesStoreMemory()
    let model = withDependencies {
      $0.librarySnapshotStore.read = { snapshot }
      $0.playlistRolesStore.read = { existing }
      $0.playlistRolesStore.write = { await memory.write($0) }
      $0.playlistRolesStore.fileURL = { URL(fileURLWithPath: "/test/playlist-roles.json") }
    } operation: { PlaylistRolesModel() }
    await model.load()
    #expect(model.missingEntries.map(\.persistentID) == ["old"])
    await model.save()
    #expect(await memory.value?.playlists.map(\.persistentID) == ["old"])
  }
}

private actor RolesStoreMemory {
  private(set) var value: PlaylistRoles?
  func write(_ roles: PlaylistRoles) { value = roles }
}
