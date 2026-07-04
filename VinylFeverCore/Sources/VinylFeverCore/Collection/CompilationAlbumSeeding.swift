import Dependencies
import Foundation
import SQLiteData

public struct CompilationAlbumSeeder: Sendable {
  @Dependency(\.audioMetadataClient) private var audioMetadataClient
  @Dependency(\.fileSystemClient) private var fileSystemClient
  @Dependency(\.uuid) private var uuid

  public init() {
  }

  public func candidates(from root: URL, toolPaths: AudioToolPaths) async throws -> [CompilationAlbumSeedCandidate] {
    let folders = try fileSystemClient.discoverCompilationAlbumSeedFolders(root)
    var candidates: [CompilationAlbumSeedCandidate] = []
    for folder in folders {
      try Task.checkCancellation()
      let files = try fileSystemClient.scanAudioFolder(folder)
      let metadata = try await metadata(for: files, toolPaths: toolPaths)
      candidates.append(deriveCandidate(folder: folder, metadata: metadata))
    }
    return candidates
  }

  private func metadata(
    for files: [ScannedAudioFile],
    toolPaths: AudioToolPaths
  ) async throws -> [(ScannedAudioFile, AudioTags)] {
    var values: [(ScannedAudioFile, AudioTags)] = []
    for file in files {
      try Task.checkCancellation()
      let tags = try await audioMetadataClient.read(AudioMetadataRequest(file: file, toolPaths: toolPaths))
      values.append((file, tags))
    }
    return values
  }

  public func deriveCandidate(
    folder: URL,
    metadata: [(ScannedAudioFile, AudioTags)]
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
