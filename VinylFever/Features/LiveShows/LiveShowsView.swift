import AppKit
import SwiftUI
import VinylFeverCore

struct LiveShowsView: View {
  @Bindable var model: AppModel

  var body: some View {
    Group {
      if let scannedShowFolder = model.scannedShowFolder {
        ScannedShowFolderView(
          folder: scannedShowFolder,
          errorMessage: model.scanErrorMessage,
          openFolder: openFolder
        )
      } else {
        ContentUnavailableView {
          Label("Live Shows", systemImage: "music.note.list")
        } description: {
          if let scanErrorMessage = model.scanErrorMessage {
            Text(scanErrorMessage)
          }
        } actions: {
          Button(action: openFolder) {
            Label("Open Show Folder", systemImage: "folder")
          }
          .buttonStyle(.borderedProminent)
        }
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
}

private struct ScannedShowFolderView: View {
  let folder: ScannedShowFolder
  let errorMessage: String?
  let openFolder: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ScanHeader(root: folder.root, openFolder: openFolder)
        if let errorMessage {
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
        ScanSection(
          title: "Cover Art",
          systemImage: "photo",
          count: folder.coverCandidates.count
        ) {
          CandidateList(urls: folder.coverCandidates, root: folder.root)
        }
      }
      .frame(maxWidth: 980, alignment: .leading)
      .padding(24)
    }
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
  LiveShowsView(model: AppModel())
}
