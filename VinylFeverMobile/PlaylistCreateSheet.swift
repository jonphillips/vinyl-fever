import SwiftUI
import VinylFeverAppleMusic

struct PlaylistCreateSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: PlaylistCreateModel

  private var title: String { model.playlist?.batch.playlist ?? "Create in Music" }

  var body: some View {
    NavigationStack {
      Group {
        if model.isResolving {
          ProgressView("Finding songs…")
        } else {
          List {
            Section { Text(title).font(.headline) }
            if let description = model.playlist?.batch.description, !description.isEmpty {
              Section { Text(description).foregroundStyle(.secondary) }
            }
            Section {
              ForEach(model.rows) { row in
                rowView(row)
              }
            }
            if model.unresolvedChoiceCount > 0 {
              Section {
                Text("Choose or skip \(model.unresolvedChoiceCount) songs")
                  .foregroundStyle(.secondary)
              }
            }
            if let errorMessage = model.errorMessage {
              Section { Text(errorMessage).foregroundStyle(.red) }
            }
          }
        }
      }
      .navigationTitle("Create in Music")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { model.cancel(); dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(model.createButtonTitle) { Task { await model.create() } }
            .disabled(!model.canCreate)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !model.isResolving {
          Button(model.createButtonTitle) { Task { await model.create() } }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.bar)
            .disabled(!model.canCreate)
        }
      }
    }
  }

  @ViewBuilder
  private func rowView(_ row: PlaylistCreateRow) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        if let candidate = row.resolvedCandidate {
          artwork(candidate)
        } else {
          Image(systemName: "music.note")
            .frame(width: 44, height: 44)
            .background(.quaternary, in: .rect(cornerRadius: 5))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(row.resolvedCandidate?.title ?? row.request.title).font(.headline)
          Text(row.resolvedCandidate?.artistName ?? row.request.artist).foregroundStyle(.secondary)
          if let candidate = row.resolvedCandidate, let album = candidate.albumTitle {
            Text(album).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }

      switch row.status {
      case .matched:
        if let duplicate = model.duplicateOf(row) {
          Text("Same as #\(duplicate + 1)").font(.caption).foregroundStyle(.secondary)
        }
      case .ambiguous(let candidates):
        if row.isSkipped {
          Label("Skipped", systemImage: "forward.end").font(.caption).foregroundStyle(.secondary)
        } else if let choice = row.choice {
          Text("Chosen: \(choice.title) · \(choice.artistName)").font(.caption).foregroundStyle(.secondary)
        } else {
          Text("Choose a match or skip").font(.caption).foregroundStyle(.secondary)
          ForEach(Array(candidates.enumerated()), id: \.offset) { _, scored in
            Button {
              model.choose(scored.candidate, for: row.id)
            } label: {
              HStack {
                artwork(scored.candidate)
                VStack(alignment: .leading) {
                  Text(scored.candidate.title)
                  Text([scored.candidate.artistName, scored.candidate.albumTitle,
                    scored.candidate.releaseDate?.formatted(.dateTime.year())].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
            }
            .buttonStyle(.plain)
          }
          Button("Skip") { model.skip(row.id) }.font(.caption)
        }
      case .notFound(let reason):
        Text(reason ?? "No confident match found. Skipped.").font(.caption).foregroundStyle(.secondary)
      case .uploadNotFound(let reason, _):
        Text(reason).font(.caption).foregroundStyle(.secondary)
      case .duplicate(_, let index):
        Text("Same as #\(index + 1)").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private func artwork(_ candidate: CatalogSongCandidate) -> some View {
    Group {
      if let url = candidate.artworkURL {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
          Image(systemName: "music.note")
        }
      } else { Image(systemName: "music.note") }
    }
    .frame(width: 44, height: 44)
    .clipShape(.rect(cornerRadius: 5))
  }
}
