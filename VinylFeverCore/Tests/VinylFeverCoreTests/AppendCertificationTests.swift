import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct AppendCertificationTests {
  private let identity = AlbumIdentity(album: "Great Covers", albumArtist: "Jon Phillips")

  @Test
  func certifiesCleanMergeWhenExactAlbumCountIncreasesByAddedTracks() {
    let pre = [
      libraryTrack(id: "before-1", album: "Great Covers", albumArtist: "Jon Phillips"),
      libraryTrack(id: "before-2", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]
    let post = pre + [
      libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
      libraryTrack(id: "after-2", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]

    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: identity,
        preImportTracks: pre,
        postImportTracks: post,
        addedTrackCount: 2
      ),
      .merged
    )
  }

  @Test
  func comparatorNormalizesSeededIdentityTheSameWayAsImportedRefs() {
    let rawIdentity = AlbumIdentity(album: "  Great Covers  ", albumArtist: "  Jon Phillips  ")
    let pre = [
      libraryTrack(id: "before-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]
    let post = pre + [
      libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]

    expectNoDifference(
      AppendCertificationComparator.exactMatches(identity: rawIdentity, in: pre).count,
      1
    )
    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: rawIdentity,
        preImportTracks: pre,
        postImportTracks: post,
        addedTrackCount: 1
      ),
      .merged
    )
  }

  @Test
  func reportsAlbumNotFoundWhenExactIdentityDoesNotExistBeforeImport() {
    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: identity,
        preImportTracks: [],
        postImportTracks: [
          libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
        ],
        addedTrackCount: 1
      ),
      .albumNotFound
    )
  }

  @Test
  func reportsDuplicateSpawnWhenNearIdenticalSiblingAppears() {
    let pre = [
      libraryTrack(id: "before-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]
    let post = pre + [
      libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
      libraryTrack(id: "duplicate-1", album: "Great Covers 2", albumArtist: "Artist A"),
    ]

    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: identity,
        preImportTracks: pre,
        postImportTracks: post,
        addedTrackCount: 1
      ),
      .duplicateSpawned(otherTitle: "Great Covers 2")
    )
  }

  @Test
  func reportsCountMismatchWhenAlbumGrowthIsShort() {
    let pre = [
      libraryTrack(id: "before-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]
    let post = pre + [
      libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]

    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: identity,
        preImportTracks: pre,
        postImportTracks: post,
        addedTrackCount: 2
      ),
      .countMismatch(expected: 3, actual: 2)
    )
  }

  @Test
  func reportsCountMismatchWhenAlbumGrowthIsOver() {
    let pre = [
      libraryTrack(id: "before-1", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]
    let post = pre + [
      libraryTrack(id: "after-1", album: "Great Covers", albumArtist: "Jon Phillips"),
      libraryTrack(id: "after-2", album: "Great Covers", albumArtist: "Jon Phillips"),
      libraryTrack(id: "after-3", album: "Great Covers", albumArtist: "Jon Phillips"),
    ]

    expectNoDifference(
      AppendCertificationComparator.verdict(
        identity: identity,
        preImportTracks: pre,
        postImportTracks: post,
        addedTrackCount: 2
      ),
      .countMismatch(expected: 3, actual: 4)
    )
  }

  @Test
  func importReducerCountsOnlyReturnedAddRefsAsImported() {
    let plan = twoTrackConversionPlan()

    let tracks = CompilationImportReducer.importedTracks(
      plan: plan,
      addedRefs: [
        ImportedTrackRef(id: "music-1", location: plan.tracks[0].verificationFile),
      ]
    )

    expectNoDifference(tracks.map(\.status), [.imported, .alreadyPresent])
    expectNoDifference(tracks.count { $0.status == .imported }, 1)
  }

  @Test
  func importReducerMatchesReturnedAddRefsByLocationBeforeOrder() {
    let plan = twoTrackConversionPlan()

    let tracks = CompilationImportReducer.importedTracks(
      plan: plan,
      addedRefs: [
        ImportedTrackRef(id: "music-2", location: plan.tracks[1].verificationFile),
        ImportedTrackRef(id: "music-1", location: plan.tracks[0].verificationFile),
      ]
    )

    expectNoDifference(tracks.map { $0.libraryRef?.id }, ["music-1", "music-2"])
    expectNoDifference(tracks.map(\.status), [.imported, .imported])
  }
}

private func libraryTrack(id: String, album: String, albumArtist: String) -> ImportedTrackRef {
  ImportedTrackRef(
    id: id,
    title: id,
    album: album,
    albumArtist: albumArtist
  )
}

private func twoTrackConversionPlan() -> ConversionPlan {
  let files = [
    makeAudioFile(id: UUID(1), name: "01.mp3", format: .mp3, sortKey: "01.mp3"),
    makeAudioFile(id: UUID(2), name: "02.mp3", format: .mp3, sortKey: "02.mp3"),
  ]
  let showPlan = makeShowPlan(files: files, trackTitles: ["Song A", "Song B"])
  return ConversionPlan(
    applyPlan: ApplyPlan(showPlan: showPlan, showRoot: applyShowRoot, coverURL: nil)
  )
}
