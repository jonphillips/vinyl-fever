import AppKit
import SwiftUI
import VinylFeverCore

/// The Setlist Normalizer's preview gate: paste/load raw trading notes, normalize
/// through the sandwich, and review the proposed `setlist.txt` — its confidence, any
/// guardrail issues, and everything dropped — before an explicit Save writes the file.
/// No auto-write, even at high confidence.
struct SetlistNormalizerSheet: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label {
            Text(
              "AI turns messy raw trading notes into a structured setlist.txt. Nothing is saved until you review the preview and choose Save."
            )
          } icon: {
            Image(systemName: "wand.and.stars")
          }
          .font(.callout)
          .foregroundStyle(.secondary)

          if !model.isFrontierConfigured {
            frontierBanner
          }

          Text("Raw notes")
            .font(.headline)
          TextEditor(text: $model.setlistInput)
            .font(.body.monospaced())
            .frame(minHeight: 160)
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
            }

          HStack {
            Button {
              Task { await model.normalizeSetlistInput() }
            } label: {
              Label("Normalize", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
              model.setlistNormalizationState.isRunning
                || model.setlistInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            if model.setlistNormalizationState.isRunning {
              ProgressView().controlSize(.small)
            }
          }

          resultSection
        }
        .padding(20)
      }
      .navigationTitle("Normalize Setlist")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
      .task {
        model.loadFrontierKeyPreview()
      }
    }
    .frame(minWidth: 640, minHeight: 560)
  }

  @ViewBuilder
  private var resultSection: some View {
    switch model.setlistNormalizationState {
    case .idle, .running:
      EmptyView()
    case let .failed(message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    case let .saved(url):
      Label("Saved to \(url.path(percentEncoded: false))", systemImage: "checkmark.circle")
        .foregroundStyle(.green)
    case let .completed(result):
      NormalizationPreview(result: result, save: { save(result) })
    }
  }

  private var frontierBanner: some View {
    Label {
      Text(
        "No frontier key configured — normalization needs one. Add a Claude key in Settings."
      )
    } icon: {
      Image(systemName: "key")
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }

  private func save(_ result: SetlistNormalizationResult) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "setlist.txt"
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    Task { await model.writeNormalizedSetlist(result, to: url) }
  }
}

private struct NormalizationPreview: View {
  let result: SetlistNormalizationResult
  let save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()

      HStack(spacing: 8) {
        Image(systemName: result.isHighConfidence ? "checkmark.seal" : "exclamationmark.triangle")
          .foregroundStyle(result.isHighConfidence ? .green : .orange)
        Text(result.isHighConfidence ? "High confidence" : "Needs review")
          .font(.headline)
          .foregroundStyle(result.isHighConfidence ? .green : .orange)
      }

      if !result.issues.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
            Label(issue.displayMessage, systemImage: "exclamationmark.circle")
              .font(.callout)
              .foregroundStyle(.orange)
          }
        }
      }

      Text("Proposed setlist.txt")
        .font(.headline)
      Text(result.renderedText)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
          RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor))
        }

      if !result.allDropped.isEmpty {
        DisclosureGroup("Dropped (\(result.allDropped.count))") {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(result.allDropped.enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }

      Button(action: save) {
        Label("Save setlist.txt…", systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
