import Dependencies
import Foundation

public struct LibraryImportExecutor: Sendable {
  @Dependency(\.musicAppClient) private var musicAppClient
  @Dependency(\.runLogClient) private var runLogClient

  private let importer: MusicWatchFolderImporter

  public init(importer: MusicWatchFolderImporter = MusicWatchFolderImporter()) {
    self.importer = importer
  }

  public func importToLibrary(_ plan: ConversionPlan, watchFolder: URL) async throws -> ImportResult {
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .importLibrary,
        command: commandText(for: plan)
      )
    )

    do {
      try Task.checkCancellation()
      // Best-effort dedup read: if Music is slow to answer we still drop the files rather than
      // failing the import. The copy into the watch folder is the real work.
      let existingLibraryTracks = (try? await musicAppClient.readAlbumTracks(
        MusicAlbumReadRequest(albumTitle: plan.albumTitle)
      )) ?? []
      let importedTrackOutcomes = try await importer.importTracks(
        plan: plan,
        watchFolder: watchFolder,
        existingLibraryTracks: existingLibraryTracks
      )
      for outcome in importedTrackOutcomes {
        try await append(outcome: outcome, run: run)
      }

      let exitSummary = exitSummary(for: importedTrackOutcomes)
      let closedRun = try await close(run: run, exitSummary: exitSummary)
      return ImportResult(run: closedRun, tracks: importedTrackOutcomes, exitSummary: exitSummary)
    } catch is CancellationError {
      _ = try? await close(run: run, exitSummary: "cancelled")
      throw CancellationError()
    } catch {
      _ = try? await close(run: run, exitSummary: error.localizedDescription)
      throw error
    }
  }

  private func append(outcome: ImportedTrack, run: RunRecord) async throws {
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: outcome.sourceURL.path(percentEncoded: false),
        producedPath: outcome.libraryRef?.locationPath,
        status: outcome.runOutcomeStatus,
        note: outcome.note
      )
    )
  }

  private func close(run: RunRecord, exitSummary: String) async throws -> RunRecord {
    try await runLogClient.close(
      RunLogCloseRequest(runID: run.id, exitSummary: exitSummary)
    )
  }

  private func exitSummary(for tracks: [ImportedTrack]) -> String {
    LibraryImportSummary.text(for: tracks)
  }

  private func commandText(for plan: ConversionPlan) -> String {
    let lines = [
      "read Music album \"\(plan.albumTitle)\"",
    ] + plan.tracks.map { track in
      "drop \(track.verificationFile.path(percentEncoded: false))"
    }
    return lines.joined(separator: "\n")
  }
}
