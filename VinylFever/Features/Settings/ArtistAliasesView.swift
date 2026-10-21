import Dependencies
import Observation
import SQLiteData
import SwiftUI
import VinylFeverCore

@MainActor
@Observable
final class ArtistAliasesModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.librarySnapshotStore) private var snapshotStore
  var candidates: [ArtistAliasCandidate] = []
  var accepted: [ArtistAlias] = []
  var isLoading = false
  var errorMessage: String?

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let rows = try await database.read { db in try ArtistAlias.all.fetchAll(db) }
      accepted = rows.filter { $0.decision == "accepted" }.sorted { $0.variant < $1.variant }
      guard let snapshot = try await snapshotStore.read() else {
        candidates = []
        errorMessage = "Refresh the library snapshot to find artist aliases."
        return
      }
      let index = LibraryIndex(snapshot: snapshot)
      candidates = ArtistAliasCandidateFinder.candidates(in: index, decidedPairs: ArtistAlias.decidedPairs(rows))
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }

  func decide(_ candidate: ArtistAliasCandidate, canonical: String?, variant: String? = nil) async {
    do {
      try await database.write { db in
        try ArtistAlias.decide(
          variant: variant ?? candidate.variant,
          canonical: canonical ?? candidate.canonical,
          accepted: canonical != nil,
          in: db)
      }
      try await exportAliases()
      await load()
    } catch { errorMessage = error.localizedDescription }
  }

  func undo(_ alias: ArtistAlias) async {
    do {
      try await database.write { db in try ArtistAlias.undo(alias.variant, in: db) }
      try await exportAliases()
      await load()
    } catch { errorMessage = error.localizedDescription }
  }

  private func exportAliases() async throws {
    let aliases = try await database.read { db in ArtistAlias.acceptedMap(try ArtistAlias.all.fetchAll(db)) }
    try await snapshotStore.writeAliases(aliases)
  }
}

struct ArtistAliasesView: View {
  @State private var model = ArtistAliasesModel()
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let error = model.errorMessage {
          ContentUnavailableView(error, systemImage: "person.2.badge.gearshape")
        }
        if !model.candidates.isEmpty {
          Section("Suggested aliases") {
            ForEach(model.candidates) { candidate in
              VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                  Text(candidate.variantDisplay).font(.headline)
                  Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                  Text(candidate.canonicalDisplay).font(.headline)
                  Spacer()
                  Text("\(candidate.variantTrackCount.formatted()) · \(candidate.canonicalTrackCount.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
                }
                if !candidate.sharedTitles.isEmpty {
                  Text(candidate.sharedTitles.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                  Button("Same artist · \(candidate.canonicalDisplay)") {
                    Task { await model.decide(candidate, canonical: candidate.canonical) }
                  }
                  Button("Same artist · \(candidate.variantDisplay)") {
                    Task { await model.decide(candidate, canonical: candidate.variant, variant: candidate.canonical) }
                  }
                  Button("Different") {
                    Task { await model.decide(candidate, canonical: nil) }
                  }
                }.buttonStyle(.borderless)
              }.padding(.vertical, 4)
            }
          }
        } else if !model.isLoading && model.errorMessage == nil {
          ContentUnavailableView("No pending candidates", systemImage: "checkmark.circle")
        }
        if !model.accepted.isEmpty {
          Section("Accepted aliases") {
            ForEach(model.accepted) { alias in
              HStack {
                Text(alias.variant)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(alias.canonical)
                Spacer()
                Button("Undo") { Task { await model.undo(alias) } }
              }
            }
          }
        }
      }
      .overlay { if model.isLoading { ProgressView().controlSize(.small) } }
      .navigationTitle("Artist Aliases")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } } }
      }
      .task { await model.load() }
    }
    .frame(minWidth: 760, minHeight: 520)
  }
}
