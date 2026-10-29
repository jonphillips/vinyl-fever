import Dependencies
import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

@testable import VinylFever

@MainActor
@Suite("Playlist role banner")
struct PlaylistRoleBannerModelTests {
  @Test("banner shows none, some, three names, and the remaining count")
  func bannerStates() {
    let empty = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [])
    #expect(PlaylistRoleBannerState.make(snapshot: empty, roles: nil, dismissed: []) == .hidden)

    let one = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "single", name: "Single", kind: .subscription, members: []),
    ])
    #expect(PlaylistRoleBannerState.make(snapshot: one, roles: nil, dismissed: []) ==
      .unlabeled(names: ["Single"], remaining: 0))

    let playlists = (1...5).map { index in
      LibraryPlaylist(persistentID: "p\(index)", name: "Playlist \(index)", kind: .user, members: [])
    }
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: playlists)
    let roles = PlaylistRoles(updatedAt: .now, playlists: [
      PlaylistRoleEntry(persistentID: "p1", name: "Playlist 1", role: .keepers),
    ])
    #expect(PlaylistRoleBannerState.make(snapshot: snapshot, roles: roles, dismissed: []) ==
      .unlabeled(names: ["Playlist 2", "Playlist 3", "Playlist 4"], remaining: 1))
    #expect(PlaylistRoleBannerState.make(snapshot: snapshot, roles: nil, dismissed: []) ==
      .unlabeled(names: ["Playlist 1", "Playlist 2", "Playlist 3"], remaining: 2))
  }

  @Test("dismissal hides current playlists and a newly unlabeled playlist reopens the banner")
  func dismissalAndNewPlaylist() {
    let playlists = ["a", "b", "c", "d"].map { id in
      LibraryPlaylist(persistentID: id, name: id, kind: .user, members: [])
    } + [LibraryPlaylist(persistentID: "e", name: "e", kind: .subscription, members: [])]
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: playlists)
    #expect(PlaylistRoleBannerState.make(snapshot: snapshot, roles: nil, dismissed: ["a", "b", "c", "d"]) ==
      .unlabeled(names: ["e", "a", "b"], remaining: 2))
    #expect(PlaylistRoleBannerState.make(snapshot: snapshot, roles: nil, dismissed: Set(playlists.map(\.persistentID))) == .hidden)
  }

  @Test("announcement remains visible with another unlabeled playlist")
  func reconciliationUsesDependencies() async {
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "vf", name: "Vinyl Fever batch", kind: .user, members: []),
      LibraryPlaylist(persistentID: "ordinary", name: "Ordinary", kind: .smart, members: []),
    ])
    let store = BannerRolesMemory()
    let model = withDependencies {
      $0.playlistRolesStore.read = { await store.read() }
      $0.playlistRolesStore.write = { await store.write($0) }
      $0.playlistInboxClient.processedNames = { ["Vinyl Fever batch"] }
      $0.listeningStore.listeningFolder = { URL(fileURLWithPath: "/tmp/vf-banner-test/Listening") }
      $0.date.now = Date(timeIntervalSince1970: 0)
    } operation: {
      PlaylistRoleBannerModel()
    }
    await model.snapshotLoaded(snapshot)
    #expect(await store.value?.playlists.first?.role == .vinylFever)
    #expect(model.announcement == "Labeled 1 Vinyl Fever playlist `vinyl-fever`: Vinyl Fever batch")
    #expect(model.state == .unlabeled(names: ["Ordinary"], remaining: 0))
    let refreshed = LibrarySnapshot(generatedAt: Date(timeIntervalSince1970: 1), tracks: [], playlists: snapshot.playlists)
    await model.snapshotLoaded(refreshed)
    #expect(await store.writeCount == 1)
  }

  @Test("snapshot adopts pending role silently and writes only once")
  func adoptionIsSilent() async {
    let createdAt = Date(timeIntervalSince1970: 100)
    let store = BannerRolesMemory(value: PlaylistRoles(updatedAt: createdAt, playlists: [
      PlaylistRoleEntry(persistentID: "catalog-id", name: "Staged batch", role: .vinylFever, pendingSince: createdAt),
    ]))
    let model = withDependencies {
      $0.playlistRolesStore.read = { await store.read() }
      $0.playlistRolesStore.write = { await store.write($0) }
      $0.playlistInboxClient.processedNames = { [] }
      $0.listeningStore.listeningFolder = { URL(fileURLWithPath: "/tmp/vf-banner-test/Listening") }
      $0.date.now = Date(timeIntervalSince1970: 200)
    } operation: {
      PlaylistRoleBannerModel()
    }
    let snapshot = LibrarySnapshot(generatedAt: createdAt, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "music-id", name: "Staged batch", kind: .user, members: []),
      LibraryPlaylist(persistentID: "ordinary", name: "Ordinary", kind: .user, members: []),
    ])
    await model.snapshotLoaded(snapshot)
    #expect(await store.value?.playlists == [PlaylistRoleEntry(
      persistentID: "music-id", name: "Staged batch", role: .vinylFever)])
    #expect(await store.writeCount == 1)
    #expect(model.announcement == nil)
    #expect(model.state == .unlabeled(names: ["Ordinary"], remaining: 0))
  }

  @Test("a reused name adopts the newly synced playlist without an S5 announcement")
  func reusedNameAdoptsUnheldPlaylist() async {
    let createdAt = Date(timeIntervalSince1970: 100)
    let oldRole = PlaylistRoleEntry(persistentID: "old", name: "Selections", role: .keepers)
    let pending = PlaylistRoleEntry(
      persistentID: "catalog", name: "Selections", role: .vinylFever, pendingSince: createdAt)
    let store = BannerRolesMemory(value: PlaylistRoles(updatedAt: createdAt, playlists: [oldRole, pending]))
    let model = withDependencies {
      $0.playlistRolesStore.read = { await store.read() }
      $0.playlistRolesStore.write = { await store.write($0) }
      $0.playlistInboxClient.processedNames = { ["Selections"] }
      $0.listeningStore.listeningFolder = { URL(fileURLWithPath: "/tmp/vf-banner-test/Listening") }
      $0.date.now = Date(timeIntervalSince1970: 200)
    } operation: {
      PlaylistRoleBannerModel()
    }
    let snapshot = LibrarySnapshot(generatedAt: createdAt, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "old", name: "Selections", kind: .user, members: []),
      LibraryPlaylist(persistentID: "new", name: "Selections", kind: .user, members: []),
    ])
    await model.snapshotLoaded(snapshot)
    #expect(await store.value?.playlists == [
      oldRole, PlaylistRoleEntry(persistentID: "new", name: "Selections", role: .vinylFever),
    ])
    #expect(await store.writeCount == 1)
    #expect(model.announcement == nil)
    #expect(PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: await store.value!).map(\.role) == [.keepers, .vinylFever])
  }

  @Test("ledger-only playlist name auto-labels when the inbox archive is empty")
  func labelsFromLedger() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "vf-ledger-role-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let ledgerFolder = root.appending(path: "Taste Intelligence/recommendations", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: ledgerFolder, withIntermediateDirectories: true)
    let batch = RecommendationBatch(recordedAt: .now, host: "other Mac", playlist: "Ledger only batch", tracks: [])
    try RecommendationLedgerCodec.encode(batch).write(to: ledgerFolder.appending(path: "other-Mac.jsonl"))

    let store = BannerRolesMemory()
    let model = withDependencies {
      $0.playlistRolesStore.read = { await store.read() }
      $0.playlistRolesStore.write = { await store.write($0) }
      $0.playlistInboxClient.processedNames = { [] }
      $0.listeningStore.listeningFolder = { root.appending(path: "Listening", directoryHint: .isDirectory) }
      $0.date.now = Date(timeIntervalSince1970: 0)
    } operation: {
      PlaylistRoleBannerModel()
    }
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "ledger", name: "Ledger only batch", kind: .subscription, members: []),
    ])
    await model.snapshotLoaded(snapshot)
    #expect(await store.value?.playlists.first?.role == .vinylFever)
  }

  @Test("roles read failure hides the banner and does not write")
  func rolesReadFailure() async {
    let store = BannerRolesMemory()
    let model = withDependencies {
      $0.playlistRolesStore.read = { throw BannerTestFailure.expected }
      $0.playlistRolesStore.write = { await store.write($0) }
      $0.listeningStore.listeningFolder = { URL(fileURLWithPath: "/tmp/vf-banner-test/Listening") }
    } operation: {
      PlaylistRoleBannerModel()
    }
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "ordinary", name: "Ordinary", kind: .user, members: []),
    ])
    await model.snapshotLoaded(snapshot)
    #expect(model.state == .hidden)
    #expect(model.errorMessage != nil)
    #expect(await store.writeCount == 0)
  }

  @Test("roles write failure hides the banner")
  func rolesWriteFailure() async {
    let model = withDependencies {
      $0.playlistRolesStore.read = { nil }
      $0.playlistRolesStore.write = { _ in throw BannerTestFailure.expected }
      $0.playlistInboxClient.processedNames = { ["Vinyl Fever batch"] }
      $0.listeningStore.listeningFolder = { URL(fileURLWithPath: "/tmp/vf-banner-test/Listening") }
      $0.date.now = Date(timeIntervalSince1970: 0)
    } operation: {
      PlaylistRoleBannerModel()
    }
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "vf", name: "Vinyl Fever batch", kind: .user, members: []),
    ])
    await model.snapshotLoaded(snapshot)
    #expect(model.state == .hidden)
    #expect(model.errorMessage != nil)
  }
}

private enum BannerTestFailure: Error { case expected }

private actor BannerRolesMemory {
  private(set) var value: PlaylistRoles?
  private(set) var writeCount = 0
  init(value: PlaylistRoles? = nil) { self.value = value }
  func read() -> PlaylistRoles? { value }
  func write(_ roles: PlaylistRoles) { value = roles; writeCount += 1 }
}
