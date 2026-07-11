import Dependencies
import Foundation

/// Imports produced files into Music by dropping them into Music's "Automatically Add"
/// folder, then polling the library until every track appears — replacing the single,
/// timeout-prone `add` Apple Event with a filesystem copy plus bounded reads.
///
/// The drop and the reads both go through `MusicAppClient`, so this type is fully
/// testable without touching Music or the real filesystem. Polling uses `Task.sleep`
/// with an injectable `pollInterval` (set to `.zero` in tests) rather than a clock
/// dependency, keeping the unit tests fast and free of clock-override boilerplate.
public struct MusicWatchFolderImporter: Sendable {
  @Dependency(\.musicAppClient) private var musicAppClient

  /// Ceiling for how long we wait for Music's watcher to ingest the dropped files. A
  /// healthy import lands in a few seconds; this only bounds the pathological case.
  private let deadline: Duration
  /// Delay between library reads while waiting for the drop to be ingested.
  private let pollInterval: Duration

  public init(deadline: Duration = .seconds(180), pollInterval: Duration = .seconds(2)) {
    self.deadline = deadline
    self.pollInterval = pollInterval
  }

  /// Resolves each plan track against `existingLibraryTracks`; anything already present is
  /// reported without re-importing. The rest are copied into `watchFolder`, then we poll
  /// the album until they resolve or the deadline passes. Returns one `ImportedTrack` per
  /// plan track, in plan order.
  public func importTracks(
    plan: ConversionPlan,
    watchFolder: URL,
    existingLibraryTracks: [ImportedTrackRef]
  ) async throws -> [ImportedTrack] {
    var outcomesByID: [ConversionTrackPlan.ID: ImportedTrack] = [:]
    var pending: [ConversionTrackPlan] = []

    for track in plan.tracks {
      try Task.checkCancellation()
      let resolution = MusicLibraryMatcher.resolve(track: track, libraryTracks: existingLibraryTracks)
      if let libraryRef = resolution.libraryRef {
        outcomesByID[track.id] = ImportedTrack(
          id: track.id,
          sourceURL: track.verificationFile,
          libraryRef: libraryRef,
          status: .alreadyPresent
        )
      } else {
        pending.append(track)
      }
    }

    if !pending.isEmpty {
      // The copy is the real work; it never depends on Music answering a scripting query, so it
      // always runs. Confirming ingest afterwards is best-effort.
      try await musicAppClient.importViaWatchFolder(pending.map(\.verificationFile), watchFolder)
      let resolvedLibraryTracks = try await bestEffortResolvedTracks(plan: plan, pending: pending)
      for track in pending {
        let resolution = MusicLibraryMatcher.resolve(
          track: track,
          libraryTracks: resolvedLibraryTracks
        )
        // A confirmed library match is `.imported`; otherwise the file is safely dropped and Music
        // will ingest it on its own schedule, so report `.dropped` (a success) rather than failing.
        outcomesByID[track.id] = ImportedTrack(
          id: track.id,
          sourceURL: track.verificationFile,
          libraryRef: resolution.libraryRef,
          status: resolution.libraryRef == nil ? .dropped : .imported
        )
      }
    }

    return plan.tracks.compactMap { outcomesByID[$0.id] }
  }

  /// Polls for ingest confirmation, but never lets a scripting failure fail the import: the files
  /// are already in the watch folder. A read timeout or error yields an empty result (callers then
  /// mark those tracks `.dropped`). Cancellation still propagates so an aborted append stops.
  private func bestEffortResolvedTracks(
    plan: ConversionPlan,
    pending: [ConversionTrackPlan]
  ) async throws -> [ImportedTrackRef] {
    do {
      return try await pollUntilResolved(plan: plan, pending: pending)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return []
    }
  }

  /// Reads the album repeatedly until every `pending` track resolves or the attempt budget
  /// (derived from `deadline` / `pollInterval`) is exhausted. Returns the most recent read
  /// so the caller can resolve whatever did land.
  private func pollUntilResolved(
    plan: ConversionPlan,
    pending: [ConversionTrackPlan]
  ) async throws -> [ImportedTrackRef] {
    var latest = try await musicAppClient.readAlbumTracks(
      MusicAlbumReadRequest(albumTitle: plan.albumTitle)
    )
    var attemptsRemaining = maxPollAttempts
    while !allResolved(pending: pending, in: latest), attemptsRemaining > 1 {
      try Task.checkCancellation()
      try await Task.sleep(for: pollInterval)
      attemptsRemaining -= 1
      latest = try await musicAppClient.readAlbumTracks(
        MusicAlbumReadRequest(albumTitle: plan.albumTitle)
      )
    }
    return latest
  }

  private func allResolved(
    pending: [ConversionTrackPlan],
    in libraryTracks: [ImportedTrackRef]
  ) -> Bool {
    pending.allSatisfy {
      MusicLibraryMatcher.resolve(track: $0, libraryTracks: libraryTracks).libraryRef != nil
    }
  }

  /// Number of library reads to attempt before giving up. When `pollInterval` is ~zero
  /// (tests), the read sequence itself decides when to stop, so this only needs to be a
  /// generous cap rather than a precise `deadline / pollInterval`.
  private var maxPollAttempts: Int {
    let deadlineSeconds = seconds(deadline)
    let intervalSeconds = seconds(pollInterval)
    guard intervalSeconds > 0 else {
      return 1_000
    }
    return max(1, Int((deadlineSeconds / intervalSeconds).rounded(.up)))
  }

  private func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }
}
