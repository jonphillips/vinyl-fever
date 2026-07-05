import Dependencies
import SQLiteData
import SwiftUI
import VinylFeverCore

struct SettingsView: View {
  @Bindable var model: AppModel

  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]
  @FetchAll(SourceLabel.order(by: \.token))
  private var persistedSourceLabels: [SourceLabel]

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
    .frame(minWidth: 620, minHeight: 420)
    .task(id: settings) {
      await model.refreshToolStatuses(settings: settings)
    }
  }

  private func refreshButtonTapped() async {
    await model.refreshToolStatuses(settings: settings)
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
