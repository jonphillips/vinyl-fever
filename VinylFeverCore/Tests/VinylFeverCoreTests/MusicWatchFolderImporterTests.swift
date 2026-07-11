import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct MusicWatchFolderImporterTests {
  private static let fastImporter = MusicWatchFolderImporter(
    deadline: .milliseconds(50),
    pollInterval: .milliseconds(1)
  )
  private static let watchFolder = URL(filePath: "/tmp/AutomaticallyAdd")

  @Test
  func reportsAlreadyPresentTracksWithoutDropping() async throws {
    let plan = makeMultiTrackConversionPlan()
    let existing = plan.tracks.map(libraryRef(for:))
    let music = MusicAppRecorder(albumReads: [])

    let outcomes = try await withDependencies {
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
    } operation: {
      try await Self.fastImporter.importTracks(
        plan: plan,
        watchFolder: Self.watchFolder,
        existingLibraryTracks: existing
      )
    }

    expectNoDifference(outcomes.map(\.status), [.alreadyPresent, .alreadyPresent])
    let dropped = await music.droppedFiles()
    expectNoDifference(dropped, [])
  }

  @Test
  func dropsOnlyMissingTracksAndResolvesThem() async throws {
    let plan = makeMultiTrackConversionPlan()
    let present = libraryRef(for: plan.tracks[0])
    let music = MusicAppRecorder(albumReads: [plan.tracks.map(libraryRef(for:))])

    let outcomes = try await withDependencies {
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
    } operation: {
      try await Self.fastImporter.importTracks(
        plan: plan,
        watchFolder: Self.watchFolder,
        existingLibraryTracks: [present]
      )
    }

    expectNoDifference(outcomes.map(\.status), [.alreadyPresent, .imported])
    let dropped = await music.droppedFiles()
    // Only the missing second track is dropped.
    expectNoDifference(dropped.map(\.urls), [[plan.tracks[1].verificationFile]])
    expectNoDifference(dropped.map(\.folder), [Self.watchFolder])
  }

  @Test
  func keepsPollingUntilMusicIngestsTheDrop() async throws {
    let plan = makeMultiTrackConversionPlan()
    let resolved = plan.tracks.map(libraryRef(for:))
    // Music takes a couple of reads to ingest: two empty reads, then the tracks appear.
    let music = MusicAppRecorder(albumReads: [[], [], resolved])

    let outcomes = try await withDependencies {
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
    } operation: {
      try await Self.fastImporter.importTracks(
        plan: plan,
        watchFolder: Self.watchFolder,
        existingLibraryTracks: []
      )
    }

    expectNoDifference(outcomes.map(\.status), [.imported, .imported])
    let readCount = await music.readCount()
    #expect(readCount >= 3)
  }

  @Test
  func dropsTracksMusicHasNotYetIngested() async throws {
    let plan = makeMultiTrackConversionPlan()
    let music = MusicAppRecorder(albumReads: [[]])

    let outcomes = try await withDependencies {
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      $0.musicAppClient.readAlbumTracks = { try await music.readAlbumTracks($0) }
    } operation: {
      try await Self.fastImporter.importTracks(
        plan: plan,
        watchFolder: Self.watchFolder,
        existingLibraryTracks: []
      )
    }

    // The files were copied into the watch folder; the poll just never saw them appear. That is a
    // successful drop awaiting Music's ingest, not a failure.
    expectNoDifference(outcomes.map(\.status), [.dropped, .dropped])
  }

  @Test
  func dropsTracksEvenWhenIngestConfirmationReadThrows() async throws {
    let plan = makeMultiTrackConversionPlan()
    let music = MusicAppRecorder(albumReads: [])

    let outcomes = try await withDependencies {
      $0.musicAppClient.importViaWatchFolder = { try await music.importViaWatchFolder($0, $1) }
      // Music is unresponsive to scripting — the ingest-confirmation read times out.
      $0.musicAppClient.readAlbumTracks = { _ in throw ImporterTestError.readTimedOut }
    } operation: {
      try await Self.fastImporter.importTracks(
        plan: plan,
        watchFolder: Self.watchFolder,
        existingLibraryTracks: []
      )
    }

    // A read that throws must not undo the drop: the files still land in the watch folder and are
    // reported `.dropped`, not failed.
    expectNoDifference(outcomes.map(\.status), [.dropped, .dropped])
    let dropped = await music.droppedFiles()
    expectNoDifference(
      dropped.map(\.urls),
      [[plan.tracks[0].verificationFile, plan.tracks[1].verificationFile]]
    )
  }
}

private enum ImporterTestError: Error {
  case readTimedOut
}

private actor MusicAppRecorder {
  private var albumReads: [[ImportedTrackRef]]
  private var lastRead: [ImportedTrackRef] = []
  private var dropped: [DroppedBatch] = []
  private var reads = 0

  init(albumReads: [[ImportedTrackRef]]) {
    self.albumReads = albumReads
  }

  func readAlbumTracks(_ request: MusicAlbumReadRequest) -> [ImportedTrackRef] {
    _ = request
    reads += 1
    guard !albumReads.isEmpty else {
      return lastRead
    }
    lastRead = albumReads.removeFirst()
    return lastRead
  }

  func importViaWatchFolder(_ urls: [URL], _ folder: URL) {
    dropped.append(DroppedBatch(urls: urls, folder: folder))
  }

  func droppedFiles() -> [DroppedBatch] {
    dropped
  }

  func readCount() -> Int {
    reads
  }
}

private struct DroppedBatch: Equatable, Sendable {
  var urls: [URL]
  var folder: URL
}

private func makeMultiTrackConversionPlan() -> ConversionPlan {
  let showPlan = makeShowPlan(
    files: [
      makeAudioFile(id: UUID(1), name: "01.mp3", format: .mp3, sortKey: "01.mp3"),
      makeAudioFile(id: UUID(2), name: "02.mp3", format: .mp3, sortKey: "02.mp3"),
    ],
    trackTitles: ["The Way It Is", "Mandolin Rain"]
  )
  return ConversionPlan(
    applyPlan: ApplyPlan(showPlan: showPlan, showRoot: applyShowRoot, coverURL: nil)
  )
}

private func libraryRef(for track: ConversionTrackPlan) -> ImportedTrackRef {
  ImportedTrackRef(
    id: "music-\(track.tags.trackNumber ?? 0)",
    title: track.tags.title,
    album: track.tags.album,
    trackNumber: track.tags.trackNumber,
    durationSeconds: 12,
    location: track.verificationFile
  )
}
