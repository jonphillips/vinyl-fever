import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct SetlistTextTests {
  @Test
  func composesAlbumLineFromComponents() {
    let tags = ShowTags(
      date: .iso(year: 1996, month: 5, day: 21),
      venue: .value("Pearl Street Grill"),
      location: .value("Northampton, MA"),
      source: .value("SBD")
    )
    expectNoDifference(
      SetlistText.composedAlbum(tags),
      "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)"
    )
  }

  @Test
  func composesAlbumWithDocumentedUnknownFallbacks() {
    expectNoDifference(
      SetlistText.composedAlbum(ShowTags()),
      "Unknown Date: Unknown City - Unknown Venue (unknown)"
    )
  }

  @Test
  func explicitAlbumOverridesComposition() {
    let tags = ShowTags(album: .value("Christmas & Fan Club Singles 1988-2011 (Compilation)"))
    expectNoDifference(
      SetlistText.composedAlbum(tags),
      "Christmas & Fan Club Singles 1988-2011 (Compilation)"
    )
  }

  @Test
  func rendersCanonicalSetlistFile() {
    let draft = SetlistDraft(
      tags: ShowTags(
        artist: .value("Bruce Hornsby and The Range"),
        albumArtist: .value("Bruce Hornsby"),
        date: .iso(year: 1996, month: 5, day: 21),
        venue: .value("Pearl Street Grill"),
        location: .value("Northampton, MA"),
        source: .value("SBD")
      ),
      tracks: [
        SetlistTrack(id: UUID(1), title: "The Way It Is"),
        SetlistTrack(id: UUID(2), title: "Mandolin Rain", note: "> segue"),
      ]
    )

    expectNoDifference(
      SetlistText.render(draft),
      """
      ARTIST: Bruce Hornsby and The Range
      ALBUM: 1996-05-21: Northampton, MA - Pearl Street Grill (SBD)
      ALBUMARTIST: Bruce Hornsby
      DATE: 1996-05-21
      VENUE: Pearl Street Grill
      LOCATION: Northampton, MA

      The Way It Is
      Mandolin Rain

      """
    )
  }
}
