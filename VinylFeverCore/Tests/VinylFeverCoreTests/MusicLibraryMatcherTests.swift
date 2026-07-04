import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct MusicLibraryMatcherTests {
  @Test
  func resolvesByExactLocationBeforeFallbackMetadata() {
    let plan = makeConversionPlan(format: .flac)
    let track = plan.tracks[0]
    let libraryTrack = ImportedTrackRef(
      id: "MUSIC-1",
      title: "Wrong Title",
      album: "Wrong Album",
      trackNumber: 99,
      location: track.verificationFile
    )

    let result = MusicLibraryMatcher.resolve(plan: plan, libraryTracks: [libraryTrack])

    expectNoDifference(result.didResolveAll, true)
    expectNoDifference(result.resolvedCount, 1)
    expectNoDifference(result.trackResolutions[0].libraryRef, libraryTrack)
    expectNoDifference(result.trackResolutions[0].strategy, .location)
  }

  @Test
  func resolvesByAlbumTrackAndTitleWhenLocationIsMissing() {
    let plan = makeConversionPlan(format: .flac)
    let track = plan.tracks[0]
    let libraryTrack = ImportedTrackRef(
      id: "MUSIC-2",
      title: "  \(track.tags.title ?? "")  ",
      album: track.tags.album,
      trackNumber: track.tags.trackNumber
    )

    let result = MusicLibraryMatcher.resolve(plan: plan, libraryTracks: [libraryTrack])

    expectNoDifference(result.didResolveAll, true)
    expectNoDifference(result.trackResolutions[0].libraryRef, libraryTrack)
    expectNoDifference(result.trackResolutions[0].strategy, .albumTrackTitle)
  }

  @Test
  func leavesAmbiguousFallbackMatchesUnresolved() {
    let plan = makeConversionPlan(format: .flac)
    let track = plan.tracks[0]
    let libraryTracks = [
      ImportedTrackRef(
        id: "MUSIC-A",
        title: track.tags.title,
        album: track.tags.album,
        trackNumber: track.tags.trackNumber
      ),
      ImportedTrackRef(
        id: "MUSIC-B",
        title: track.tags.title,
        album: track.tags.album,
        trackNumber: track.tags.trackNumber
      ),
    ]

    let result = MusicLibraryMatcher.resolve(plan: plan, libraryTracks: libraryTracks)

    expectNoDifference(result.didResolveAll, false)
    expectNoDifference(result.trackResolutions[0].libraryRef, nil)
    expectNoDifference(result.trackResolutions[0].strategy, nil)
    expectNoDifference(
      result.trackResolutions[0].failure,
      .ambiguous(strategy: .albumTrackTitle, matches: ["MUSIC-A", "MUSIC-B"])
    )
  }

  @Test
  func leavesMissingTracksUnresolved() {
    let plan = makeConversionPlan(format: .flac)

    let result = MusicLibraryMatcher.resolve(plan: plan, libraryTracks: [])

    expectNoDifference(result.didResolveAll, false)
    expectNoDifference(result.trackResolutions[0].failure, .notFound)
  }

  @Test
  func normalizesImportedTrackReadModelValues() {
    let track = ImportedTrackRef(
      id: "  PID-1  ",
      title: "   ",
      album: "  Album Title  ",
      trackNumber: 0,
      durationSeconds: 0,
      location: URL(fileURLWithPath: "/Shows/Album/../Album/01.m4a")
    )

    expectNoDifference(track.id, "PID-1")
    expectNoDifference(track.title, nil)
    expectNoDifference(track.album, "Album Title")
    expectNoDifference(track.trackNumber, nil)
    expectNoDifference(track.durationSeconds, nil)
    expectNoDifference(track.locationPath, "/Shows/Album/01.m4a")
  }
}
