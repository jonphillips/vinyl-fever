import AppKit
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers
import VinylFeverCore

struct CollectionsView: View {
  @Bindable var model: AppModel
  @FetchAll(CompilationAlbum.order(by: \.name))
  private var albums: [CompilationAlbum]
  @FetchAll(CollectionPolicy.order(by: \.name))
  private var policies: [CollectionPolicy]
  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]
  @State private var selectedAlbumID: CompilationAlbum.ID?

  var body: some View {
    let selectedAlbum = albums.first { $0.id == selectedAlbumID }
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        CollectionHeader(
          seedFolder: openSeedFolder
        )
        InboxSummarySection(
          summary: model.inboxSummary,
          albums: albums,
          clear: { albumID in
            model.clearInboxQueue(albumID: albumID)
          }
        )
        CollectionRegistrySection(
          albums: albums,
          selectedAlbumID: $selectedAlbumID,
          onDropAudio: { album, urls in
            stageDroppedFiles(onto: album, urls: urls)
          }
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
            policies: policies,
            folder: model.compilationAppendFolder,
            appendGrouping: $model.compilationAppendGrouping,
            appendComments: $model.compilationAppendComments,
            plan: model.compilationApplyPlan,
            recipeProposalsByFileID: model.compilationRecipeProposalsByFileID,
            applyState: model.compilationApplyState,
            conversionState: model.compilationConversionState,
            importState: model.compilationImportState,
            isInboxSourced: model.isAppendSourcedFromInbox(album: selectedAlbum),
            clearQueue: {
              model.clearCurrentAppendQueue(album: selectedAlbum)
            },
            removeItem: { file in
              Task {
                await model.removeAppendQueueItem(album: selectedAlbum, file: file.url)
              }
            },
            appendFolder: {
              openAppendFolder(album: selectedAlbum)
            },
            rebuildPlan: {
              guard let folder = model.compilationAppendFolder else {
                return
              }
              model.scheduleCompilationAppendPlanRebuild(entry: selectedAlbum, sourceFolder: folder)
            },
            apply: {
              Task {
                await model.applyCurrentCompilationAppend(entry: selectedAlbum)
              }
            },
            saveGroupingAsDefault: {
              model.saveCompilationAppendGroupingAsDefault(for: selectedAlbum)
            },
            setCover: {
              guard let url = chooseCoverImage() else {
                return
              }
              Task {
                await model.setCompilationAlbumCover(album: selectedAlbum, imageURL: url)
              }
            },
            setPolicy: { policyID in
              model.setCompilationPolicy(policyID, for: selectedAlbum)
            },
            onDropAudio: { urls in
              stageDroppedFiles(onto: selectedAlbum, urls: urls)
            }
          )
        }
      }
      .frame(maxWidth: 1040, alignment: .leading)
      .padding(24)
    }
    .navigationTitle("Collections")
    .onChange(of: selectedAlbumID) { oldValue, newValue in
      guard oldValue != newValue else {
        return
      }
      let defaultGrouping = newValue
        .flatMap { id in albums.first { $0.id == id } }
        .map { $0.ruleset.groupingTokens.joined(separator: CompilationRuleset.groupingDelimiter) }
        ?? ""
      model.clearCompilationAppendScratch(defaultGrouping: defaultGrouping)
      model.compilationApplyPlan = nil
      model.compilationAppendFolder = nil
      model.compilationAppendAlbumID = nil
    }
    .toolbar {
      ToolbarItem {
        Button(action: openSeedFolder) {
          Label("Seed", systemImage: "rectangle.stack.badge.plus")
        }
      }
    }
    .task(id: AppSetting.current(from: persistedSettings)) {
      await model.refreshToolStatuses(settings: AppSetting.current(from: persistedSettings))
    }
    .task {
      model.refreshInboxSummary()
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

  /// Stage audio files dropped onto a Collection: select that album (so the append section
  /// tracks it) and hand the URLs to the Inbox-backed append rail.
  private func stageDroppedFiles(onto album: CompilationAlbum, urls: [URL]) {
    selectedAlbumID = album.id
    Task {
      await model.stageDroppedFilesForAppend(entry: album, files: urls)
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

  private func chooseCoverImage() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.png, .jpeg, .gif, .image]
    panel.prompt = "Set Cover"
    return panel.runModal() == .OK ? panel.url : nil
  }
}

private struct CollectionHeader: View {
  let seedFolder: () -> Void

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
    }
  }
}

/// The standing Inbox visibility surface: per-album pending counts from
/// `CollectionInboxClient.summary()`, an aggregate line, and a manual per-album Clear for
/// abandoning a queue without appending. An entry whose `albumID` no longer resolves against
/// the registry (a since-deleted album) renders as "Unknown album" and is still clearable.
private struct InboxSummarySection: View {
  let summary: [InboxAlbumSummary]
  let albums: [CompilationAlbum]
  let clear: (CompilationAlbum.ID) -> Void

  private var totalTracks: Int {
    summary.reduce(0) { $0 + $1.fileCount }
  }

  var body: some View {
    CollectionSection(title: "Inbox", systemImage: "tray", count: totalTracks) {
      if summary.isEmpty {
        EmptyCollectionRow(title: "Inbox empty")
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            "\(totalTracks) track\(totalTracks == 1 ? "" : "s") staged across "
              + "\(summary.count) album\(summary.count == 1 ? "" : "s")"
          )
          .foregroundStyle(.secondary)
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(summary) { entry in
              InboxSummaryRow(
                title: albums.first { $0.id == entry.albumID }?.name,
                fileCount: entry.fileCount,
                clear: { clear(entry.albumID) }
              )
            }
          }
        }
      }
    }
  }
}

private struct InboxSummaryRow: View {
  let title: String?
  let fileCount: Int
  let clear: () -> Void
  @State private var isConfirmingClear = false

  var body: some View {
    HStack {
      Text(title ?? "Unknown album")
        .foregroundStyle(title == nil ? .secondary : .primary)
      Spacer()
      Text("\(fileCount)")
        .foregroundStyle(.secondary)
      Button("Clear") {
        isConfirmingClear = true
      }
      .buttonStyle(.borderless)
      .confirmationDialog(
        "Clear the staged queue for \(title ?? "this album")?",
        isPresented: $isConfirmingClear
      ) {
        Button("Clear", role: .destructive) {
          clear()
        }
        Button("Cancel", role: .cancel) {}
      }
    }
    .padding(.vertical, 6)
  }
}

private struct CollectionRegistrySection: View {
  let albums: [CompilationAlbum]
  @Binding var selectedAlbumID: CompilationAlbum.ID?
  let onDropAudio: (CompilationAlbum, [URL]) -> Void

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

  var body: some View {
    CollectionSection(title: "Registry", systemImage: "rectangle.stack", count: albums.count) {
      if albums.isEmpty {
        EmptyCollectionRow(title: "No compilation albums registered")
      } else {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
          ForEach(albums) { album in
            CompilationAlbumTileButton(
              album: album,
              isSelected: selectedAlbumID == album.id,
              // Tap toggles: a second tap on the selected tile deselects it.
              toggleSelect: {
                selectedAlbumID = selectedAlbumID == album.id ? nil : album.id
              },
              onDropAudio: { urls in onDropAudio(album, urls) }
            )
          }
        }
      }
    }
  }
}

/// A registry tile that is both a selection button and a drop target: dropping loose song files
/// onto it stages them to *that* album's Inbox and drives the append preview.
private struct CompilationAlbumTileButton: View {
  let album: CompilationAlbum
  let isSelected: Bool
  let toggleSelect: () -> Void
  let onDropAudio: ([URL]) -> Void
  @State private var isDropTargeted = false

  var body: some View {
    Button(action: toggleSelect) {
      CompilationAlbumTile(album: album, isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.accentColor, lineWidth: 2)
        .opacity(isDropTargeted ? 1 : 0)
    }
    .dropDestination(for: URL.self) { urls, _ in
      onDropAudio(urls)
      return true
    } isTargeted: { isDropTargeted = $0 }
  }
}

/// A cover-forward registry card: square artwork on top, title and identity beneath — so the
/// Registry reads like a shelf of albums rather than a list of rows.
private struct CompilationAlbumTile: View {
  let album: CompilationAlbum
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.secondary.opacity(0.08))
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          if let data = album.displayImage, let image = NSImage(data: data) {
            Image(nsImage: image)
              .resizable()
              .scaledToFill()
          } else {
            Image(systemName: "square.stack")
              .font(.largeTitle)
              .foregroundStyle(.secondary)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .font(.title3)
              .foregroundStyle(.tint)
              .padding(4)
              .background(.background, in: Circle())
              .padding(6)
          }
        }
      VStack(alignment: .leading, spacing: 2) {
        Text(album.name)
          .font(.subheadline)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text("\(album.identity.album) / \(album.identity.albumArtist)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(8)
    .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 10))
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
  let policies: [CollectionPolicy]
  let folder: URL?
  @Binding var appendGrouping: String
  @Binding var appendComments: String
  let plan: CompilationApplyPlan?
  let recipeProposalsByFileID: [ScannedAudioFile.ID: [CompilationRecipeProposal]]
  let applyState: ApplyRunState
  let conversionState: ConversionRunState
  let importState: LibraryImportState
  /// Whether the queue behind this preview is the album's drop-staged Inbox (vs. a picked
  /// folder). Gates the destructive per-item Remove — only app-owned staged copies are removable.
  let isInboxSourced: Bool
  let clearQueue: () -> Void
  let removeItem: (ScannedAudioFile) -> Void
  let appendFolder: () -> Void
  let rebuildPlan: () -> Void
  let apply: () -> Void
  let saveGroupingAsDefault: () -> Void
  let setCover: () -> Void
  let setPolicy: (CollectionPolicy.ID?) -> Void
  let onDropAudio: ([URL]) -> Void
  @State private var isConfirmingApply = false
  @State private var isConfirmingClear = false

  var body: some View {
    CollectionSection(title: "Append Preview", systemImage: "tag", count: plan?.tracks.count ?? 0) {
      VStack(alignment: .leading, spacing: 14) {
        CompilationAppendDropZone(
          albumName: album.name,
          hasBoundPolicy: album.collectionPolicyID != nil,
          onDropAudio: onDropAudio
        )
        HStack(alignment: .top) {
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
            CollectionPolicyPicker(
              album: album,
              policies: policies,
              setPolicy: setPolicy
            )
            if folder != nil {
              VStack(alignment: .leading, spacing: 8) {
                Text("This append only")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                LabeledContent("Grouping") {
                  HStack {
                    TextField("Optional token", text: $appendGrouping)
                    Button("Save as Default", action: saveGroupingAsDefault)
                  }
                  .onChange(of: appendGrouping) { rebuildPlan() }
                  .onSubmit(rebuildPlan)
                }
                LabeledContent("Comments") {
                  TextField("Optional note", text: $appendComments)
                    .onChange(of: appendComments) { rebuildPlan() }
                    .onSubmit(rebuildPlan)
                }
                Text("Preview updates shortly after editing.")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 8) {
            Button(action: appendFolder) {
              Label("Append Folder", systemImage: "plus")
            }
            Button(action: setCover) {
              Label("Set Cover…", systemImage: "photo")
            }
          }
        }
        if let plan {
          HStack {
            Label("\(plan.tracks.count) files ready", systemImage: "checkmark.circle")
              .foregroundStyle(.green)
            Spacer()
            Button(role: .destructive) {
              isConfirmingClear = true
            } label: {
              Label("Clear Queue", systemImage: "trash")
            }
            .disabled(isRunning)
            .confirmationDialog(
              "Clear the entire append queue?",
              isPresented: $isConfirmingClear
            ) {
              Button("Clear Queue", role: .destructive) {
                clearQueue()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              let clearMessage: String = isInboxSourced
                ? "Removes all \(plan.tracks.count) staged files from this album's Inbox. Your originals are untouched."
                : "Discards this preview. The picked folder is left on disk."
              Text(clearMessage)
            }
            Button {
              isConfirmingApply = true
            } label: {
              Label("Append to Music", systemImage: "square.and.arrow.down")
            }
            .disabled(isRunning)
            .confirmationDialog("Append stamped copies to Music?", isPresented: $isConfirmingApply) {
              Button("Append") {
                apply()
              }
              Button("Cancel", role: .cancel) {
              }
            }
          }
          CompilationApplyStatus(state: applyState)
          CompilationConversionStatus(state: conversionState)
          CompilationImportStatus(state: importState)
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(plan.tracks) { track in
              // Removing a queued item trashes an app-owned staged copy, so only offer it for
              // an Inbox-sourced queue and never for a user-picked folder.
              let removeAction: (() -> Void)? = isInboxSourced && !isRunning
                ? { removeItem(track.sourceFile) }
                : nil
              CompilationTrackPlanRow(
                track: track,
                recipeProposals: recipeProposalsByFileID[track.id] ?? [],
                remove: removeAction
              )
            }
          }
        } else {
          EmptyCollectionRow(title: "Choose a registry entry, then append a folder of new songs")
        }
      }
    }
  }

  private var isRunning: Bool {
    applyState.isRunning ||
      conversionState.isRunning ||
      importState.isRunning
  }
}

/// The always-present drop target for the selected album: dropping songs here stages them to the
/// album's Inbox and builds the append preview. When no policy is bound it also carries a
/// non-blocking nudge — the drop still stamps compilation identity regardless.
private struct CompilationAppendDropZone: View {
  let albumName: String
  let hasBoundPolicy: Bool
  let onDropAudio: ([URL]) -> Void
  @State private var isDropTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "square.and.arrow.down.on.square")
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text("Drop songs here to append to “\(albumName)”")
            .fontWeight(.medium)
          Text("Files copy into this album's Inbox and preview like a folder pick.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      if !hasBoundPolicy {
        Label(
          "No policy bound — dropped tracks get compilation identity but no recipe cleanup. Bind a policy to auto-tag.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(isDropTargeted ? 0.16 : 0.06))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
          style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
        )
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .dropDestination(for: URL.self) { urls, _ in
      onDropAudio(urls)
      return true
    } isTargeted: { isDropTargeted = $0 }
  }
}

private struct CollectionPolicyPicker: View {
  let album: CompilationAlbum
  let policies: [CollectionPolicy]
  let setPolicy: (CollectionPolicy.ID?) -> Void

  var body: some View {
    Picker(
      "Collection Policy",
      selection: Binding(
        get: { album.collectionPolicyID },
        set: setPolicy
      )
    ) {
      Text("None").tag(CollectionPolicy.ID?.none)
      ForEach(policies) { policy in
        Text(policy.name).tag(CollectionPolicy.ID?.some(policy.id))
      }
    }
    .pickerStyle(.menu)
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
  let recipeProposals: [CompilationRecipeProposal]
  /// When non-nil, shows a per-item Remove control that drops this file from the append queue.
  var remove: (() -> Void)?

  var body: some View {
    let hasAppliedRecipeGrouping = recipeProposals.contains {
      $0.proposal.issues.isEmpty && $0.proposal.delta.grouping != nil
    }

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
        if let remove {
          Button(role: .destructive, action: remove) {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.borderless)
          .help("Remove this file from the append queue")
        }
      }
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
        ForEach(track.diffs.filter { diff in
          !hasAppliedRecipeGrouping || diff.field != "Grouping"
        }) { diff in
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
      if !recipeProposals.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recipe edits")
            .font(.caption)
            .fontWeight(.semibold)
          ForEach(recipeProposals) { recipeProposal in
            RecipeProposalPreview(proposal: recipeProposal, current: track.current)
          }
        }
      }
      if track.proposed.isCompilation == false {
        Label(
          "Clearing the per-track Compilation flag is intentional: the album is unified by Album Artist + Grouping, not the iTunes compilation checkbox (which fragments tracks in Music).",
          systemImage: "info.circle"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}

private struct RecipeProposalPreview: View {
  let proposal: CompilationRecipeProposal
  let current: AudioTags

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      let diffs = Self.diffs(for: proposal.previewDelta, current: current)
      if !diffs.isEmpty {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
          ForEach(diffs) { diff in
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
      }
      if !proposal.heldFields.isEmpty {
        ForEach(proposal.heldFields.sorted { $0.rawValue < $1.rawValue }, id: \.self) { field in
          Label(
            "\(field.displayName) held by collection — not applied",
            systemImage: "arrow.uturn.left.circle"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      Text(proposal.proposal.reason)
        .font(.caption2)
        .foregroundStyle(.secondary)
      if !proposal.proposal.issues.isEmpty {
        Label(
          "Review required — not applied",
          systemImage: "exclamationmark.triangle"
        )
        .foregroundStyle(.orange)
        .font(.caption2)
        ForEach(proposal.proposal.issues, id: \.self) { issue in
          Text(Self.issueMessage(issue))
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }
    }
    .padding(.leading, 12)
  }

  private static func diffs(for proposed: ProposedTags, current: AudioTags) -> [CompilationTagDiff] {
    ProposedTags.Field.allCases
      .filter {
        $0.isStringValued
          && proposed.stringValue(for: $0) != nil
          && proposed.stringValue(for: $0) != current.stringValue(for: $0)
      }
      .map { field in
        CompilationTagDiff(
          field: field.displayName,
          current: current.stringValue(for: field),
          proposed: proposed.stringValue(for: field)
        )
      }
  }

  private static func issueMessage(_ issue: RecipeIssue) -> String {
    switch issue {
    case .valueNotInFilename:
      "The proposed value was not evidenced by the filename."
    case .modelOutputUnparseable:
      "The model output could not be parsed."
    }
  }
}

private struct CollectionSeedStatus: View {
  let state: CollectionSeedState

  var body: some View {
    switch state {
    case .idle:
      EmptyCollectionRow(title: "Seed from one album folder or a parent folder of album folders")
    case let .running(progress):
      VStack(alignment: .leading, spacing: 4) {
        if progress.total > 0 {
          Label(
            "Reading \(progress.url.lastPathComponent) — \(progress.completed) of \(progress.total) albums",
            systemImage: "hourglass"
          )
          .foregroundStyle(.secondary)
          ProgressView(value: Double(progress.completed), total: Double(progress.total))
        } else {
          Label("Reading \(progress.url.lastPathComponent)", systemImage: "hourglass")
            .foregroundStyle(.secondary)
          ProgressView()
        }
      }
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

private struct CompilationConversionStatus: View {
  let state: ConversionRunState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .running:
      Label("Converting FLAC outputs", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .skipped(message):
      Label(message, systemImage: "checkmark.circle")
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

private struct CompilationImportStatus: View {
  let state: LibraryImportState

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .requestingPermission:
      Label("Requesting Music automation", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case .running:
      Label("Importing into Music", systemImage: "hourglass")
        .foregroundStyle(.secondary)
    case let .permission(permission):
      Label(permission.displayMessage, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
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
  let size: CGFloat

  init(data: Data?, size: CGFloat = 44) {
    self.data = data
    self.size = size
  }

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
    .frame(width: size, height: size)
    .background(Color.secondary.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
