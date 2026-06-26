import CustomDump
import DependenciesTestSupport
import Testing
@testable import VinylFeverCore

@Suite(
  .serialized,
  .dependency(\.uuid, .incrementing)
)
struct SetlistParserTests {
  @Test
  func parsesCanonicalSetlistTagsAndTracks() {
    let draft = SetlistParser().parse(
      """
      ARTIST: Bruce Hornsby and The Range
      ALBUM: 1996-05-21: Northampton, MA - Pearl Street Grill (SBD)
      ALBUMARTIST: Bruce Hornsby
      DATE: 1996-05-21
      VENUE: Pearl Street Grill
      LOCATION: Northampton, MA

      The Way It Is
      Mandolin Rain
      Every Little Kiss
      """
    )

    expectNoDifference(
      draft.tags,
      ShowTags(
        artist: .value("Bruce Hornsby and The Range"),
        album: .value("1996-05-21: Northampton, MA - Pearl Street Grill (SBD)"),
        albumArtist: .value("Bruce Hornsby"),
        date: .iso(year: 1996, month: 5, day: 21),
        venue: .value("Pearl Street Grill"),
        location: .value("Northampton, MA")
      )
    )
    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "The Way It Is",
        "Mandolin Rain",
        "Every Little Kiss",
      ]
    )
  }

  @Test
  func numberedTracksPreserveSegueNotationWithoutSplitting() {
    let draft = SetlistParser().parse(
      """
      12. Mandolin Rain > Brokedown Palace
      13. Rainbow's Cadillac / Franklin's Tower
      """
    )

    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "Mandolin Rain > Brokedown Palace",
        "Rainbow's Cadillac / Franklin's Tower",
      ]
    )
  }

  @Test
  func separatelyNumberedSegueTracksStaySeparate() {
    let draft = SetlistParser().parse(
      """
      01 On the Western Skyline >
      02 Not Fade Away
      """
    )

    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "On the Western Skyline >",
        "Not Fade Away",
      ]
    )
  }

  @Test
  func numberTitledPlainSongsKeepTheirLeadingNumbers() {
    let draft = SetlistParser().parse(
      """
      500 Miles
      8 Days a Week
      16 Tons
      99 Luftballons
      2-4-6-8 Motorway
      """
    )

    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "500 Miles",
        "8 Days a Week",
        "16 Tons",
        "99 Luftballons",
        "2-4-6-8 Motorway",
      ]
    )
  }

  @Test
  func stripsUnnumberedStructuralHeadersButKeepsNumberedNonSongTracks() {
    let draft = SetlistParser().parse(
      """
      Disc One
      Set 1
      01 intro
      02 The Long Race
      Encore
      03 encore
      04 band intros
      END OF PART 1
      """
    )

    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "intro",
        "The Long Race",
        "encore",
        "band intros",
      ]
    )
  }

  @Test
  func plainTrackListsUseUnknownTagFallbacks() {
    let draft = SetlistParser().parse(
      """

      Have a Little Faith in Me

      Thing Called Love
      -----
      Angel from Montgomery
      """
    )

    expectNoDifference(draft.tags, ShowTags())
    expectNoDifference(
      draft.tracks.map(\.title),
      [
        "Have a Little Faith in Me",
        "Thing Called Love",
        "Angel from Montgomery",
      ]
    )
  }

  @Test
  func invalidDateTagFallsBackToUnknown() {
    let draft = SetlistParser().parse(
      """
      DATE: May 21, 1996

      Track Title
      """
    )

    expectNoDifference(draft.tags.date, .unknown)
  }
}
