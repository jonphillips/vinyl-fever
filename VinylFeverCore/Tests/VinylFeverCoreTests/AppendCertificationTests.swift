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
}

private func libraryTrack(id: String, album: String, albumArtist: String) -> ImportedTrackRef {
  ImportedTrackRef(
    id: id,
    title: id,
    album: album,
    albumArtist: albumArtist
  )
}
