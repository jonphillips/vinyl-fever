import CustomDump
import Testing
@testable import VinylFeverCore

@Suite struct ShowMetadataTests {
  @Test
  func formatsLiveShowAlbumTitleWithSource() {
    let metadata = ShowMetadata(
      tags: ShowTags(
        artist: .value("Bruce Hornsby and The Range"),
        albumArtist: .value("Bruce Hornsby"),
        date: .iso(year: 1996, month: 5, day: 21),
        venue: .value("Pearl Street Grill"),
        location: .value("Northampton, MA")
      ),
      source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true)
    )

    expectNoDifference(
      metadata.albumTitle,
      "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)"
    )
    expectNoDifference(metadata.sortAlbum, metadata.albumTitle)
  }

  @Test
  func formatsUnknownLiveShowAlbumTitleFallbacks() {
    let metadata = ShowMetadata(tags: ShowTags())

    expectNoDifference(
      metadata.albumTitle,
      "Unknown Date: Unknown City - Unknown Venue (unknown)"
    )
  }

  @Test
  func formatsPartialSetQualifierBeforeSource() {
    let metadata = ShowMetadata(
      tags: ShowTags(
        date: .iso(year: 1996, month: 5, day: 21),
        venue: .value("Pearl Street Grill"),
        location: .value("Northampton, MA")
      ),
      source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true),
      albumTitleKind: .liveShow(qualifier: .value("1st Set"))
    )

    expectNoDifference(
      metadata.albumTitle,
      "1996-05-21: Northampton, MA - Pearl Street Grill (1st Set) (SBD)"
    )
  }

  @Test
  func formatsCompilationTitleWithoutDateVenueLocation() {
    let metadata = ShowMetadata(
      tags: ShowTags(
        date: .iso(year: 1988, month: 12, day: 1),
        venue: .value("Ignored Venue"),
        location: .value("Ignored City")
      ),
      source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true),
      albumTitleKind: .compilation(title: .value("Christmas & Fan Club Singles 1988-2011"))
    )

    expectNoDifference(
      metadata.albumTitle,
      "Christmas & Fan Club Singles 1988-2011 (Compilation)"
    )
  }
}
