import Dependencies
import Foundation
import SQLiteData

public struct CompilationAlbumSeeder: Sendable {
  @Dependency(\.audioMetadataClient) private var audioMetadataClient
  @Dependency(\.fileSystemClient) private var fileSystemClient
  @Dependency(\.uuid) private var uuid

  /// Cap on simultaneous tag-reading subprocesses across all album folders. Seeding a
  /// parent folder can span many albums, so an unbounded `TaskGroup` would fork one
  /// `ffprobe`/`metaflac` per file all at once; this keeps the fan-out bounded.
  static let maxConcurrentReads = max(4, ProcessInfo.processInfo.activeProcessorCount)

  public init() {
  }

  /// Reads every candidate album under `root` concurrently.
  ///
  /// Mirrors the show-folder metadata path (`AppModel.refreshCurrentMetadata`): each
  /// file's tags are read on a `TaskGroup`, capped by a shared limiter so a parent
  /// folder of many albums doesn't spawn thousands of `ffprobe`/`metaflac`
  /// subprocesses at once. A file that can't be read is skipped rather than aborting
  /// the whole seed. `progress` reports completed/total album folders as they finish.
  public func candidates(
    from root: URL,
    toolPaths: AudioToolPaths,
    progress: (@Sendable (_ completed: Int, _ total: Int) async -> Void)? = nil
  ) async throws -> [CompilationAlbumSeedCandidate] {
    let folders = try fileSystemClient.discoverCompilationAlbumSeedFolders(root)
    let total = folders.count
    await progress?(0, total)
    guard total > 0 else {
      return []
    }

    let limiter = SeedConcurrencyLimiter(limit: Self.maxConcurrentReads)
    return try await withThrowingTaskGroup(
      of: (offset: Int, candidate: CompilationAlbumSeedCandidate).self
    ) { group in
      for (offset, folder) in folders.enumerated() {
        group.addTask {
          try Task.checkCancellation()
          let files = try self.fileSystemClient.scanAudioFolder(folder)
          let read = try await self.metadata(for: files, toolPaths: toolPaths, limiter: limiter)
          return (
            offset,
            self.deriveCandidate(
              folder: folder,
              metadata: read.values,
              unreadableCount: read.unreadableCount
            )
          )
        }
      }

      var ordered = [CompilationAlbumSeedCandidate?](repeating: nil, count: total)
      var completed = 0
      for try await result in group {
        ordered[result.offset] = result.candidate
        completed += 1
        await progress?(completed, total)
      }
      return ordered.compactMap { $0 }
    }
  }

  /// Reads tags for one album's files concurrently, tolerating per-file failures.
  ///
  /// A file whose tags can't be read is counted in `unreadableCount` and dropped from
  /// `values` instead of aborting the batch. Cancellation still propagates so the
  /// caller can stop the whole seed.
  private func metadata(
    for files: [ScannedAudioFile],
    toolPaths: AudioToolPaths,
    limiter: SeedConcurrencyLimiter
  ) async throws -> (values: [(ScannedAudioFile, AudioTags)], unreadableCount: Int) {
    let audioMetadataClient = self.audioMetadataClient
    return try await withThrowingTaskGroup(of: (offset: Int, tags: AudioTags?).self) { group in
      for (offset, file) in files.enumerated() {
        group.addTask {
          try Task.checkCancellation()
          await limiter.acquire()
          do {
            let tags = try await audioMetadataClient.read(
              AudioMetadataRequest(file: file, toolPaths: toolPaths)
            )
            await limiter.release()
            return (offset, tags)
          } catch is CancellationError {
            await limiter.release()
            throw CancellationError()
          } catch {
            await limiter.release()
            return (offset, nil)
          }
        }
      }

      var tagsByOffset = [AudioTags?](repeating: nil, count: files.count)
      var unreadableCount = 0
      for try await result in group {
        if let tags = result.tags {
          tagsByOffset[result.offset] = tags
        } else {
          unreadableCount += 1
        }
      }
      let values = files.enumerated().compactMap { offset, file in
        tagsByOffset[offset].map { (file, $0) }
      }
      return (values, unreadableCount)
    }
  }

  public func deriveCandidate(
    folder: URL,
    metadata: [(ScannedAudioFile, AudioTags)],
    unreadableCount: Int = 0
  ) -> CompilationAlbumSeedCandidate {
    let albumChoice = Self.mostCommon(
      metadata.compactMap { $0.1.album?.nilIfBlank },
      fallback: folder.lastPathComponent
    )
    let albumArtistChoice = Self.mostCommon(
      metadata.compactMap { $0.1.albumArtist?.nilIfBlank },
      fallback: "Unknown Album Artist"
    )
    var warnings: [String] = []
    warnings += Self.disagreementWarnings(
      field: "Album",
      chosen: albumChoice.value,
      counts: albumChoice.counts
    )
    warnings += Self.disagreementWarnings(
      field: "Album Artist",
      chosen: albumArtistChoice.value,
      counts: albumArtistChoice.counts
    )
    if unreadableCount > 0 {
      warnings.append("\(unreadableCount) file(s) could not be read and were skipped.")
    }

    let artwork = metadata.lazy.compactMap(\.1.embeddedArtwork).first
    let album = CompilationAlbum(
      id: uuid(),
      name: albumChoice.value,
      identity: AlbumIdentity(album: albumChoice.value, albumArtist: albumArtistChoice.value),
      displayImage: artwork,
      fallbackArtwork: artwork,
      seedFolderPath: folder.standardizedFileURL.path(percentEncoded: false),
      seedWarnings: warnings
    )
    return CompilationAlbumSeedCandidate(
      id: album.id,
      folderURL: folder.standardizedFileURL,
      album: album,
      trackCount: metadata.count,
      warnings: warnings
    )
  }

  private static func mostCommon(
    _ values: [String],
    fallback: String
  ) -> (value: String, counts: [String: Int]) {
    guard !values.isEmpty else {
      return (fallback, [:])
    }
    let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    let value = counts
      .sorted { lhs, rhs in
        if lhs.value != rhs.value {
          return lhs.value > rhs.value
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
      }
      .first?
      .key ?? fallback
    return (value, counts)
  }

  private static func disagreementWarnings(
    field: String,
    chosen: String,
    counts: [String: Int]
  ) -> [String] {
    guard counts.count > 1 else {
      return []
    }
    let alternatives = counts
      .sorted { lhs, rhs in
        if lhs.value != rhs.value {
          return lhs.value > rhs.value
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
      }
      .map { "\($0.key) (\($0.value))" }
      .joined(separator: ", ")
    return ["\(field) disagrees; using \(chosen). Values: \(alternatives)."]
  }
}

/// A minimal async counting semaphore used to bound how many tag-reading
/// subprocesses run concurrently while seeding.
actor SeedConcurrencyLimiter {
  private var available: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) {
    self.available = max(1, limit)
  }

  func acquire() async {
    if available > 0 {
      available -= 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      available += 1
    } else {
      waiters.removeFirst().resume()
    }
  }
}

public enum CompilationAlbumRegistry {
  public static func upsert(_ albums: [CompilationAlbum], in db: Database) throws {
    for album in albums {
      try CompilationAlbum.upsert { album }.execute(db)
    }
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
