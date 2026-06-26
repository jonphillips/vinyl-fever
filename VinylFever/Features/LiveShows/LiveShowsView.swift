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

private struct ScannedShowFolderView: View {
  let folder: ScannedShowFolder
  @Bindable var model: AppModel
  let openFolder: () -> Void
  let openSetlistFile: () -> Void

  @FetchAll(SourceLabel.order(by: \.token))
  private var persistedSourceLabels: [SourceLabel]

  var body: some View {
    let sourceLabels = SourceLabel.deduplicated(persistedSourceLabels)
    let selectedSourceLabel = sourceLabels.first { $0.id == model.selectedSourceLabelID }

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
          metadata: model.setlistDraft.map {
            ShowMetadata(tags: $0.tags, source: selectedSourceLabel)
          },
          addSourceLabel: model.addSourceLabel,
          deleteSourceLabel: model.deleteSourceLabel
        )
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
