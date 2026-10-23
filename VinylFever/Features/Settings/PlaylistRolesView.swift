import Dependencies
import Observation
import SwiftUI
import VinylFeverCore

@MainActor
@Observable
final class PlaylistRolesModel {
  var snapshot: LibrarySnapshot?
  var savedRoles: PlaylistRoles?
  var selections: [String: PlaylistRole] = [:]
  var errorMessage: String?
  var isSaving = false
  @ObservationIgnored @Dependency(\.librarySnapshotStore) private var snapshotStore
  @ObservationIgnored @Dependency(\.playlistRolesStore) private var rolesStore
  @ObservationIgnored @Dependency(\.playlistInboxClient) private var playlistInboxClient

  var missingEntries: [PlaylistRoleEntry] {
    guard let snapshot, let savedRoles else { return [] }
    return PlaylistRoleMatcher.missing(snapshot: snapshot, roles: savedRoles)
  }
  var rows: [LibraryPlaylist] { snapshot?.playlists ?? [] }

  func load() async {
    do {
      snapshot = try await snapshotStore.read()
      savedRoles = try await rolesStore.read()
      guard let snapshot else { return }
      let resolved = savedRoles.map { PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: $0) } ?? []
      selections = Dictionary(uniqueKeysWithValues: resolved.compactMap { item in
        item.role.map { (item.playlist.persistentID, $0) }
      })
    } catch { errorMessage = error.localizedDescription }
  }

  func useSuggestions() {
    let createdNames = (try? playlistInboxClient.processedNames()) ?? []
    for playlist in rows where selections[playlist.persistentID] == nil {
      if let role = PlaylistRoleSuggestion.suggest(name: playlist.name, kind: playlist.kind,
        folder: playlist.folder, createdNames: createdNames) {
        selections[playlist.persistentID] = role
      }
    }
  }

  func removeMissing(_ entry: PlaylistRoleEntry) {
    guard let savedRoles else { return }
    self.savedRoles = PlaylistRoles(updatedAt: savedRoles.updatedAt, playlists: savedRoles.playlists.filter { $0.persistentID != entry.persistentID })
  }

  func save() async {
    guard let snapshot else { return }
    isSaving = true
    defer { isSaving = false }
    let unresolvedExisting = savedRoles.map { PlaylistRoleMatcher.missing(snapshot: snapshot, roles: $0) } ?? []
    let current = snapshot.playlists.compactMap { playlist in
      selections[playlist.persistentID].map { PlaylistRoleEntry(persistentID: playlist.persistentID, name: playlist.name, role: $0) }
    }
    let roles = PlaylistRoles(updatedAt: .now, playlists: current + unresolvedExisting)
    do { try await rolesStore.write(roles); savedRoles = roles; errorMessage = nil }
    catch { errorMessage = error.localizedDescription }
  }
}

struct PlaylistRolesView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model = PlaylistRolesModel()
  @State private var filter = "all"

  private var visibleRows: [LibraryPlaylist] {
    switch filter {
    case "unlabeled": model.rows.filter { model.selections[$0.persistentID] == nil }
    case "missing": []
    case let role where role.hasPrefix("role:"):
      model.rows.filter { model.selections[$0.persistentID]?.rawValue == String(role.dropFirst(5)) }
    default: model.rows
    }
  }
  private var visibleMissing: [PlaylistRoleEntry] {
    guard filter == "all" || filter == "missing" else { return [] }
    return model.missingEntries
  }

  var body: some View {
    NavigationStack {
      List {
        if let error = model.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        Section {
          Picker("Filter", selection: $filter) {
            Text("All").tag("all")
            Text("Unlabeled").tag("unlabeled")
            Text("Missing").tag("missing")
            ForEach(PlaylistRole.allCases, id: \.self) { role in Text(role.rawValue).tag("role:\(role.rawValue)") }
          }
        }
        if filter != "missing" {
          Section("Playlists") {
          ForEach(visibleRows) { playlist in
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                Text("\(playlist.folder.map { $0 + " · " } ?? "")\(playlist.kind.rawValue) · \(playlist.members.count) songs")
                  .font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Picker("Role", selection: Binding(
                get: { model.selections[playlist.persistentID] },
                set: { model.selections[playlist.persistentID] = $0 }
              )) {
                Text("Unlabeled").tag(PlaylistRole?.none)
                ForEach(PlaylistRole.allCases.filter { $0 != .replay || !PlaylistRoleSuggestion.isPreCutoffReplay(playlist.name) }, id: \.self) { role in
                  Text(role.rawValue).tag(Optional(role))
                }
              }.labelsHidden().frame(width: 190)
            }
          }
        }
        }
        if !visibleMissing.isEmpty {
          Section("Missing from this library") {
            ForEach(visibleMissing, id: \.persistentID) { entry in
              HStack {
                VStack(alignment: .leading) { Text(entry.name); Text(entry.role.rawValue).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Remove", role: .destructive) { model.removeMissing(entry) }
              }
            }
          }
        }
      }
      .navigationTitle("Playlist Roles")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .primaryAction) { Button("Save") { Task { await model.save(); if model.errorMessage == nil { dismiss() } } }.disabled(model.isSaving) }
        ToolbarItem(placement: .automatic) { Button("Use Suggestions") { model.useSuggestions() } }
      }
      .task { await model.load() }
    }
    .frame(minWidth: 760, minHeight: 520)
  }
}
