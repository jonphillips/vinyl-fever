import AppKit
import Dependencies
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers
import VinylFeverCore

struct LiveShowsView: View {
  @Bindable var model: AppModel
  @State private var isShowingNormalizer = false

  var body: some View {
    Group {
      if let scannedShowFolder = model.scannedShowFolder {
        ScannedShowFolderView(
          folder: scannedShowFolder,
          model: model,
          openFolder: openFolder,
          openSetlistFile: openSetlistFile,
          openNormalizer: { isShowingNormalizer = true }
        )
      } else {
        EmptyLiveShowsView(
          scanErrorMessage: model.scanErrorMessage,
          openFolder: openFolder
        )
      }
    }
    .navigationTitle("Live Shows")
    .toolbar {
      ToolbarItem {
        Button {
          isShowingNormalizer = true
        } label: {
          Label("Normalize Notes", systemImage: "wand.and.stars")
        }
        .help("AI: turn raw trading notes into a structured setlist. Distinct from Parse Setlist (deterministic).")
      }
      ToolbarItem {
        Button(action: openFolder) {
          Label("Open Show Folder", systemImage: "folder")
        }
      }
    }
    .sheet(isPresented: $isShowingNormalizer) {
      SetlistNormalizerSheet(model: model)
    }
  }

  private func openFolder() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = false
    panel.prompt = "Open"

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    model.scanShowFolder(at: url)
  }

  private func openSetlistFile() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.canCreateDirectories = false
    panel.allowedContentTypes = [.plainText, .text]
    panel.prompt = "Load"

    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    model.loadSetlistText(from: url)
  }
}

private struct EmptyLiveShowsView: View {
  let scanErrorMessage: String?
  let openFolder: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ContentUnavailableView {
          Label("Live Shows", systemImage: "music.note.list")
        } description: {
          if let scanErrorMessage {
            Text(scanErrorMessage)
          }
        } actions: {
          Button(action: openFolder) {
            Label("Open Show Folder", systemImage: "folder")
          }
          .buttonStyle(.borderedProminent)
        }

        RunHistorySection()
      }
      .frame(maxWidth: 980, alignment: .leading)
      .padding(24)
    }
  }
}

private struct ScannedShowFolderView: View {
  let folder: ScannedShowFolder
  @Bindable var model: AppModel
  let openFolder: () -> Void
  let openSetlistFile: () -> Void
  let openNormalizer: () -> Void

  @State private var selectedTab: ActivityTab = .setlist

  @FetchAll(SourceLabel.order(by: \.token))
  private var persistedSourceLabels: [SourceLabel]
  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]

  var body: some View {
    let sourceLabels = SourceLabel.deduplicated(persistedSourceLabels)
    let settings = AppSetting.current(from: persistedSettings)
    let selectedSourceLabel = sourceLabels.first { $0.id == model.selectedSourceLabelID }
    let metadata = model.setlistDraft.map {
      ShowMetadata(tags: $0.tags, source: selectedSourceLabel)
    }
    let showPlan: ShowPlan? =
      if let setlistDraft = model.setlistDraft, let metadata {
        ShowPlan(folder: folder, setlist: setlistDraft, metadata: metadata)
      } else {
        nil
      }

    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        ShowHeader(
          root: folder.root,
          openFolder: openFolder,
          done: model.clearScannedShow
        )
        if let errorMessage = model.scanErrorMessage {
          ScanErrorBanner(message: errorMessage)
        }
        if let resolution = model.completedLibraryResolution {
          CompletionPill(resolution: resolution)
        }
        PipelineStrip(stage: model.pipelineStage, selection: $selectedTab)
        ActivityTabBar(selection: $selectedTab)
      }
      .frame(maxWidth: 980, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 16)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          switch selectedTab {
          case .setlist:
            setlistTab(sourceLabels: sourceLabels, metadata: metadata)
          case .plan:
            planTab(showPlan: showPlan)
          case .output:
            OutputTabPlaceholder(stage: model.pipelineStage)
          case .history:
            if let errorMessage = model.runLogErrorMessage {
              ScanErrorBanner(message: errorMessage)
            }
            RunHistorySection()
          }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(24)
      }
    }
    .task(id: settings) {
      await model.refreshToolStatuses(settings: settings)
    }
    .task(id: MetadataRefreshID(
      folder: folder,
      toolStatuses: model.toolStatuses,
      hasResolvedToolStatuses: model.hasResolvedToolStatuses
    )) {
      await model.refreshCurrentMetadata()
    }
  }

  // MARK: - Tab bodies (S1 wraps the existing sections unchanged)

  @ViewBuilder
  private func setlistTab(sourceLabels: [SourceLabel], metadata: ShowMetadata?) -> some View {
    ScanSection(
      title: "Audio Files",
      systemImage: "waveform",
      count: folder.audioFiles.count
    ) {
      if folder.audioFiles.isEmpty {
        EmptyScanSectionRow(title: "No audio files")
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(folder.audioFiles) { file in
            ScannedAudioFileRow(file: file, root: folder.root)
          }
        }
      }
    }
    ScanSection(
      title: "Setlists",
      systemImage: "text.page",
      count: folder.setlistCandidates.count
    ) {
      CandidateList(urls: folder.setlistCandidates, root: folder.root)
    }
    SetlistInputSection(
      setlistInput: $model.setlistInput,
      draft: $model.setlistDraft,
      errorMessage: model.setlistErrorMessage,
      setlistCandidates: folder.setlistCandidates,
      root: folder.root,
      parse: model.parseSetlistInput,
      loadCandidate: model.loadSetlistText(from:),
      openSetlistFile: openSetlistFile,
      openNormalizer: openNormalizer
    )
    SourceMetadataSection(
      sourceLabels: sourceLabels,
      selectedSourceLabelID: $model.selectedSourceLabelID,
      metadata: metadata
    )
    ScanSection(
      title: "Cover Art",
      systemImage: "photo",
      count: folder.coverCandidates.count
    ) {
      CandidateList(urls: folder.coverCandidates, root: folder.root)
    }
  }

  @ViewBuilder
  private func planTab(showPlan: ShowPlan?) -> some View {
    PlanPreviewSection(
      plan: showPlan,
      root: folder.root,
      coverURL: folder.coverCandidates.first,
      currentMetadataByFileID: model.currentMetadataByFileID,
      applyState: model.applyState,
      conversionState: model.conversionState,
      verificationState: model.verificationState,
      libraryImportState: model.libraryImportState,
      libraryReadState: model.libraryReadState,
      hasRequiredApplyTools: model.hasRequiredApplyTools(for: showPlan),
      hasRequiredConversionTools: { applyPlan in
        model.hasRequiredConversionTools(for: applyPlan)
      },
      hasSuccessfulApply: { applyPlan in
        model.hasSuccessfulApply(for: applyPlan)
      },
      hasSuccessfulFileVerify: { conversionPlan in
        model.hasSuccessfulFileVerify(for: conversionPlan)
      },
      apply: { plan in
        Task {
          await model.applyShowPlan(plan, coverURL: folder.coverCandidates.first)
        }
      },
      convertAndVerify: { applyPlan in
        Task {
          await model.convertAndVerify(applyPlan)
        }
      },
      importIntoMusicLibrary: { conversionPlan in
        Task {
          await model.importIntoMusicLibrary(for: conversionPlan)
        }
      },
      readMusicLibrary: { conversionPlan in
        Task {
          await model.readMusicLibrary(for: conversionPlan)
        }
      },
      revealWorkingDirectory: {
        Task {
          await model.revealWorkingDirectory()
        }
      },
      revealOutputDirectory: {
        Task {
          await model.revealOutputDirectory()
        }
      }
    )
  }
}

private struct PlanPreviewSection: View {
  let plan: ShowPlan?
  let root: URL
  let coverURL: URL?
  let currentMetadataByFileID: [ScannedAudioFile.ID: AudioMetadataLoadState]
  let applyState: ApplyRunState
  let conversionState: ConversionRunState
  let verificationState: VerificationRunState
  let libraryImportState: LibraryImportState
  let libraryReadState: LibraryReadState
  let hasRequiredApplyTools: Bool
  let hasRequiredConversionTools: (ApplyPlan) -> Bool
  let hasSuccessfulApply: (ApplyPlan) -> Bool
  let hasSuccessfulFileVerify: (ConversionPlan) -> Bool
  let apply: (ShowPlan) -> Void
  let convertAndVerify: (ApplyPlan) -> Void
  let importIntoMusicLibrary: (ConversionPlan) -> Void
  let readMusicLibrary: (ConversionPlan) -> Void
  let revealWorkingDirectory: () -> Void
  let revealOutputDirectory: () -> Void

  var body: some View {
    ScanSection(
      title: "Import Plan",
      systemImage: "list.bullet.rectangle",
      count: plan?.tracks.count ?? 0
    ) {
      if let plan {
        let applyPlan = ApplyPlan(showPlan: plan, showRoot: root, coverURL: coverURL)
        let conversionPlan = ConversionPlan(applyPlan: applyPlan)
        VStack(alignment: .leading, spacing: 16) {
          PlanReadinessSummary(
            plan: plan,
            applyPlan: applyPlan,
            root: root,
            applyState: applyState,
            conversionState: conversionState,
            verificationState: verificationState,
            libraryImportState: libraryImportState,
            libraryReadState: libraryReadState,
            hasRequiredApplyTools: hasRequiredApplyTools,
            hasRequiredConversionTools: hasRequiredConversionTools(applyPlan),
            hasSuccessfulApply: hasSuccessfulApply(applyPlan),
            hasSuccessfulFileVerify: hasSuccessfulFileVerify(conversionPlan),
            apply: { apply(plan) },
            convertAndVerify: { convertAndVerify(applyPlan) },
            importIntoMusicLibrary: { importIntoMusicLibrary(conversionPlan) },
            readMusicLibrary: { readMusicLibrary(conversionPlan) },
            revealWorkingDirectory: revealWorkingDirectory,
            revealOutputDirectory: revealOutputDirectory
          )
          ProposedMetadataSummary(plan: plan)
          ApplyOperationsPreview(applyPlan: applyPlan, root: root)
          if plan.tracks.isEmpty {
            EmptyScanSectionRow(title: "No file-to-track mappings")
          } else {
            LazyVStack(alignment: .leading, spacing: 10) {
              ForEach(plan.tracks) { trackPlan in
                TrackPlanRow(
                  trackPlan: trackPlan,
                  root: root,
                  currentMetadata: currentMetadataByFileID[trackPlan.sourceFile.id] ?? .notLoaded
                )
              }
            }
          }
        }
        .padding(.vertical, 8)
      } else {
        EmptyScanSectionRow(title: "Parse a setlist to preview the import plan")
      }
    }
  }
}

private struct PlanReadinessSummary: View {
  let plan: ShowPlan
  let applyPlan: ApplyPlan
  let root: URL
  let applyState: ApplyRunState
  let conversionState: ConversionRunState
  let verificationState: VerificationRunState
  let libraryImportState: LibraryImportState
  let libraryReadState: LibraryReadState
  let hasRequiredApplyTools: Bool
  let hasRequiredConversionTools: Bool
  let hasSuccessfulApply: Bool
  let hasSuccessfulFileVerify: Bool
  let apply: () -> Void
  let convertAndVerify: () -> Void
  let importIntoMusicLibrary: () -> Void
  let readMusicLibrary: () -> Void
  let revealWorkingDirectory: () -> Void
  let revealOutputDirectory: () -> Void

  @State private var isConfirmingApply = false

  var body: some View {
    let conversionPlan = ConversionPlan(applyPlan: applyPlan)
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Label(
          plan.isReadyToImport ? "Ready to import" : "Not ready to import",
          systemImage: plan.isReadyToImport ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .foregroundStyle(plan.isReadyToImport ? .green : .orange)
        Spacer()
        Button {
          isConfirmingApply = true
        } label: {
          Label("Apply", systemImage: "hammer")
        }
        .disabled(!canApply)
        .help(disabledReason ?? "Apply the plan into Working.")
        .confirmationDialog("Apply into Working?", isPresented: $isConfirmingApply) {
          Button("Apply") {
            apply()
          }
          Button("Cancel", role: .cancel) {
          }
        } message: {
          Text("Copies and tags \(plan.tracks.count) files. Existing Working destinations are reported as conflicts.")
        }
        Button(action: convertAndVerify) {
          Label(convertButtonTitle(conversionPlan), systemImage: conversionSystemImage(conversionPlan))
        }
        .disabled(!canConvert)
        .help(convertDisabledReason ?? convertHelp(conversionPlan))
        Button(action: importIntoMusicLibrary) {
          Label("Import", systemImage: "square.and.arrow.down")
        }
        .disabled(!canImport)
        .help(importDisabledReason ?? "Add the verified files to Music.")
        Button(action: readMusicLibrary) {
          Label("Read Music", systemImage: "music.note")
        }
        .disabled(!canReadMusic)
        .help(readMusicDisabledReason ?? "Read Music for this album and resolve produced files.")
      }

      if !plan.issues.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(plan.issues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }

      ApplyRunStatus(state: applyState, revealWorkingDirectory: revealWorkingDirectory)
      ConversionRunStatus(
        state: conversionState,
        plan: conversionPlan,
        revealOutputDirectory: revealOutputDirectory
      )
      VerificationRunStatus(state: verificationState, root: root)
      LibraryImportStatus(state: libraryImportState, root: root)
      LibraryReadStatus(state: libraryReadState, root: root)
    }
  }

  private var canApply: Bool {
    plan.isReadyToImport && hasRequiredApplyTools && !applyState.isRunning
  }

  private var disabledReason: String? {
    if applyState.isRunning {
      return "Apply is already running."
    }
    if !plan.isReadyToImport {
      return "Resolve blocking plan issues first."
    }
    if !hasRequiredApplyTools {
      return "Required audio tools are missing."
    }
    return nil
  }

  private var canConvert: Bool {
    hasSuccessfulApply &&
      hasRequiredConversionTools &&
      !applyState.isRunning &&
      !conversionState.isRunning &&
      !verificationState.isRunning &&
      !libraryImportState.isRunning &&
      !libraryReadState.isRunning
  }

  private var convertDisabledReason: String? {
    if applyState.isRunning {
      return "Apply is already running."
    }
    if conversionState.isRunning {
      return "Conversion is already running."
    }
    if verificationState.isRunning {
      return "Verification is already running."
    }
    if libraryImportState.isRunning {
      return "Import is already running."
    }
    if libraryReadState.isRunning {
      return "Music read is already running."
    }
    if !hasSuccessfulApply {
      return "Apply must finish successfully first."
    }
    if !hasRequiredConversionTools {
      return "Required conversion and verification tools are missing."
    }
    return nil
  }

  private var canReadMusic: Bool {
    hasSuccessfulFileVerify &&
      !applyState.isRunning &&
      !conversionState.isRunning &&
      !verificationState.isRunning &&
      !libraryImportState.isRunning &&
      !libraryReadState.isRunning
  }

  private var canImport: Bool {
    hasSuccessfulFileVerify &&
      !applyState.isRunning &&
      !conversionState.isRunning &&
      !verificationState.isRunning &&
      !libraryImportState.isRunning &&
      !libraryReadState.isRunning
  }

  private var importDisabledReason: String? {
    if applyState.isRunning {
      return "Apply is already running."
    }
    if conversionState.isRunning {
      return "Conversion is already running."
    }
    if verificationState.isRunning {
      return "Verification is already running."
    }
    if libraryImportState.isRunning {
      return "Import is already running."
    }
    if libraryReadState.isRunning {
      return "Music read is already running."
    }
    if !hasSuccessfulFileVerify {
      return "File verification must finish successfully first."
    }
    return nil
  }

  private var readMusicDisabledReason: String? {
    if applyState.isRunning {
      return "Apply is already running."
    }
    if conversionState.isRunning {
      return "Conversion is already running."
    }
    if verificationState.isRunning {
      return "Verification is already running."
    }
    if libraryImportState.isRunning {
      return "Import is already running."
    }
    if libraryReadState.isRunning {
      return "Music read is already running."
    }
    if !hasSuccessfulFileVerify {
      return "File verification must finish successfully first."
    }
    return nil
  }

  private func convertButtonTitle(_ plan: ConversionPlan) -> LocalizedStringResource {
    plan.requiresConversion ? "Convert" : "Verify"
  }

  private func conversionSystemImage(_ plan: ConversionPlan) -> String {
    plan.requiresConversion ? "arrow.triangle.2.circlepath" : "checkmark.shield"
  }

  private func convertHelp(_ plan: ConversionPlan) -> String {
    if plan.requiresConversion {
      return "Convert FLAC Working files to ALAC and verify Output."
    }
    return "Verify tagged Working files."
  }
}

private struct ApplyRunStatus: View {
  let state: ApplyRunState
  let revealWorkingDirectory: () -> Void

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case let .running(plan):
      Label("Applying \(plan.tracks.count) files", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .completed(result):
      HStack(spacing: 10) {
        Label(
          result.exitSummary,
          systemImage: result.didSucceed ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .foregroundStyle(result.didSucceed ? .green : .orange)
        Button(action: revealWorkingDirectory) {
          Label("Reveal Working", systemImage: "folder")
        }
      }
      .font(.callout)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

private struct ConversionRunStatus: View {
  let state: ConversionRunState
  let plan: ConversionPlan
  let revealOutputDirectory: () -> Void

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case let .running(plan):
      Label("Converting \(plan.convertibleTracks.count) files", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .skipped(message):
      Label(message, systemImage: "forward")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .completed(result):
      HStack(spacing: 10) {
        Label(
          result.exitSummary,
          systemImage: result.didSucceed ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .foregroundStyle(result.didSucceed ? .green : .orange)
        if result.didSucceed && plan.requiresConversion {
          Button(action: revealOutputDirectory) {
            Label("Reveal Output", systemImage: "folder")
          }
        }
      }
      .font(.callout)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

private struct VerificationRunStatus: View {
  let state: VerificationRunState
  let root: URL

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case let .running(plan):
      Label("Verifying \(plan.tracks.count) files", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .completed(result):
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Label(
            result.didVerify ? "Verified" : "Not verified",
            systemImage: result.didVerify ? "checkmark.seal" : "xmark.seal"
          )
          .foregroundStyle(result.didVerify ? .green : .red)
          Text("\(result.actualFileCount)/\(result.expectedFileCount) files")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(result.files) { file in
            VerificationFileResultRow(result: file, root: root)
          }
        }
      }
      .font(.callout)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

private struct VerificationFileResultRow: View {
  let result: VerificationFileResult
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: result.didVerify ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(result.didVerify ? .green : .red)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(result.url.relativePath(from: root))
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Text(result.note)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct LibraryImportStatus: View {
  let state: LibraryImportState
  let root: URL

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .requestingPermission:
      Label("Requesting Music automation access", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .running(plan):
      Label("Importing \(plan.tracks.count) files into Music", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .permission(permission):
      Label(permission.displayMessage, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(permission == .authorized ? .green : .orange)
    case let .completed(result):
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Label(
            result.didSucceed ? "Imported to Music" : "Import incomplete",
            systemImage: result.didSucceed ? "checkmark.seal" : "xmark.seal"
          )
          .foregroundStyle(result.didSucceed ? .green : .red)
          Text(result.exitSummary)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(result.tracks) { track in
            ImportedTrackRow(track: track, root: root)
          }
        }
      }
      .font(.callout)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

private struct ImportedTrackRow: View {
  let track: ImportedTrack
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(statusColor)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(track.sourceURL.relativePath(from: root))
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Text(track.note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
  }

  private var systemImage: String {
    switch track.status {
    case .imported:
      "checkmark.circle"
    case .alreadyPresent:
      "checkmark.circle"
    case .failed:
      "exclamationmark.triangle"
    }
  }

  private var statusColor: Color {
    switch track.status {
    case .imported:
      .green
    case .alreadyPresent:
      .secondary
    case .failed:
      .red
    }
  }
}

private struct LibraryReadStatus: View {
  let state: LibraryReadState
  let root: URL

  var body: some View {
    switch state {
    case .idle:
      EmptyView()
    case .requestingPermission:
      Label("Requesting Music automation access", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .running(plan):
      Label("Reading Music for \(plan.albumTitle)", systemImage: "hourglass")
        .font(.callout)
        .foregroundStyle(.secondary)
    case let .permission(permission):
      Label(permission.displayMessage, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(permission == .authorized ? .green : .orange)
    case let .completed(result):
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Label(
            result.didResolveAll ? "Music resolved" : "Music unresolved",
            systemImage: result.didResolveAll ? "checkmark.seal" : "xmark.seal"
          )
          .foregroundStyle(result.didResolveAll ? .green : .orange)
          Text("\(result.resolvedCount)/\(result.trackResolutions.count) files")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Text("\(result.libraryTracks.count) Music tracks")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(result.trackResolutions) { resolution in
            LibraryTrackResolutionRow(resolution: resolution, root: root)
          }
        }
      }
      .font(.callout)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.red)
    }
  }
}

private struct LibraryTrackResolutionRow: View {
  let resolution: LibraryTrackResolution
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: resolution.isResolved ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(resolution.isResolved ? .green : .orange)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(resolution.producedFile.relativePath(from: root))
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
  }

  private var detail: String {
    if let libraryRef = resolution.libraryRef {
      let strategy = resolution.strategy?.displayName ?? "unknown"
      return "Matched \(libraryRef.id) by \(strategy)."
    }
    return resolution.failure?.displayMessage ?? "Unresolved."
  }
}

private struct ProposedMetadataSummary: View {
  let plan: ShowPlan

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
      ProposedMetadataRow(title: "Album", value: plan.metadata.albumTitle)
      ProposedMetadataRow(title: "Sort Album", value: plan.metadata.sortAlbum)
      ProposedMetadataRow(title: "Artist", value: plan.metadata.tags.artist.displayText)
      ProposedMetadataRow(title: "Album Artist", value: plan.metadata.tags.albumArtist.displayText)
    }
  }
}

private struct ProposedMetadataRow: View {
  let title: LocalizedStringResource
  let value: String

  var body: some View {
    GridRow {
      Text(title)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
    }
  }
}

private struct ApplyOperationsPreview: View {
  let applyPlan: ApplyPlan
  let root: URL

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Label("Working", systemImage: "folder")
          .font(.subheadline.weight(.semibold))
        Text(applyPlan.workingDirectory.relativePath(from: root))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(Array(applyPlan.operations.enumerated()), id: \.offset) { _, operation in
          ApplyOperationRow(operation: operation, root: root)
        }
      }
    }
  }
}

private struct ApplyOperationRow: View {
  let operation: FileOperation
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(text)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
  }

  private var systemImage: String {
    switch operation {
    case .copy:
      "doc.on.doc"
    case .writeTags:
      "tag"
    }
  }

  private var text: String {
    switch operation {
    case let .copy(source, destination):
      "\(source.relativePath(from: root)) -> \(destination.relativePath(from: root))"
    case let .writeTags(track):
      "tag \(track.workingFile.relativePath(from: root))"
    }
  }
}

private struct TrackPlanRow: View {
  let trackPlan: TrackPlan
  let root: URL
  let currentMetadata: AudioMetadataLoadState

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(trackPlan.proposedTags.trackNumber.map(String.init) ?? "-")
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 28, alignment: .trailing)
      VStack(alignment: .leading, spacing: 6) {
        Text(trackPlan.proposedFilename)
          .font(.callout.monospaced())
          .textSelection(.enabled)
        Text(trackPlan.sourceFile.url.relativePath(from: root))
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
          GridRow {
            Text("")
            Text("Current")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text("Proposed")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
          TrackMetadataComparisonRow(
            title: "Title",
            current: currentMetadata.tags?.title,
            proposed: trackPlan.proposedTags.title
          )
          TrackMetadataComparisonRow(
            title: "Artist",
            current: currentMetadata.tags?.artist,
            proposed: trackPlan.proposedTags.artist
          )
          TrackMetadataComparisonRow(
            title: "Album",
            current: currentMetadata.tags?.album,
            proposed: trackPlan.proposedTags.album
          )
          TrackMetadataComparisonRow(
            title: "Album Artist",
            current: currentMetadata.tags?.albumArtist,
            proposed: trackPlan.proposedTags.albumArtist
          )
          TrackMetadataComparisonRow(
            title: "Track",
            current: currentMetadata.tags?.trackNumber.map(String.init),
            proposed: trackPlan.proposedTags.trackNumber.map(String.init)
          )
          TrackMetadataComparisonRow(
            title: "Disc",
            current: currentMetadata.tags?.discNumber.map(String.init),
            proposed: trackPlan.proposedTags.discNumber.map(String.init)
          )
          TrackMetadataComparisonRow(
            title: "Duration",
            current: currentMetadata.tags?.durationSeconds.map(Self.durationText),
            proposed: nil
          )
        }
        CurrentMetadataStatus(state: currentMetadata)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
  }

  private static func durationText(_ seconds: Double) -> String {
    let roundedSeconds = Int(seconds.rounded())
    let minutes = roundedSeconds / 60
    let remainder = roundedSeconds % 60
    return "\(minutes):\(String(format: "%02d", remainder))"
  }
}

private struct TrackMetadataComparisonRow: View {
  let title: LocalizedStringResource
  let current: String?
  let proposed: String?

  var body: some View {
    GridRow {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TagValueText(value: current)
      TagValueText(value: proposed)
    }
  }
}

private struct TagValueText: View {
  let value: String?

  var body: some View {
    let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayValue =
      if let trimmedValue, !trimmedValue.isEmpty {
        trimmedValue
      } else {
        "None"
      }
    Text(displayValue)
      .font(.caption)
      .foregroundStyle(displayValue == "None" ? .tertiary : .secondary)
      .textSelection(.enabled)
  }
}

private struct CurrentMetadataStatus: View {
  let state: AudioMetadataLoadState

  var body: some View {
    switch state {
    case .notLoaded:
      EmptyView()
    case .loading:
      Label("Reading current tags", systemImage: "hourglass")
        .font(.caption)
        .foregroundStyle(.secondary)
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.orange)
    case let .loaded(tags):
      HStack(spacing: 10) {
        Label(
          tags.hasAudioStream ? "Audio stream" : "No audio stream",
          systemImage: tags.hasAudioStream ? "waveform" : "waveform.slash"
        )
        Label(
          tags.hasEmbeddedArtwork ? "Artwork" : "No artwork",
          systemImage: tags.hasEmbeddedArtwork ? "photo" : "photo.badge.exclamationmark"
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct MetadataRefreshID: Equatable {
  var root: URL
  var fileIDs: [ScannedAudioFile.ID]
  var toolStatuses: [ToolStatus]
  var hasResolvedToolStatuses: Bool

  init(
    folder: ScannedShowFolder,
    toolStatuses: [ToolStatus],
    hasResolvedToolStatuses: Bool
  ) {
    root = folder.root
    fileIDs = folder.audioFiles.map(\.id)
    self.toolStatuses = toolStatuses
    self.hasResolvedToolStatuses = hasResolvedToolStatuses
  }
}

private struct RunHistorySection: View {
  @Fetch(RunHistoryRequest())
  private var runHistory = RunHistoryRequest.Value()

  var body: some View {
    ScanSection(
      title: "Run History",
      systemImage: "clock.arrow.circlepath",
      count: runHistory.entries.count
    ) {
      if runHistory.entries.isEmpty {
        EmptyScanSectionRow(title: "No runs recorded yet")
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(runHistory.entries) { entry in
            RunHistoryEntryRow(entry: entry)
          }
        }
      }
    }
  }
}

private struct RunHistoryEntryRow: View {
  let entry: RunHistoryEntry

  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        RunHistoryCommand(command: entry.run.command)
        if entry.fileOutcomes.isEmpty {
          EmptyScanSectionRow(title: "No file outcomes")
        } else {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(entry.fileOutcomes) { outcome in
              RunFileOutcomeRow(outcome: outcome)
            }
          }
        }
      }
      .padding(.top, 8)
    } label: {
      RunHistoryEntryLabel(entry: entry)
    }
    .padding(.vertical, 8)
  }
}

private struct RunHistoryEntryLabel: View {
  let entry: RunHistoryEntry

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Label(entry.run.kind.displayName, systemImage: "terminal")
        .font(.callout.weight(.semibold))
      Text(entry.run.startedAt, format: .dateTime.month().day().hour().minute())
        .foregroundStyle(.secondary)
      Text(entry.run.exitSummary.isEmpty ? "open" : entry.run.exitSummary)
        .foregroundStyle(entry.run.exitSummary == "ok" ? .green : .secondary)
      Spacer()
      Text(entry.fileOutcomes.count, format: .number)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }
}

private struct RunHistoryCommand: View {
  let command: String

  var body: some View {
    Text(command)
      .font(.caption.monospaced())
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .lineLimit(8)
  }
}

private struct RunFileOutcomeRow: View {
  let outcome: RunFileOutcome

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Label(outcome.status.displayName, systemImage: systemImage)
        .foregroundStyle(statusColor)
        .frame(width: 88, alignment: .leading)
      VStack(alignment: .leading, spacing: 3) {
        Text(outcome.sourcePath)
          .font(.caption.monospaced())
          .textSelection(.enabled)
        if let producedPath = outcome.producedPath {
          Text(producedPath)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        if !outcome.note.isEmpty {
          Text(outcome.note)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var systemImage: String {
    switch outcome.status {
    case .read:
      "checkmark.circle"
    case .created:
      "plus.circle"
    case .skipped:
      "minus.circle"
    case .failed:
      "exclamationmark.triangle"
    }
  }

  private var statusColor: Color {
    switch outcome.status {
    case .read, .created:
      .green
    case .skipped:
      .secondary
    case .failed:
      .red
    }
  }
}

private struct SourceMetadataSection: View {
  let sourceLabels: [SourceLabel]
  @Binding var selectedSourceLabelID: SourceLabel.ID?
  let metadata: ShowMetadata?

  var body: some View {
    ScanSection(
      title: "Source & Album Title",
      systemImage: "record.circle"
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
          GridRow {
            Text("Source")
              .foregroundStyle(.secondary)
            Picker("Source", selection: $selectedSourceLabelID) {
              Text("unknown").tag(SourceLabel.ID?.none)
              ForEach(sourceLabels) { sourceLabel in
                Text(sourceLabel.token).tag(SourceLabel.ID?.some(sourceLabel.id))
              }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
          }

          GridRow {
            Text("Album")
              .foregroundStyle(.secondary)
            Text(metadata?.albumTitle ?? "Parse a setlist to compute the album title.")
              .textSelection(.enabled)
          }

          GridRow {
            Text("Sort Album")
              .foregroundStyle(.secondary)
            Text(metadata?.sortAlbum ?? "Parse a setlist to compute the sort album.")
              .foregroundStyle(metadata == nil ? .secondary : .primary)
              .textSelection(.enabled)
          }
        }

        Text("Manage the source-label vocabulary in Settings.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 8)
    }
  }
}

private struct SetlistInputSection: View {
  @Binding var setlistInput: String
  @Binding var draft: SetlistDraft?
  let errorMessage: String?
  let setlistCandidates: [URL]
  let root: URL
  let parse: () -> Void
  let loadCandidate: (URL) -> Void
  let openSetlistFile: () -> Void
  let openNormalizer: () -> Void

  var body: some View {
    ScanSection(
      title: "Parsed Setlist",
      systemImage: "text.badge.checkmark",
      count: draft?.tracks.count ?? 0
    ) {
      VStack(alignment: .leading, spacing: 14) {
        SetlistTextInput(
          text: $setlistInput,
          parse: parse,
          openSetlistFile: openSetlistFile,
          openNormalizer: openNormalizer
        )
        if !setlistCandidates.isEmpty {
          DetectedSetlistButtons(
            urls: setlistCandidates,
            root: root,
            load: loadCandidate
          )
        }
        if let errorMessage {
          ScanErrorBanner(message: errorMessage)
        }
        if let draft = Binding($draft) {
          SetlistDraftEditor(draft: draft)
        } else {
          EmptyScanSectionRow(title: "No parsed setlist yet")
        }
      }
      .padding(.vertical, 8)
    }
  }
}

private struct SetlistTextInput: View {
  @Binding var text: String
  let parse: () -> Void
  let openSetlistFile: () -> Void
  let openNormalizer: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextEditor(text: $text)
        .font(.body.monospaced())
        .frame(minHeight: 150)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor))
        }
      HStack(spacing: 8) {
        Button(action: openSetlistFile) {
          Label("Load .txt", systemImage: "doc.badge.plus")
        }
        Button(action: parse) {
          Label("Parse Setlist", systemImage: "text.magnifyingglass")
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(
          "Deterministic — reads an already-formatted setlist (ARTIST:/ALBUM: tags, “NN. Title” lines). No AI; raw notes come out as garbage."
        )

        Spacer(minLength: 12)

        Button(action: openNormalizer) {
          Label("Normalize Raw Notes…", systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .help(
          "AI — turns messy raw trading notes into a structured setlist, with a preview before anything is saved."
        )
      }
      // The cue the two buttons lacked: which one is the model, and when to use it.
      Text(
        "Pasting **raw trading notes**? Use **Normalize Raw Notes** — it runs them through AI. **Parse Setlist** only reads a setlist that’s already formatted."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct DetectedSetlistButtons: View {
  let urls: [URL]
  let root: URL
  let load: (URL) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Detected text files")
        .font(.subheadline.weight(.semibold))
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(urls, id: \.self) { url in
            Button {
              load(url)
            } label: {
              Label(url.relativePath(from: root), systemImage: "text.page")
            }
          }
        }
      }
    }
  }
}

private struct SetlistDraftEditor: View {
  @Binding var draft: SetlistDraft

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SetlistTagsEditor(tags: $draft.tags)
      VStack(alignment: .leading, spacing: 8) {
        Text("Tracks")
          .font(.subheadline.weight(.semibold))
        if draft.tracks.isEmpty {
          EmptyScanSectionRow(title: "No tracks parsed")
        } else {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach($draft.tracks) { $track in
              SetlistTrackEditRow(track: $track)
            }
          }
        }
      }
    }
  }
}

private struct SetlistTagsEditor: View {
  @Binding var tags: ShowTags

  var body: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
      EditableTagRow(title: "Artist", text: $tags.artist.text)
      EditableTagRow(title: "Album", text: $tags.album.text)
      EditableTagRow(title: "Album Artist", text: $tags.albumArtist.text)
      EditableTagRow(title: "Date", text: $tags.date.text)
      EditableTagRow(title: "Venue", text: $tags.venue.text)
      EditableTagRow(title: "Location", text: $tags.location.text)
    }
  }
}

private struct EditableTagRow: View {
  let title: LocalizedStringResource
  @Binding var text: String

  var body: some View {
    GridRow {
      Text(title)
        .foregroundStyle(.secondary)
      TextField(text: $text, prompt: Text("Unknown")) {
        Text(title)
      }
      .textFieldStyle(.roundedBorder)
      .frame(maxWidth: 520)
    }
  }
}

private struct SetlistTrackEditRow: View {
  @Binding var track: SetlistTrack

  var body: some View {
    TextField("Track title", text: $track.title)
      .textFieldStyle(.roundedBorder)
  }
}

// MARK: - Shell (M6 S1): fixed header + completion pill + pipeline strip + tab bar

/// The four activity tabs the scanned-show body scrolls between. The pipeline strip's
/// cards select these; the selection itself is view-local `@State`.
private enum ActivityTab: String, CaseIterable, Identifiable {
  case setlist = "Setlist"
  case plan = "Plan"
  case output = "Output"
  case history = "History"

  var id: Self { self }
}

private struct ShowHeader: View {
  let root: URL
  let openFolder: () -> Void
  let done: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 6) {
        Text(root.lastPathComponent)
          .font(.title2.weight(.semibold))
        Text(root.path(percentEncoded: false))
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .textSelection(.enabled)
      }
      Spacer(minLength: 24)
      Button(action: openFolder) {
        Label("Open Show Folder", systemImage: "folder")
      }
      Button(action: done) {
        Label("Done", systemImage: "checkmark.circle")
      }
      .help("Clear this show and return to the empty state.")
    }
  }
}

/// Terminal-state summary — only shown once every produced file resolves in the library.
private struct CompletionPill: View {
  let resolution: LibraryResolutionResult

  var body: some View {
    Label(
      "Imported · resolved \(resolution.resolvedCount)/\(resolution.trackResolutions.count)",
      systemImage: "checkmark.seal.fill"
    )
    .font(.callout.weight(.medium))
    .foregroundStyle(.green)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Capsule().fill(Color.green.opacity(0.12)))
  }
}

/// Four status cards rolling up the five run states; tapping a card selects its tab.
private struct PipelineStrip: View {
  let stage: AppModel.PipelineStage
  @Binding var selection: ActivityTab

  var body: some View {
    HStack(spacing: 10) {
      // Files is always reached here — we only render this strip for a scanned folder.
      card("Files", systemImage: "waveform", tab: .setlist, reached: true)
      card("Setlist", systemImage: "text.badge.checkmark", tab: .setlist, reached: stage >= .planned)
      card("Plan", systemImage: "list.bullet.rectangle", tab: .plan, reached: stage >= .verified)
      card("Music", systemImage: "music.note", tab: .output, reached: stage >= .resolved)
    }
  }

  private func card(
    _ title: LocalizedStringResource,
    systemImage: String,
    tab: ActivityTab,
    reached: Bool
  ) -> some View {
    Button {
      selection = tab
    } label: {
      HStack(spacing: 8) {
        Image(systemName: reached ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(reached ? .green : .secondary)
        Label(title, systemImage: systemImage)
          .labelStyle(.titleOnly)
          .font(.callout.weight(selection == tab ? .semibold : .regular))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(selection == tab ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(selection == tab ? Color.accentColor.opacity(0.5) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct ActivityTabBar: View {
  @Binding var selection: ActivityTab

  var body: some View {
    Picker("Activity", selection: $selection) {
      ForEach(ActivityTab.allCases) { tab in
        Text(tab.rawValue).tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }
}

/// S1 placeholder — the run-status views still live in the Plan tab this slice; S2
/// relocates them here (splitting the action bar from the `*RunStatus` calls).
private struct OutputTabPlaceholder: View {
  let stage: AppModel.PipelineStage

  var body: some View {
    let message: LocalizedStringResource = stage >= .applied
      ? "Run details currently live under the Plan tab. They move here in the next slice."
      : "Apply and convert a plan to produce run output."
    ContentUnavailableView {
      Label("Run Output", systemImage: "waveform.badge.magnifyingglass")
    } description: {
      Text(message)
    }
  }
}

private struct ScanErrorBanner: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle")
      .foregroundStyle(.red)
      .font(.callout)
  }
}

private struct ScanSection<Content: View>: View {
  let title: LocalizedStringResource
  let systemImage: String
  var count: Int?
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Label(title, systemImage: systemImage)
          .font(.headline)
        if let count {
          Text(count, format: .number)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottom) {
        Divider()
      }
    }
  }
}

private struct ScannedAudioFileRow: View {
  let file: ScannedAudioFile
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: "music.note")
        .foregroundStyle(.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(file.url.lastPathComponent)
          .lineLimit(1)
        Text(file.url.relativePath(from: root))
          .foregroundStyle(.secondary)
          .font(.caption)
          .lineLimit(1)
      }
      Spacer()
      Text(file.format.rawValue.uppercased())
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 8)
  }
}

private struct CandidateList: View {
  let urls: [URL]
  let root: URL

  var body: some View {
    if urls.isEmpty {
      EmptyScanSectionRow(title: "None detected")
    } else {
      LazyVStack(alignment: .leading, spacing: 0) {
        ForEach(urls, id: \.self) { url in
          CandidateRow(url: url, root: root)
        }
      }
    }
  }
}

private struct CandidateRow: View {
  let url: URL
  let root: URL

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: "doc")
        .foregroundStyle(.secondary)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 3) {
        Text(url.lastPathComponent)
        Text(url.relativePath(from: root))
          .foregroundStyle(.secondary)
          .font(.caption)
      }
    }
    .padding(.vertical, 8)
  }
}

private struct EmptyScanSectionRow: View {
  let title: LocalizedStringResource

  var body: some View {
    Text(title)
      .foregroundStyle(.secondary)
      .padding(.vertical, 8)
  }
}

private extension URL {
  func relativePath(from root: URL) -> String {
    let rootPath = root.standardizedFileURL.path(percentEncoded: false)
    let filePath = standardizedFileURL.path(percentEncoded: false)
    guard filePath.hasPrefix(rootPath) else {
      return lastPathComponent
    }
    let relativePath = filePath.dropFirst(rootPath.count)
    return String(relativePath.hasPrefix("/") ? relativePath.dropFirst() : relativePath)
  }
}

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
  }
  LiveShowsView(model: AppModel())
}
