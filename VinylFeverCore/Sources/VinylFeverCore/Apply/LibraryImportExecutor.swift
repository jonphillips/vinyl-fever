import Dependencies
import Foundation

public struct LibraryImportExecutor: Sendable {
  @Dependency(\.musicAppClient) private var musicAppClient
  @Dependency(\.runLogClient) private var runLogClient

  public init() {
  }

  public func importToLibrary(_ plan: ConversionPlan) async throws -> ImportResult {
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .importLibrary,
        command: commandText(for: plan)
      )
    )

    do {
      try Task.checkCancellation()
      let existingLibraryTracks = try await musicAppClient.readAlbumTracks(
        MusicAlbumReadRequest(albumTitle: plan.albumTitle)
      )
      var outcomesByID: [ConversionTrackPlan.ID: ImportedTrack] = [:]
      var importedTracks: [ConversionTrackPlan] = []
      var addedLibraryRefs: [ImportedTrackRef] = []

      for track in plan.tracks {
        try Task.checkCancellation()
        let resolution = MusicLibraryMatcher.resolve(
          track: track,
          libraryTracks: existingLibraryTracks
        )
        if let libraryRef = resolution.libraryRef {
          outcomesByID[track.id] = ImportedTrack(
            id: track.id,
            sourceURL: track.verificationFile,
            libraryRef: libraryRef,
            status: .alreadyPresent
          )
        } else {
          do {
            let refs = try await musicAppClient.add([track.verificationFile])
            addedLibraryRefs.append(contentsOf: refs)
            importedTracks.append(track)
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            outcomesByID[track.id] = ImportedTrack(
              id: track.id,
              sourceURL: track.verificationFile,
              libraryRef: nil,
              status: .failed(error.localizedDescription)
            )
          }
        }
      }

      let postImportRead = await postImportLibraryTracks(
        plan: plan,
        needsRefresh: !importedTracks.isEmpty,
        existingLibraryTracks: existingLibraryTracks,
        addedLibraryRefs: addedLibraryRefs
      )
      for track in importedTracks where outcomesByID[track.id] == nil {
        let resolution = MusicLibraryMatcher.resolve(
          track: track,
          libraryTracks: postImportRead.libraryTracks
        )
        outcomesByID[track.id] = ImportedTrack(
          id: track.id,
          sourceURL: track.verificationFile,
          libraryRef: resolution.libraryRef,
          status: resolution.libraryRef == nil
            ? .failed(postImportRead.unresolvedMessage)
            : .imported
        )
      }

      let importedTrackOutcomes = plan.tracks.compactMap { outcomesByID[$0.id] }
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

  private func postImportLibraryTracks(
    plan: ConversionPlan,
    needsRefresh: Bool,
    existingLibraryTracks: [ImportedTrackRef],
    addedLibraryRefs: [ImportedTrackRef]
  ) async -> PostImportLibraryRead {
    guard needsRefresh else {
      return PostImportLibraryRead(libraryTracks: existingLibraryTracks)
    }
    do {
      let refreshedLibraryTracks = try await musicAppClient.readAlbumTracks(
        MusicAlbumReadRequest(albumTitle: plan.albumTitle)
      )
      return PostImportLibraryRead(
        libraryTracks: deduplicated(addedLibraryRefs + refreshedLibraryTracks)
      )
    } catch {
      return PostImportLibraryRead(
        libraryTracks: deduplicated(addedLibraryRefs + existingLibraryTracks),
        readError: error.localizedDescription
      )
    }
  }

  private func deduplicated(_ refs: [ImportedTrackRef]) -> [ImportedTrackRef] {
    var seen: Set<String> = []
    var result: [ImportedTrackRef] = []
    var unkeyedIndex = 0
    for ref in refs {
      let key: String
      if !ref.id.isEmpty {
        key = "id:\(ref.id)"
      } else if let locationPath = ref.locationPath {
        key = "location:\(locationPath)"
      } else {
        unkeyedIndex += 1
        key = "unkeyed:\(unkeyedIndex)"
      }
      guard seen.insert(key).inserted else {
        continue
      }
      result.append(ref)
    }
    return result
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
    let failedCount = tracks.count { !$0.didSucceed }
    if failedCount > 0 {
      return "\(failedCount) of \(tracks.count) failed"
    }

    let importedCount = tracks.count { $0.status == .imported }
    let alreadyPresentCount = tracks.count { $0.status == .alreadyPresent }
    switch (importedCount, alreadyPresentCount) {
    case (0, 0):
      return "no files"
    case (_, 0):
      return "imported"
    case (0, _):
      return "already present"
    default:
      return "\(importedCount) imported, \(alreadyPresentCount) already present"
    }
  }

  private func commandText(for plan: ConversionPlan) -> String {
    let lines = [
      "read Music album \"\(plan.albumTitle)\"",
    ] + plan.tracks.map { track in
      "add \(track.verificationFile.path(percentEncoded: false))"
    }
    return lines.joined(separator: "\n")
  }
}

private struct PostImportLibraryRead {
  var libraryTracks: [ImportedTrackRef]
  var readError: String?

  var unresolvedMessage: String {
    if let readError {
      return "Music add completed, but library refresh failed: \(readError)"
    }
    return "Music add completed, but no matching library item was found."
  }
}
