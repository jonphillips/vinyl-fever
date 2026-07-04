import AppKit
import SQLiteData
import SwiftUI
import VinylFeverCore

struct CollectionsView: View {
  @Bindable var model: AppModel
  @FetchAll(CompilationAlbum.order(by: \.name))
  private var albums: [CompilationAlbum]
  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]
  @State private var selectedAlbumID: CompilationAlbum.ID?

  var body: some View {
    let selectedAlbum = albums.first { $0.id == selectedAlbumID }
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CollectionHeader(
          seedFolder: openSeedFolder,
          appendFolder: {
            if let selectedAlbum {
              openAppendFolder(album: selectedAlbum)
            }
          },
          canAppend: selectedAlbum != nil
        )
        CollectionRegistrySection(
          albums: albums,
          selectedAlbumID: $selectedAlbumID
        )
        CollectionSeedSection(
          candidates: model.compilationSeedCandidates,
          selectedIDs: $model.selectedCompilationSeedCandidateIDs,
          state: model.compilationSeedState,
          save: model.persistSelectedCompilationSeedCandidates
        )
        if let selectedAlbum {
          CompilationAppendSection(
            album: selectedAlbum,
            folder: model.compilationAppendFolder,
            plan: model.compilationApplyPlan,
            applyState: model.compilationApplyState,
            apply: { plan in
              Task {
                await model.applyCompilationPlan(plan)
              }
            }
          )
        }
      }
      .frame(maxWidth: 1040, alignment: .leading)
      .padding(24)
    }
    .navigationTitle("Collections")
    .toolbar {
      ToolbarItem {
        Button(action: openSeedFolder) {
          Label("Seed", systemImage: "rectangle.stack.badge.plus")
        }
      }
      ToolbarItem {
        Button {
          if let selectedAlbum {
            openAppendFolder(album: selectedAlbum)
          }
        } label: {
          Label("Append", systemImage: "plus")
        }
        .disabled(selectedAlbum == nil)
      }
    }
    .task(id: AppSetting.current(from: persistedSettings)) {
      await model.refreshToolStatuses(settings: AppSetting.current(from: persistedSettings))
    }
  }

  private func openSeedFolder() {
    guard let url = openFolder(prompt: "Seed") else {
      return
    }
    Task {
      await model.seedCompilationAlbums(from: url)
    }
  }

  private func openAppendFolder(album: CompilationAlbum) {
    guard let url = openFolder(prompt: "Append") else {
      return
    }
    Task {
      await model.buildCompilationAppendPlan(entry: album, sourceFolder: url)
    }
  }

  private func openFolder(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = false
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
  }
}

private struct CollectionHeader: View {
  let seedFolder: () -> Void
  let appendFolder: () -> Void
  let canAppend: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Compilation Albums")
          .font(.title2)
          .fontWeight(.semibold)
        Text("Registry entries are seeded from folders and appends write stamped copies to Working.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: seedFolder) {
        Label("Seed Registry", systemImage: "rectangle.stack.badge.plus")
      }
      Button(action: appendFolder) {
        Label("Append Folder", systemImage: "plus")
      }
      .disabled(!canAppend)
    }
  }
}

private struct CollectionRegistrySection: View {
  let albums: [CompilationAlbum]
  @Binding var selectedAlbumID: CompilationAlbum.ID?

  var body: some View {
    CollectionSection(title: "Registry", systemImage: "rectangle.stack", count: albums.count) {
      if albums.isEmpty {
        EmptyCollectionRow(title: "No compilation albums registered")
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(albums) { album in
            Button {
              selectedAlbumID = album.id
            } label: {
              CompilationAlbumRow(
                album: album,
                isSelected: selectedAlbumID == album.id
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

private struct CollectionSeedSection: View {
  let candidates: [CompilationAlbumSeedCandidate]
  @Binding var selectedIDs: Set<CompilationAlbumSeedCandidate.ID>
  let state: CollectionSeedState
  let save: () -> Void

  var body: some View {
    CollectionSection(title: "Folder Seeding", systemImage: "folder.badge.plus", count: candidates.count) {
      VStack(alignment: .leading, spacing: 12) {
        CollectionSeedStatus(state: state)
        if !candidates.isEmpty {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(candidates) { candidate in
              CollectionSeedCandidateRow(
                candidate: candidate,
                isSelected: selectedIDs.contains(candidate.id),
                toggle: {
                  if selectedIDs.contains(candidate.id) {
                    selectedIDs.remove(candidate.id)
                  } else {
                    selectedIDs.insert(candidate.id)
                  }
                }
              )
            }
          }
          Button(action: save) {
            Label("Save Selected", systemImage: "checkmark")
          }
          .disabled(selectedIDs.isEmpty)
        }
      }
    }
  }
}

private struct CompilationAppendSection: View {
  let album: CompilationAlbum
  let folder: URL?
  let plan: CompilationApplyPlan?
  let applyState: ApplyRunState
  let apply: (CompilationApplyPlan) -> Void
  @State private var isConfirmingApply = false

  var body: some View {
    CollectionSection(title: "Append Preview", systemImage: "tag", count: plan?.tracks.count ?? 0) {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(album.name)
            .font(.headline)
          Text("\(album.identity.album) / \(album.identity.albumArtist)")
            .foregroundStyle(.secondary)
          if let folder {
            Text(folder.path(percentEncoded: false))
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        if let plan {
          HStack {
            Label("\(plan.tracks.count) files ready", systemImage: "checkmark.circle")
              .foregroundStyle(.green)
            Spacer()
            Button {
              isConfirmingApply = true
            } label: {
              Label("Apply to Working", systemImage: "hammer")
            }
            .disabled(applyState.isRunning)
            .confirmationDialog("Apply policy stamp into Working?", isPresented: $isConfirmingApply) {
              Button("Apply") {
                apply(plan)
              }
              Button("Cancel", role: .cancel) {
              }
            }
          }
          CompilationApplyStatus(state: applyState)
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(plan.tracks) { track in
              CompilationTrackPlanRow(track: track)
            }
          }
        } else {
          EmptyCollectionRow(title: "Choose a registry entry, then append a folder of new songs")
        }
      }
    }
  }
}

private struct CompilationAlbumRow: View {
  let album: CompilationAlbum
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      ArtworkThumbnail(data: album.displayImage)
      VStack(alignment: .leading, spacing: 4) {
        Text(album.name)
          .font(.headline)
        Text("\(album.identity.album) / \(album.identity.albumArtist)")
          .foregroundStyle(.secondary)
        if !album.ruleset.groupingTokens.isEmpty {
          Text(album.ruleset.groupingTokens.formatted())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.tint)
      }
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 10)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

private struct CollectionSeedCandidateRow: View {
  let candidate: CompilationAlbumSeedCandidate
  let isSelected: Bool
  let toggle: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Toggle(isOn: Binding(get: { isSelected }, set: { _ in toggle() })) {
        EmptyView()
      }
      .labelsHidden()
      ArtworkThumbnail(data: candidate.album.displayImage)
      VStack(alignment: .leading, spacing: 4) {
        Text(candidate.album.name)
          .font(.headline)
        Text("\(candidate.album.identity.album) / \(candidate.album.identity.albumArtist)")
          .foregroundStyle(.secondary)
        Text("\(candidate.trackCount) tracks")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(candidate.warnings, id: \.self) { warning in
          Label(warning, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      Spacer()
    }
    .padding(.vertical, 8)
  }
}

private struct CompilationTrackPlanRow: View {
  let track: CompilationTrackPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(track.sourceFile.url.lastPathComponent)
          .font(.headline)
        Spacer()
        Label(
          track.artwork == .keepExisting ? "Keeps art" : "Fallback art",
          systemImage: track.artwork == .keepExisting ? "photo" : "photo.badge.plus"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
        ForEach(track.diffs) { diff in
          GridRow {
            Text(diff.field)
              .foregroundStyle(.secondary)
            Text(diff.current ?? "none")
            Image(systemName: "arrow.right")
              .foregroundStyle(.secondary)
            Text(diff.proposed ?? "removed")
              .fontWeight(.medium)
          }
        }
      }
      .font(.caption)
    }
    .padding(12)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

private struct CollectionSeedStatus: View {
  let state: CollectionSeedState

  var body: some View {
    switch state {
    case .idle:
      EmptyCollectionRow(title: "Seed from one album folder or a parent folder of album folders")
    case let .running(url):
      Label("Reading \(url.lastPathComponent)", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .completed(candidates):
      Label("\(candidates.count) candidates found", systemImage: "checkmark.circle")
        .foregroundStyle(.green)
    case let .saved(count):
      Label("\(count) albums saved", systemImage: "checkmark.circle")
        .foregroundStyle(.green)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }
}

private struct CompilationApplyStatus: View {
  let state: ApplyRunState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running:
      Label("Applying tags to Working copies", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .completed(result):
      Label(result.exitSummary, systemImage: result.didSucceed ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(result.didSucceed ? .green : .orange)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }
}

private struct CollectionSection<Content: View>: View {
  let title: String
  let systemImage: String
  let count: Int
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(title, systemImage: systemImage)
          .font(.headline)
        Spacer()
        Text("\(count)")
          .foregroundStyle(.secondary)
      }
      content
    }
    .padding(.vertical, 4)
  }
}

private struct EmptyCollectionRow: View {
  let title: String

  var body: some View {
    Text(title)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }
}

private struct ArtworkThumbnail: View {
  let data: Data?

  var body: some View {
    Group {
      if let data, let image = NSImage(data: data) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "square.stack")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 44, height: 44)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
