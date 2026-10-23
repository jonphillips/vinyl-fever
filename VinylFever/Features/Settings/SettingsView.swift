import AppKit
import Dependencies
import Observation
import SQLiteData
import ServiceManagement
import SwiftUI
import VinylFeverCore
import VinylFeverListening

struct SettingsView: View {
  @Bindable var model: AppModel

  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]
  @FetchAll(SourceLabel.order(by: \.token))
  private var persistedSourceLabels: [SourceLabel]
  @State private var didCopyPlaylistInstructions = false
  @State private var copiedMCPConfig: String?
  @State private var librarySnapshotStatus = "Checking…"
  @State private var listeningModel = ListeningPollingSettingsModel()
  @State private var isShowingArtistAliases = false
  @Dependency(\.librarySnapshotStore) private var librarySnapshotStore
  @Dependency(\.listeningStore) private var listeningStore

  private var settings: AppSetting {
    AppSetting.current(from: persistedSettings)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Audio Tools") {
          ForEach(AudioTool.allCases) { tool in
            ToolStatusRow(
              status: model.toolStatus(for: tool),
              overridePath: settings.toolPathOverrides.path(for: tool) ?? "",
              saveOverride: { path in
                model.saveToolOverride(path, for: tool, settings: settings)
              },
              clearOverride: {
                model.saveToolOverride(nil, for: tool, settings: settings)
              }
            )
          }
        }

        if let errorMessage = model.toolStatusErrorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }

        Section {
          MusicWatchFolderRow(
            folderPath: settings.musicWatchFolderPath ?? "",
            errorMessage: model.musicWatchFolderErrorMessage,
            save: { path in model.saveMusicWatchFolder(path, settings: settings) }
          )
        } header: {
          Text("Apple Music Import")
        } footer: {
          Text(
            "Vinyl Fever imports by copying files into Music's “Automatically Add” folder "
              + "instead of scripting Music directly, which avoids the “Music did not respond "
              + "in time” errors. Point this at "
              + "…/Media.localized/Automatically Add to Music.localized inside your Music library "
              + "(on its external drive)."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        Section {
          Text(listeningModel.statusLine)
          if listeningModel.canPollNow {
            Button("Poll now") { Task { await listeningModel.pollNow() } }
              .disabled(listeningModel.isPollingNow)
          }
          Toggle("Poll listening on this Mac", isOn: Binding(
            get: { listeningModel.pollingEnabled },
            set: { enabled in
              Task {
                if enabled { await listeningModel.enablePolling() }
                else { await listeningModel.disablePolling() }
              }
            }
          ))
          LabeledContent("Poller", value: listeningModel.leaseLabel)
          if let idleMessage = listeningModel.idleAgentMessage {
            Text(idleMessage).foregroundStyle(.secondary)
          }
          if listeningModel.requiresApproval {
            Text("Approve Vinyl Fever in Login Items to let it poll in the background.")
              .foregroundStyle(.secondary)
            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
          }
          if let error = listeningModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
          LabeledContent("iCloud folder", value: listeningStore.listeningFolder().path(percentEncoded: false))
            .textSelection(.enabled)
          Link("Listening history setup", destination: URL(string: "https://github.com/jonphillips/vinyl-fever/blob/main/docs/listening/POLLER-SETUP.md")!)
        } header: {
          Text("Listening History")
        } footer: {
          Text("Listening history begins when polling is set up. A play means a song started; skips and brief autoplay count.")
        }

        Section("Frontier Model") {
          FrontierKeyRow(
            keyPreview: model.frontierKeyPreview,
            save: { model.saveFrontierKey($0) },
            clear: { model.clearFrontierKey() }
          )
          if let errorMessage = model.frontierKeyErrorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
          }
        }

        Section {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(PlaylistContract.projectInstructions, forType: .string)
            didCopyPlaylistInstructions = true
          } label: {
            Label(
              didCopyPlaylistInstructions ? "Instructions Copied" : "Copy ChatGPT Project Instructions",
              systemImage: didCopyPlaylistInstructions ? "checkmark" : "doc.on.doc"
            )
          }
          Text("Paste these instructions into the Vinyl Fever Chat Project so playlist replies use the format Vinyl Fever can review.")
            .font(.callout)
            .foregroundStyle(.secondary)
        } header: {
          Text("Playlist Builder")
        }

        Section {
          LabeledContent("Helper path", value: helperPath)
            .textSelection(.enabled)
          LabeledContent("Library snapshot", value: snapshotPath)
            .textSelection(.enabled)
          LabeledContent("Database", value: databasePath)
            .textSelection(.enabled)
          LabeledContent("Snapshot status", value: librarySnapshotStatus)
          copyButton("Claude Code .mcp.json", key: "claude", value: claudeConfig)
          copyButton("Codex config.toml", key: "codex", value: codexConfig)
          copyButton("tunnel-client init command", key: "tunnel", value: tunnelCommand)
          Text("Use the plugin name Vinyl Fever. The tunnel command needs the tunnel ID from the Platform Tunnels page.")
            .font(.callout).foregroundStyle(.secondary)
          Text("Tools: library_overview, top_artists, top_tracks, search_library, artist_profile, check_tracks, recent_listening, stage_playlist")
            .font(.callout).foregroundStyle(.secondary)
        } header: {
          Text("Chat Access (MCP)")
        } footer: {
          Text("The helper reads the last library snapshot Vinyl Fever built. Chat can stage a playlist for review, but only Create in Vinyl Fever changes Apple Music.")
        }

        artistAliasesSection

        Section("Source Labels") {
          SourceLabelEditor(
            sourceLabels: SourceLabel.deduplicated(persistedSourceLabels),
            newSourceLabelToken: $model.newSourceLabelToken,
            errorMessage: model.sourceLabelErrorMessage,
            addSourceLabel: model.addSourceLabel,
            deleteSourceLabel: model.deleteSourceLabel
          )
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
      .task {
        model.loadFrontierKeyPreview()
        await refreshLibrarySnapshotStatus()
        await listeningModel.refresh()
      }
      .toolbar {
        ToolbarItem {
          Button {
            Task { await refreshButtonTapped() }
          } label: {
            Label("Re-probe", systemImage: "arrow.clockwise")
          }
        }
      }
    }
    .alert("Make this Mac the poller?", isPresented: $listeningModel.isConfirmingTakeover) {
      Button("Make This Mac the Poller") { Task { await listeningModel.confirmTakeover() } }
      Button("Cancel", role: .cancel) { listeningModel.cancelTakeover() }
    } message: {
      Text(listeningModel.takeoverMessage)
    }
    .frame(minWidth: 620, minHeight: 420)
    .sheet(isPresented: $isShowingArtistAliases) { ArtistAliasesView() }
    .task(id: settings) {
      await model.refreshToolStatuses(settings: settings)
    }
  }

  private func refreshButtonTapped() async {
    await model.refreshToolStatuses(settings: settings)
  }

  private var artistAliasesSection: some View {
    Section("Library") {
      Button("Artist Aliases…") { isShowingArtistAliases = true }
    }
  }

  private func refreshLibrarySnapshotStatus() async {
    do {
      guard let snapshot = try await librarySnapshotStore.read() else {
        librarySnapshotStatus = "Not built yet"
        return
      }
      let modifiedAt = try await librarySnapshotStore.modifiedAt() ?? snapshot.generatedAt
      librarySnapshotStatus = "\(snapshot.trackCount.formatted()) tracks · \(modifiedAt.formatted(.relative(presentation: .numeric)))"
    } catch {
      librarySnapshotStatus = "Unavailable · \(error.localizedDescription)"
    }
  }

  private var helperPath: String {
    Bundle.main.bundleURL.appending(path: "Contents/Helpers/vf-mcp").path(percentEncoded: false)
  }

  private var snapshotPath: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/VinylFever/LibrarySnapshot/library-snapshot.json")
      .path(percentEncoded: false)
  }

  private var databasePath: String {
    VinylFeverDatabase.liveDatabaseURL.path(percentEncoded: false)
  }

  private var claudeConfig: String {
    "{\n  \"mcpServers\": {\n    \"vinyl-fever\": {\n      \"command\": \"\(helperPath)\"\n    }\n  }\n}"
  }

  private var codexConfig: String {
    "[mcp_servers.vinyl-fever]\ncommand = \"\(helperPath)\"\nargs = []"
  }

  private var tunnelCommand: String {
    "mcp-tunnel init vinyl-fever <tunnel_id> \"\(helperPath)\""
  }

  private func copyButton(_ title: String, key: String, value: String) -> some View {
    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
      copiedMCPConfig = key
    } label: {
      Label(copiedMCPConfig == key ? "Copied \(title)" : "Copy \(title)", systemImage: copiedMCPConfig == key ? "checkmark" : "doc.on.doc")
    }
  }
}

struct ListeningAgentClient {
  var isEnabled: @Sendable () -> Bool
  var requiresApproval: @Sendable () -> Bool
  var register: @Sendable () throws -> Void
  var unregister: @Sendable () async throws -> Void
  var kickstart: @Sendable () throws -> Void

  static var liveValue: Self {
    return Self(
      isEnabled: { SMAppService.agent(plistName: "VinylFeverListeningAgent.plist").status == .enabled },
      requiresApproval: { SMAppService.agent(plistName: "VinylFeverListeningAgent.plist").status == .requiresApproval },
      register: { try SMAppService.agent(plistName: "VinylFeverListeningAgent.plist").register() },
      unregister: { try await SMAppService.agent(plistName: "VinylFeverListeningAgent.plist").unregister() },
      kickstart: {
        try ListeningLaunchAgentKickstarter.kickstart(label: "com.jonphillips.vinylfever.listening.agent")
      }
    )
  }
}

extension ListeningAgentClient: TestDependencyKey, DependencyKey {
  static var testValue: Self {
    Self(
      isEnabled: { fatalError("Override listeningAgentClient in tests before reading its status.") },
      requiresApproval: { fatalError("Override listeningAgentClient in tests before reading its status.") },
      register: { fatalError("Override listeningAgentClient in tests before registering the agent.") },
      unregister: { fatalError("Override listeningAgentClient in tests before unregistering the agent.") },
      kickstart: { fatalError("Override listeningAgentClient in tests before starting the agent.") }
    )
  }
}

extension DependencyValues {
  var listeningAgentClient: ListeningAgentClient {
    get { self[ListeningAgentClient.self] }
    set { self[ListeningAgentClient.self] = newValue }
  }
}

@MainActor
@Observable
final class ListeningPollingSettingsModel {
  @ObservationIgnored @Dependency(\.listeningStore) private var store
  @ObservationIgnored @Dependency(\.listeningAgentClient) private var agent
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @Dependency(\.continuousClock) private var clock
  private var pendingTakeoverPoller: UUID?
  private var leaseHost: String?

  private(set) var statusLine = ListeningStatusLine.setupPointer
  private(set) var holdsLease = false
  private(set) var leaseExists = false
  private(set) var errorMessage: String?
  var isConfirmingTakeover = false

  init() {}

  var hasRegisteredAgent: Bool { agent.isEnabled() || agent.requiresApproval() }
  var pollingEnabled: Bool { hasRegisteredAgent && !isAnotherMacPolling }
  var requiresApproval: Bool { agent.requiresApproval() }
  private var isAnotherMacPolling: Bool { leaseExists && !holdsLease }
  var canPollNow: Bool { holdsLease && agent.isEnabled() }
  private(set) var isPollingNow = false

  var takeoverMessage: String {
    "\(leaseHost ?? "Another Mac") is polling now. Make this Mac the poller?"
  }

  var idleAgentMessage: String? {
    guard hasRegisteredAgent, isAnotherMacPolling else { return nil }
    return "\(leaseHost ?? "Another Mac") is polling. This Mac's agent is idle until you turn polling back on here."
  }

  var leaseLabel: String {
    if holdsLease { "This Mac holds the lease" }
    else if let leaseHost { "\(leaseHost) holds the lease" }
    else if leaseExists { "Another Mac holds the lease" }
    else { "No lease yet" }
  }

  func refresh() async {
    do {
      let poller = try store.pollerID()
      let lease = try store.readLease()
      leaseExists = lease != nil
      holdsLease = lease?.poller == poller
      leaseHost = lease?.host
      let fetches = try store.readFetches()
      statusLine = ListeningStatusLine.make(fetches: fetches, now: date())
      errorMessage = try store.readLastPollError()
        ?? (fetches.last?.outcome == .failed ? fetches.last?.error : nil)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func enablePolling() async {
    do {
      let poller = try store.pollerID()
      let lease = try store.readLease()
      if let lease, lease.poller != poller {
        pendingTakeoverPoller = poller
        leaseHost = lease.host
        isConfirmingTakeover = true
        return
      }
      try await activate()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func confirmTakeover() async {
    guard let poller = pendingTakeoverPoller else { return }
    do {
      try ListeningTakeover.perform(
        store: store, poller: poller, host: store.hostName(), now: date(),
        isAgentEnabled: { agent.isEnabled() || agent.requiresApproval() },
        register: { try agent.register() },
        kickstart: { try agent.kickstart() })
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    pendingTakeoverPoller = nil
    isConfirmingTakeover = false
    await refresh()
  }

  func cancelTakeover() {
    pendingTakeoverPoller = nil
    isConfirmingTakeover = false
  }

  func disablePolling() async {
    do {
      try await agent.unregister()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    await refresh()
  }

  func pollNow() async {
    guard canPollNow, !isPollingNow else { return }
    isPollingNow = true
    defer { isPollingNow = false }
    do {
      let previousFetchAt = try store.readFetches().last?.fetchedAt
      try agent.kickstart()
      for attempt in 0...30 {
        try Task.checkCancellation()
        let newestFetchAt = try store.readFetches().last?.fetchedAt
        if let newestFetchAt, newestFetchAt != previousFetchAt { break }
        if attempt < 30 { try await clock.sleep(for: .seconds(1)) }
      }
      await refresh()
    } catch is CancellationError {
      await refresh()
    } catch {
      await refresh()
      errorMessage = error.localizedDescription
    }
  }

  private func activate() async throws {
    try registerAgentIfNeeded()
    errorMessage = nil
    await refresh()
  }

  private func registerAgentIfNeeded() throws {
    if !agent.isEnabled() { try agent.register() }
  }
}

private struct ToolStatusRow: View {
  let status: ToolStatus
  let overridePath: String
  let saveOverride: (String?) -> Void
  let clearOverride: () -> Void

  @State private var draftOverridePath: String

  init(
    status: ToolStatus,
    overridePath: String,
    saveOverride: @escaping (String?) -> Void,
    clearOverride: @escaping () -> Void
  ) {
    self.status = status
    self.overridePath = overridePath
    self.saveOverride = saveOverride
    self.clearOverride = clearOverride
    _draftOverridePath = State(initialValue: overridePath)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Label(status.tool.displayName, systemImage: status.isAvailable ? "checkmark.circle" : "xmark.circle")
          .foregroundStyle(statusColor)
          .font(.headline)
        Text(status.source.displayName)
          .foregroundStyle(.secondary)
        Spacer()
        Text(status.version ?? "No version")
          .foregroundStyle(status.version == nil ? .secondary : .primary)
          .textSelection(.enabled)
      }

      if let resolvedPath = status.resolvedPath {
        LabeledContent("Path") {
          Text(resolvedPath)
            .font(.callout.monospaced())
            .textSelection(.enabled)
        }
      } else if let errorMessage = status.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      }

      LabeledContent("Override") {
        HStack(spacing: 8) {
          TextField("Executable path", text: $draftOverridePath)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
          Button {
            saveOverride(draftOverridePath)
          } label: {
            Label("Save", systemImage: "checkmark")
          }
          .disabled(!hasDraftChange)
          Button {
            draftOverridePath = ""
            clearOverride()
          } label: {
            Label("Clear", systemImage: "xmark")
          }
          .disabled(overridePath.isEmpty && draftOverridePath.isEmpty)
        }
      }
    }
    .padding(.vertical, 8)
    .onChange(of: overridePath) { _, newValue in
      draftOverridePath = newValue
    }
  }

  private var statusColor: Color {
    if !status.isAvailable {
      return .red
    }
    if status.errorMessage != nil {
      return .orange
    }
    return .green
  }

  private var hasDraftChange: Bool {
    draftOverridePath.trimmingCharacters(in: .whitespacesAndNewlines)
      != overridePath.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Pick or clear Music's "Automatically Add" folder — the drop target the importer copies
/// files into. A folder picker (rather than a text field) so the path is real and the app
/// records access to the external volume by touching it.
private struct MusicWatchFolderRow: View {
  let folderPath: String
  let errorMessage: String?
  let save: (String?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if folderPath.isEmpty {
        Label("No folder configured — imports are disabled.", systemImage: "folder.badge.questionmark")
          .foregroundStyle(.secondary)
      } else {
        LabeledContent("Folder") {
          Text(folderPath)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
        }
      }

      HStack(spacing: 8) {
        Button {
          if let chosen = chooseFolder() {
            save(chosen)
          }
        } label: {
          Label("Choose…", systemImage: "folder")
        }
        Button {
          save(nil)
        } label: {
          Label("Clear", systemImage: "xmark")
        }
        .disabled(folderPath.isEmpty)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .font(.callout)
      }
    }
    .padding(.vertical, 6)
  }

  private func chooseFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Select Music's “Automatically Add” folder."
    if !folderPath.isEmpty {
      panel.directoryURL = URL(filePath: folderPath)
    }
    guard panel.runModal() == .OK, let url = panel.url else {
      return nil
    }
    return url.path(percentEncoded: false)
  }
}

/// Enter/clear the Claude API key used by the Setlist Normalizer. The key is stored
/// in the shared iCloud-Keychain `APIKeyStore`, so a key entered in another
/// jon-platform app (Galavant, Yes Chef) is already visible here — this row only
/// needs to exist for entering it inside Vinyl Fever. The secret is never shown back;
/// only a masked preview confirms a key is set.
private struct FrontierKeyRow: View {
  let keyPreview: String?
  let save: (String) -> Void
  let clear: () -> Void

  @State private var draftKey = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let keyPreview {
        LabeledContent("Claude key") {
          Text(keyPreview)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
        }
      } else {
        Label("No Claude key configured.", systemImage: "key.slash")
          .foregroundStyle(.secondary)
      }

      LabeledContent("Set key") {
        HStack(spacing: 8) {
          SecureField("sk-ant-…", text: $draftKey)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
          Button {
            save(draftKey)
            draftKey = ""
          } label: {
            Label("Save", systemImage: "checkmark")
          }
          .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button {
            draftKey = ""
            clear()
          } label: {
            Label("Clear", systemImage: "xmark")
          }
          .disabled(keyPreview == nil)
        }
      }
    }
    .padding(.vertical, 6)
  }
}

/// The source-label vocabulary (SBD, FM, Matrix, …). App-global reference data —
/// mostly locked built-ins, identical for every show — so it lives in Settings, not
/// inline on a single show. The per-show Source *picker* stays on the live-show screen.
private struct SourceLabelEditor: View {
  let sourceLabels: [SourceLabel]
  @Binding var newSourceLabelToken: String
  let errorMessage: String?
  let addSourceLabel: () -> Void
  let deleteSourceLabel: (SourceLabel) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
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
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
          .font(.callout)
      }
      ForEach(sourceLabels) { sourceLabel in
        SourceLabelRow(
          sourceLabel: sourceLabel,
          delete: { deleteSourceLabel(sourceLabel) }
        )
      }
    }
    .padding(.vertical, 6)
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

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    $0.toolPathClient = .liveValue
  }
  SettingsView(model: AppModel())
}
