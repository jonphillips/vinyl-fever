import Dependencies
import SQLiteData
import SwiftUI
import VinylFeverCore

struct SettingsView: View {
  @Bindable var model: AppModel

  @FetchAll(AppSetting.all)
  private var persistedSettings: [AppSetting]

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
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
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

#Preview {
  let _ = prepareDependencies {
    try! $0.bootstrapDatabase()
    $0.toolPathClient = .liveValue
  }
  SettingsView(model: AppModel())
}
