import Dependencies
import DependenciesMacros
import Foundation
import Observation
import VinylFeverCore
import VinylFeverListening

@DependencyClient
struct PlaylistRoleDismissalClient: Sendable {
  var read: @Sendable () -> Set<String> = { [] }
  var write: @Sendable (Set<String>) -> Void = { _ in }
}

extension PlaylistRoleDismissalClient: TestDependencyKey {
  static let testValue = Self(read: { [] }, write: { _ in })
}

extension PlaylistRoleDismissalClient: DependencyKey {
  static let liveValue = Self(
    read: { Set(UserDefaults.standard.stringArray(forKey: "playlist-role-banner-dismissed") ?? []) },
    write: { UserDefaults.standard.set(Array($0), forKey: "playlist-role-banner-dismissed") }
  )
}

extension DependencyValues {
  var playlistRoleDismissalClient: PlaylistRoleDismissalClient {
    get { self[PlaylistRoleDismissalClient.self] }
    set { self[PlaylistRoleDismissalClient.self] = newValue }
  }
}

enum PlaylistRoleBannerState: Equatable {
  case hidden
  case unlabeled(names: [String], remaining: Int)

  static func make(snapshot: LibrarySnapshot?, roles: PlaylistRoles?, dismissed: Set<String>) -> Self {
    guard let snapshot else { return .hidden }
    let effectiveRoles = roles ?? PlaylistRoles(updatedAt: .distantPast, playlists: [])
    let unlabeled = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: effectiveRoles)
      .filter { $0.role == nil }
      .map(\.playlist)
    let visible = unlabeled.filter { !dismissed.contains($0.persistentID) }
    guard !visible.isEmpty else { return .hidden }
    let ordered = visible + unlabeled.filter { dismissed.contains($0.persistentID) }
    let names = ordered.prefix(3).map(\.name)
    return .unlabeled(names: names, remaining: max(0, unlabeled.count - names.count))
  }
}

@MainActor
@Observable
final class PlaylistRoleBannerModel {
  @ObservationIgnored @Dependency(\.playlistRolesStore) private var rolesStore
  @ObservationIgnored @Dependency(\.playlistInboxClient) private var inbox
  @ObservationIgnored @Dependency(\.listeningStore) private var listeningStore
  @ObservationIgnored @Dependency(\.playlistRoleDismissalClient) private var dismissalStore
  @ObservationIgnored @Dependency(\.date.now) private var now

  private(set) var snapshot: LibrarySnapshot?
  private(set) var roles: PlaylistRoles?
  private(set) var state: PlaylistRoleBannerState = .hidden
  private(set) var announcement: String?
  private(set) var errorMessage: String?
  private var dismissed: Set<String> { dismissalStore.read() }

  func snapshotLoaded(_ snapshot: LibrarySnapshot?) async {
    guard let snapshot else { return }
    guard self.snapshot?.generatedAt != snapshot.generatedAt else { return }
    self.snapshot = snapshot
    announcement = nil
    do {
      let saved = try await rolesStore.read() ?? PlaylistRoles(updatedAt: .distantPast, playlists: [])
      let adoption = PlaylistRoleAdoption.adopt(snapshot: snapshot, roles: saved, updatedAt: now)
      var createdNames = (try? inbox.processedNames()) ?? []
      createdNames.formUnion(try recommendationPlaylistNames())
      let result = PlaylistRoleAutoLabeling.applyVinylFeverRole(
        snapshot: snapshot, roles: adoption.roles, createdNames: createdNames, updatedAt: now
      )
      if adoption.didWrite || !result.labeled.isEmpty {
        try await rolesStore.write(result.roles)
        roles = result.roles
      } else {
        roles = saved
      }
      if !result.labeled.isEmpty {
        let names = result.labeled.prefix(3).map(\.name)
        let remainder = result.labeled.count - names.count
        announcement = "Labeled \(result.labeled.count) Vinyl Fever playlist\(result.labeled.count == 1 ? "" : "s") `vinyl-fever`: "
          + names.joined(separator: ", ") + (remainder > 0 ? " and \(remainder) more" : "")
      }
      state = PlaylistRoleBannerState.make(snapshot: snapshot, roles: roles, dismissed: dismissed)
      errorMessage = nil
    } catch {
      roles = nil
      state = .hidden
      announcement = nil
      errorMessage = error.localizedDescription
    }
  }

  func dismiss() {
    guard let snapshot else { return }
    let effectiveRoles = roles ?? PlaylistRoles(updatedAt: .distantPast, playlists: [])
    let unlabeledIDs = Set(PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: effectiveRoles)
      .filter { $0.role == nil }.map { $0.playlist.persistentID })
    dismissalStore.write(dismissed.union(unlabeledIDs))
    state = PlaylistRoleBannerState.make(snapshot: snapshot, roles: roles, dismissed: dismissed.union(unlabeledIDs))
  }

  private func recommendationPlaylistNames() throws -> Set<String> {
    let root = listeningStore.listeningFolder().deletingLastPathComponent()
      .appending(path: "Taste Intelligence/recommendations", directoryHint: .isDirectory)
    return try RecommendationLedgerCodec.playlistNames(inFolder: root)
  }
}
