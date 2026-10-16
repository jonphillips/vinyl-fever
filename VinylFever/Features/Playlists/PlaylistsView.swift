import SwiftUI
import VinylFeverCore

struct PlaylistsView: View {
  @Bindable var model: PlaylistBuilderModel
  @State private var confirmsPartialCreate = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Playlists")
            .font(.largeTitle.bold())
          Text(
            "Paste a playlist from Vinyl Fever Chat, review the catalog matches, then create it in Music."
          )
          .foregroundStyle(.secondary)
        }
        Spacer()
        if model.hasResolvedPaste || !model.rows.isEmpty {
          Button("Start Over", systemImage: "arrow.counterclockwise") { model.startOver() }
            .disabled(model.isCreating || model.isAppending)
        }
      }

      if !model.hasResolvedPaste && model.createdPlaylist == nil {
        pastePanel
      }

      snapshotStatus

      if let gate = model.gate {
        Label(gate.message, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      }
      if let decodeError = model.decodeError {
        Label(decodeError, systemImage: "xmark.octagon.fill")
          .foregroundStyle(.red)
      }
      if let error = model.operationError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }

      if model.hasResolvedPaste || model.createdPlaylist != nil {
        reviewPanel
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(minWidth: 760, minHeight: 560)
    .confirmationDialog(
      "Create playlist with unresolved songs?",
      isPresented: $confirmsPartialCreate,
      titleVisibility: .visible
    ) {
      Button("Create with \(model.matchedCount) of \(model.consideredTrackCount) Songs") {
        Task { await model.createPlaylist() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "\(model.unresolvedCount) unresolved song\(model.unresolvedCount == 1 ? " will" : "s will") be skipped. You can fix and add them after creation."
      )
    }
  }

  private var pastePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Playlist reply")
          .font(.headline)
        Spacer()
        PasteButton(payloadType: String.self) { pasted in
          model.pastedText = pasted.first ?? ""
        }
      }
      TextEditor(text: $model.pastedText)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 170)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
      HStack {
        Text("Use the VF-PLAYLIST block from the Vinyl Fever Chat Project.")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          Task { await model.resolve() }
        } label: {
          if model.isResolving {
            ProgressView().controlSize(.small)
          } else {
            Label("Resolve Songs", systemImage: "magnifyingglass")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          model.isResolving
            || model.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(16)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }

  private var reviewPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let created = model.createdPlaylist {
        Label(
          "Created “\(created.name)” with \(created.trackCount) songs. It will appear in Music after iCloud sync.",
          systemImage: "checkmark.circle.fill"
        )
        .foregroundStyle(.green)
      } else {
        TextField("Playlist name", text: $model.playlistName)
          .font(.title2.weight(.semibold))
        TextField("Description (optional)", text: $model.playlistDescription)
      }

      if model.markerWarning != nil {
        Text(
          "This playlist used an older contract. For the latest instructions, open Settings and copy them again."
        )
        .font(.callout)
        .foregroundStyle(.orange)
      }

      if !model.droppedTracks.isEmpty {
        DisclosureGroup("Tracks omitted from the reply (\(model.droppedTracks.count))") {
          ForEach(model.droppedTracks, id: \.index) { track in
            Text("#\(track.index): \(track.artist) — \(track.title)")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(model.visibleRows) { row in
            PlaylistRowView(
              row: row,
              annotation: model.annotation(for: row.request, candidate: matchedCandidate(in: row)),
              searchTerm: Binding(
                get: { model.searchTerms[row.request.index] ?? "" },
                set: { model.searchTerms[row.request.index] = $0 }
              ),
              canAddToCreatedPlaylist: model.canAddToCreatedPlaylist(trackIndex: row.request.index),
              canChangeMatch: model.canReopenMatch(trackIndex: row.request.index),
              isPostCreate: model.createdPlaylist != nil,
              addToPlaylist: {
                Task { await model.addToCreatedPlaylist(trackIndex: row.request.index) }
              },
              reSearch: { Task { await model.reSearch(trackIndex: row.request.index) } },
              selectCandidate: { model.selectCandidate($0, for: row.request.index) },
              changeMatch: { model.reopen(trackIndex: row.request.index) },
              remove: { model.remove(trackIndex: row.request.index) }
            )
          }
        }
      }
      .frame(maxHeight: .infinity)

      HStack {
        Text("\(model.matchedCount) matched · \(model.unresolvedCount) unresolved")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        if model.heavilyPlayedCount > 0 {
          Button(
            "Remove \(model.heavilyPlayedCount) tracks played ≥ 20 times",
            systemImage: "minus.circle"
          ) {
            model.removeHeavilyPlayedRows()
          }
          .disabled(model.isCreating)
        }
        if model.failedSearchCount > 0 || model.isRetryingSearches {
          Button {
            Task { await model.retryFailedSearches() }
          } label: {
            if model.isRetryingSearches {
              ProgressView().controlSize(.small)
            } else {
              Label(
                "Retry Failed Searches (\(model.failedSearchCount))", systemImage: "arrow.clockwise"
              )
            }
          }
          .disabled(model.isRetryingSearches || model.isCreating)
        }
        if model.createdPlaylist == nil {
          Button {
            if model.unresolvedCount > 0 {
              confirmsPartialCreate = true
            } else {
              Task { await model.createPlaylist() }
            }
          } label: {
            if model.isCreating {
              ProgressView().controlSize(.small)
            } else {
              Label("Create in Music", systemImage: "plus")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!model.canCreate)
        }
      }
    }
    .padding(16)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
  }

  private var snapshotStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if let snapshot = model.librarySnapshot {
          Text(
            "Library snapshot: \(snapshot.trackCount.formatted()) tracks · \(snapshot.generatedAt.formatted(.relative(presentation: .numeric)))"
          )
          .font(.callout).foregroundStyle(.secondary)
        } else if model.isRefreshingSnapshot {
          ProgressView("Building library snapshot…").controlSize(.small)
        } else {
          Text("Library snapshot unavailable").font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Refresh Library Snapshot", systemImage: "arrow.clockwise") {
          Task { await model.refreshLibrarySnapshot() }
        }
        .disabled(model.isRefreshingSnapshot)
      }
      if let error = model.librarySnapshotError {
        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(
          .orange)
      }
    }
  }

  private func matchedCandidate(in row: ResolvedPlaylistRow) -> CatalogSongCandidate? {
    if case .matched(let candidate, _) = row.status { return candidate }
    return nil
  }
}

private struct PlaylistRowView: View {
  let row: ResolvedPlaylistRow
  let annotation: LibraryAnnotation
  @Binding var searchTerm: String
  let canAddToCreatedPlaylist: Bool
  let canChangeMatch: Bool
  let isPostCreate: Bool
  let addToPlaylist: () -> Void
  let reSearch: () -> Void
  let selectCandidate: (CatalogSongCandidate) -> Void
  let changeMatch: () -> Void
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Text(String(format: "%02d", row.request.index))
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 30, alignment: .trailing)
        VStack(alignment: .leading, spacing: 3) {
          Text(row.request.title).font(.headline)
          Text(row.request.artist).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Remove", systemImage: "xmark.circle") { remove() }
          .labelStyle(.iconOnly)
          .help(
            isPostCreate ? "Dismiss this leftover song" : "Remove this song from the playlist draft"
          )
      }
      HStack(alignment: .center) {
        statusContent
        Spacer()
        if canChangeMatch {
          Button("Change") { changeMatch() }
            .buttonStyle(.borderless)
        }
        if canAddToCreatedPlaylist {
          Button("Add to Playlist", systemImage: "plus") { addToPlaylist() }
            .buttonStyle(.bordered)
        }
      }
      .padding(.leading, 40)
      annotationContent.padding(.leading, 40)
    }
    .padding(12)
    .background(.background, in: RoundedRectangle(cornerRadius: 9))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
  }

  @ViewBuilder
  private var annotationContent: some View {
    switch annotation {
    case .inLibrary(let plays, let lastPlayed, let favorited, _):
      HStack(spacing: 6) {
        Text("In library · \(plays) plays")
        if let lastPlayed {
          Text("· last \(lastPlayed.formatted(.dateTime.month(.abbreviated).year()))")
        }
        if favorited { Text("· ♥") }
      }
      .font(.caption).foregroundStyle(.secondary)
    case .notInLibrary:
      Label("New to you", systemImage: "sparkle").font(.caption).foregroundStyle(.secondary)
    case .snapshotUnavailable:
      EmptyView()
    }
  }

  @ViewBuilder
  private var statusContent: some View {
    switch row.status {
    case .matched(let candidate, _):
      Label("\(candidate.title) — \(candidate.artistName)", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .lineLimit(1)
    case .ambiguous(let candidates):
      HStack {
        Label("Choose a match", systemImage: "questionmark.circle")
          .foregroundStyle(.orange)
        Picker("Catalog match", selection: candidateSelection(candidates)) {
          Text("Select a song…").tag("")
          ForEach(candidates, id: \.candidate.id) { scored in
            Text(candidateLabel(scored.candidate)).tag(scored.candidate.id)
          }
        }
        .frame(maxWidth: 390)
      }
    case .notFound(let error):
      HStack {
        TextField("Search term", text: $searchTerm)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 350)
        Button("Search", systemImage: "magnifyingglass") { reSearch() }
        if let error {
          Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
        } else {
          Label("No confident match", systemImage: "minus.circle")
            .foregroundStyle(.secondary)
        }
      }
    case .duplicate(_, let index):
      Label("Same catalog song as track #\(index); this row is skipped.", systemImage: "doc.on.doc")
        .foregroundStyle(.secondary)
    }
  }

  private func candidateSelection(_ candidates: [ScoredCandidate]) -> Binding<String> {
    Binding(
      get: {
        if case .matched(let candidate, _) = row.status { candidate.id } else { "" }
      },
      set: { id in
        if let selected = candidates.first(where: { $0.candidate.id == id }) {
          selectCandidate(selected.candidate)
        }
      }
    )
  }

  private func candidateLabel(_ candidate: CatalogSongCandidate) -> String {
    let albumYear = [
      candidate.albumTitle,
      candidate.releaseDate.map { String(Calendar.current.component(.year, from: $0)) },
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
    return [candidate.title, candidate.artistName, albumYear].filter { !$0.isEmpty }.joined(
      separator: " — ")
  }
}
