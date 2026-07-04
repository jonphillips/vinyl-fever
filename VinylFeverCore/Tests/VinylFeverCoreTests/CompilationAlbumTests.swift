import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct CompilationAlbumTests {
  @Test
  func seedingDerivesMostCommonIdentityAndSurfacesDisagreement() async throws {
    let folder = URL(fileURLWithPath: "/Music/Covers")
    let files = [
      seedFile(id: UUID(1), name: "01.flac"),
      seedFile(id: UUID(2), name: "02.flac"),
      seedFile(id: UUID(3), name: "03.flac"),
    ]
    let artwork = Data([1, 2, 3])

    let candidate = try await withDependencies {
      $0.uuid = .incrementing
    } operation: {
      CompilationAlbumSeeder().deriveCandidate(
        folder: folder,
        metadata: [
          (files[0], AudioTags(album: "Great Covers", albumArtist: "Jon Phillips", embeddedArtwork: artwork)),
          (files[1], AudioTags(album: "Great Covers", albumArtist: "Jon Phillips")),
          (files[2], AudioTags(album: "Covers", albumArtist: "Various Artists")),
        ]
      )
    }

    expectNoDifference(candidate.album.identity, AlbumIdentity(album: "Great Covers", albumArtist: "Jon Phillips"))
    expectNoDifference(candidate.album.name, "Great Covers")
    expectNoDifference(candidate.album.displayImage, artwork)
    expectNoDifference(candidate.album.fallbackArtwork, artwork)
    expectNoDifference(
      candidate.warnings,
      [
        "Album disagrees; using Great Covers. Values: Great Covers (2), Covers (1).",
        "Album Artist disagrees; using Jon Phillips. Values: Jon Phillips (2), Various Artists (1).",
      ]
    )
  }

  @Test
  func registryPersistsCompilationAlbums() throws {
    let database = try VinylFeverDatabase.open(path: temporaryDatabasePath())
    let album = CompilationAlbum(
      id: UUID(1),
      name: "Great Covers",
      identity: AlbumIdentity(album: "Great Covers", albumArtist: "Jon Phillips"),
      displayImage: Data([9]),
      fallbackArtwork: Data([8]),
      ruleset: CompilationRuleset(
        stripTrackAndDisc: true,
        setCompilationFlag: false,
        groupingTokens: ["Great Covers"]
      ),
      seedFolderPath: "/Music/Great Covers",
      seedWarnings: ["Album disagrees; using Great Covers."]
    )

    try database.write { db in
      try CompilationAlbumRegistry.upsert([album], in: db)
    }

    let persisted = try database.read { db in
      try CompilationAlbum.all.fetchAll(db)
    }

    expectNoDifference(persisted, [album])
    expectNoDifference(persisted.first?.ruleset.groupingTokens, ["Great Covers"])
    expectNoDifference(persisted.first?.seedWarnings, ["Album disagrees; using Great Covers."])
  }

  @Test
  func candidatesSkipUnreadableFilesReportProgressAndStayOrdered() async throws {
    let root = URL(fileURLWithPath: "/Music/Parent")
    let albumA = root.appendingPathComponent("AlbumA")
    let albumB = root.appendingPathComponent("AlbumB")
    let a1 = seedFile(id: UUID(1), name: "a1.flac")
    let a2 = seedFile(id: UUID(2), name: "a2.flac")
    let b1 = seedFile(id: UUID(3), name: "b1.flac")
    let recorder = SeedProgressRecorder()

    let candidates = try await withDependencies {
      $0.uuid = .incrementing
      $0.fileSystemClient.discoverCompilationAlbumSeedFolders = { _ in [albumA, albumB] }
      $0.fileSystemClient.scanAudioFolder = { folder in
        folder.lastPathComponent == "AlbumA" ? [a1, a2] : [b1]
      }
      $0.audioMetadataClient.read = { request in
        if request.url == a2.url {
          throw UnreadableFileError()
        }
        return AudioTags(albumArtist: "Various Artists")
      }
    } operation: {
      try await CompilationAlbumSeeder().candidates(
        from: root,
        toolPaths: AudioToolPaths(statuses: [])
      ) { completed, total in
        await recorder.record(completed: completed, total: total)
      }
    }

    // Deterministic order preserved despite concurrent reads.
    expectNoDifference(candidates.map(\.folderURL.lastPathComponent), ["AlbumA", "AlbumB"])
    // AlbumA's unreadable file is dropped, not fatal; its skip is surfaced as a warning.
    expectNoDifference(candidates[0].trackCount, 1)
    expectNoDifference(candidates[0].warnings, ["1 file(s) could not be read and were skipped."])
    expectNoDifference(candidates[1].trackCount, 1)
    expectNoDifference(candidates[1].warnings, [])

    let updates = await recorder.updates
    expectNoDifference(updates.first?.total, 2)
    expectNoDifference(updates.last.map { [$0.completed, $0.total] }, [2, 2])
    expectNoDifference(updates.map(\.completed).max(), 2)
  }

  @Test
  func applyPlanSetsIdentityMergesGroupingStripsNumbersAndBranchesArtwork() {
    let entry = CompilationAlbum(
      id: UUID(10),
      name: "Great Covers",
      identity: AlbumIdentity(album: "Great Covers", albumArtist: "Jon Phillips"),
      ruleset: CompilationRuleset(groupingTokens: ["Great Covers", "Power Pop :: Covers"])
    )
    let sourceRoot = URL(fileURLWithPath: "/Incoming")
    let fallbackArtworkURL = sourceRoot.appendingPathComponent("front.jpg")
    let first = seedFile(id: UUID(1), name: "01.mp3")
    let second = seedFile(id: UUID(2), name: "02.flac")
    let plan = CompilationApplyPlan(
      entry: entry,
      sourceRoot: sourceRoot,
      files: [first, second],
      currentTagsByFileID: [
        first.id: AudioTags(
          title: "Song A",
          artist: "Artist A",
          album: "Original",
          albumArtist: "Artist A",
          grouping: "Existing",
          trackNumber: 7,
          trackTotal: 12,
          discNumber: 2,
          hasEmbeddedArtwork: true
        ),
        second.id: AudioTags(
          title: "Song B",
          artist: "Artist B",
          album: "Other",
          albumArtist: "Artist B",
          trackNumber: 3,
          discNumber: 1,
          hasEmbeddedArtwork: false
        ),
      ],
      fallbackArtworkURL: fallbackArtworkURL
    )

    expectNoDifference(plan.tracks.map(\.artwork), [.keepExisting, .applyFallback])
    expectNoDifference(plan.tracks[0].fallbackArtworkURL, nil)
    expectNoDifference(plan.tracks[1].fallbackArtworkURL, fallbackArtworkURL)
    expectNoDifference(plan.tracks[0].proposed.album, "Great Covers")
    expectNoDifference(plan.tracks[0].proposed.albumArtist, "Jon Phillips")
    expectNoDifference(plan.tracks[0].proposed.grouping, "Existing | Great Covers | Power Pop :: Covers")
    expectNoDifference(plan.tracks[0].proposed.trackNumber, nil)
    expectNoDifference(plan.tracks[0].proposed.clearedFields.contains(.trackNumber), true)

    let applyPlan = ApplyPlan(compilationPlan: plan)
    expectNoDifference(
      applyPlan.operations.map(ApplyOperationSnapshot.init),
      [
        .copy(source: "/Shows/BruceHornsby/01.mp3", destination: "/Incoming/Working/01.mp3"),
        .writeTags(
          file: "/Incoming/Working/01.mp3",
          format: .mp3,
          title: nil,
          trackNumber: nil,
          trackTotal: 12,
          cover: nil
        ),
        .copy(source: "/Shows/BruceHornsby/02.flac", destination: "/Incoming/Working/02.flac"),
        .writeTags(
          file: "/Incoming/Working/02.flac",
          format: .flac,
          title: nil,
          trackNumber: nil,
          trackTotal: 0,
          cover: "/Incoming/front.jpg"
        ),
      ]
    )
  }

  @Test
  func applyPlanPreviewKeepsTrackAndDiscWhenStripIsOff() {
    let entry = CompilationAlbum(
      id: UUID(10),
      name: "Great Covers",
      identity: AlbumIdentity(album: "Great Covers", albumArtist: "Jon Phillips"),
      ruleset: CompilationRuleset(stripTrackAndDisc: false)
    )
    let file = seedFile(id: UUID(1), name: "01.mp3")
    let plan = CompilationApplyPlan(
      entry: entry,
      sourceRoot: URL(fileURLWithPath: "/Incoming"),
      files: [file],
      currentTagsByFileID: [
        file.id: AudioTags(
          trackNumber: 7,
          trackTotal: 12,
          discNumber: 2
        ),
      ]
    )

    expectNoDifference(plan.tracks[0].proposed.trackNumber, 7)
    expectNoDifference(plan.tracks[0].proposed.trackTotal, 12)
    expectNoDifference(plan.tracks[0].proposed.discNumber, 2)
    expectNoDifference(
      plan.tracks[0].diffs.filter { ["Track Number", "Disc Number"].contains($0.field) },
      [
        CompilationTagDiff(field: "Track Number", current: "7", proposed: "7"),
        CompilationTagDiff(field: "Disc Number", current: "2", proposed: "2"),
      ]
    )
  }
}

private struct UnreadableFileError: Error {}

private actor SeedProgressRecorder {
  private(set) var updates: [(completed: Int, total: Int)] = []

  func record(completed: Int, total: Int) {
    updates.append((completed, total))
  }
}

private func seedFile(id: UUID, name: String) -> ScannedAudioFile {
  let format = AudioFormat(pathExtension: URL(fileURLWithPath: name).pathExtension) ?? .flac
  return ScannedAudioFile(
    id: id,
    url: applyShowRoot.appendingPathComponent(name),
    format: format,
    sortKey: name
  )
}

private func temporaryDatabasePath() throws -> String {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("VinylFever.sqlite").path(percentEncoded: false)
}
