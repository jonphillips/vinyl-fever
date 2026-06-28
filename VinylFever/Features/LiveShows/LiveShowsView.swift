import AppKit
import Dependencies
import SQLiteData
import SwiftUI
import UniformTypeIdentifiers
import VinylFeverCore

struct LiveShowsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Group {
      if let scannedShowFolder = model.scannedShowFolder {
        ScannedShowFolderView(
          folder: scannedShowFolder,
          model: model,
          openFolder: openFolder,
          openSetlistFile: openSetlistFile
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
        Button(action: openFolder) {
          Label("Open Show Folder", systemImage: "folder")
        }
      }
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

    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ScanHeader(root: folder.root, openFolder: openFolder)
        if let errorMessage = model.scanErrorMessage {
          ScanErrorBanner(message: errorMessage)
        }
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
          openSetlistFile: openSetlistFile
        )
        SourceMetadataSection(
          sourceLabels: sourceLabels,
          selectedSourceLabelID: $model.selectedSourceLabelID,
          newSourceLabelToken: $model.newSourceLabelToken,
          errorMessage: model.sourceLabelErrorMessage,
          metadata: metadata,
          addSourceLabel: model.addSourceLabel,
          deleteSourceLabel: model.deleteSourceLabel
        )
        PlanPreviewSection(
          plan: showPlan,
          root: folder.root,
          coverURL: folder.coverCandidates.first,
          currentMetadataByFileID: model.currentMetadataByFileID,
          applyState: model.applyState,
          conversionState: model.conversionState,
          verificationState: model.verificationState,
          hasRequiredApplyTools: model.hasRequiredApplyTools(for: showPlan),
          hasRequiredConversionTools: { applyPlan in
            model.hasRequiredConversionTools(for: applyPlan)
          },
          hasSuccessfulApply: { applyPlan in
            model.hasSuccessfulApply(for: applyPlan)
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
        ScanSection(
          title: "Cover Art",
          systemImage: "photo",
          count: folder.coverCandidates.count
        ) {
          CandidateList(urls: folder.coverCandidates, root: folder.root)
        }
        if let errorMessage = model.runLogErrorMessage {
          ScanErrorBanner(message: errorMessage)
        }
        RunHistorySection()
      }
      .frame(maxWidth: 980, alignment: .leading)
      .padding(24)
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
}

private struct PlanPreviewSection: View {
  let plan: ShowPlan?
  let root: URL
  let coverURL: URL?
  let currentMetadataByFileID: [ScannedAudioFile.ID: AudioMetadataLoadState]
  let applyState: ApplyRunState
  let conversionState: ConversionRunState
  let verificationState: VerificationRunState
  let hasRequiredApplyTools: Bool
  let hasRequiredConversionTools: (ApplyPlan) -> Bool
  let hasSuccessfulApply: (ApplyPlan) -> Bool
  let apply: (ShowPlan) -> Void
  let convertAndVerify: (ApplyPlan) -> Void
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
        VStack(alignment: .leading, spacing: 16) {
          PlanReadinessSummary(
            plan: plan,
            applyPlan: applyPlan,
            root: root,
            applyState: applyState,
            conversionState: conversionState,
            verificationState: verificationState,
            hasRequiredApplyTools: hasRequiredApplyTools,
            hasRequiredConversionTools: hasRequiredConversionTools(applyPlan),
            hasSuccessfulApply: hasSuccessfulApply(applyPlan),
            apply: { apply(plan) },
            convertAndVerify: { convertAndVerify(applyPlan) },
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
  let hasRequiredApplyTools: Bool
  let hasRequiredConversionTools: Bool
  let hasSuccessfulApply: Bool
  let apply: () -> Void
  let convertAndVerify: () -> Void
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
      !verificationState.isRunning
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
    if !hasSuccessfulApply {
      return "Apply must finish successfully first."
    }
    if !hasRequiredConversionTools {
      return "Required conversion and verification tools are missing."
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
      Text(trackPlan.proposedTags.trackNumber, format: .number)
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
            proposed: String(trackPlan.proposedTags.trackNumber)
          )
          TrackMetadataComparisonRow(
            title: "Disc",
            current: currentMetadata.tags?.discNumber.map(String.init),
            proposed: String(trackPlan.proposedTags.discNumber)
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
  @Binding var newSourceLabelToken: String
  let errorMessage: String?
  let metadata: ShowMetadata?
  let addSourceLabel: () -> Void
  let deleteSourceLabel: (SourceLabel) -> Void

  var body: some View {
    ScanSection(
      title: "Source & Album Title",
      systemImage: "record.circle",
      count: sourceLabels.count
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

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          Text("Vocabulary")
            .font(.subheadline.weight(.semibold))
          HStack(spacing: 8) {
            TextField("Add source label", text: $newSourceLabelToken)
              .textFieldStyle(.roundedBorder)
              .frame(width: 220)
              .onSubmit(addSourceLabel)
            Button(action: addSourceLabel) {
              Label("Add", systemImage: "plus")
            }
            .disabled(newSourceLabelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          if let errorMessage {
            ScanErrorBanner(message: errorMessage)
          }
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(sourceLabels) { sourceLabel in
              SourceLabelRow(
                sourceLabel: sourceLabel,
                delete: { deleteSourceLabel(sourceLabel) }
              )
            }
          }
        }
      }
      .padding(.vertical, 8)
    }
  }
}

private struct SourceLabelRow: View {
  let sourceLabel: SourceLabel
  let delete: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(sourceLabel.token)
        .font(.callout.monospaced())
      if sourceLabel.isBuiltIn {
        Label("Built-in", systemImage: "lock")
          .labelStyle(.iconOnly)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(action: delete) {
        Label("Remove", systemImage: "trash")
      }
      .disabled(sourceLabel.isBuiltIn)
      .help(
        sourceLabel.isBuiltIn
          ? "Built-in source labels cannot be removed."
          : "Remove source label"
      )
    }
    .frame(maxWidth: 420)
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
          openSetlistFile: openSetlistFile
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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: $text)
        .font(.body.monospaced())
        .frame(minHeight: 150)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor))
        }
      HStack {
        Button(action: openSetlistFile) {
          Label("Load .txt", systemImage: "doc.badge.plus")
        }
        Button(action: parse) {
          Label("Parse Setlist", systemImage: "text.magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
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

private struct ScanHeader: View {
  let root: URL
  let openFolder: () -> Void

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
  let count: Int
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Label(title, systemImage: systemImage)
          .font(.headline)
        Text(count, format: .number)
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
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
