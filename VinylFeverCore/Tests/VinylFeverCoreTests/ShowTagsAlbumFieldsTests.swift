import CustomDump
import Testing
@testable import VinylFeverCore

@Suite struct ShowTagsAlbumFieldsTests {
  @Test
  func fillsUnknownFieldsFromLiveShowAlbumTitle() {
    let tags = ShowTags(album: .value("2026-02-27: Chicago, IL - Sleeping Village"))

    expectNoDifference(
      tags.fillingFieldsFromAlbum(),
      ShowTags(
        album: .value("2026-02-27: Chicago, IL - Sleeping Village"),
        date: .iso(year: 2026, month: 2, day: 27),
        venue: .value("Sleeping Village"),
        location: .value("Chicago, IL")
      )
    )
  }

  @Test
  func stripsTrailingSourceAndQualifierGroups() {
    let tags = ShowTags(
      album: .value("1997-04-08: Torino, Italy - Teatro Colosseo (1st Set) (SBD)")
    )

    expectNoDifference(
      tags.fillingFieldsFromAlbum().venue,
      .value("Teatro Colosseo")
    )
  }

  @Test
  func keepsDashesInsideVenueAfterFirstSeparator() {
    let tags = ShowTags(
      album: .value("2026-02-27: Chicago, IL - Sleeping Village - Back Room")
    )

    expectNoDifference(
      tags.fillingFieldsFromAlbum().venue,
      .value("Sleeping Village - Back Room")
    )
  }

  @Test
  func preservesKnownFieldsAndSource() {
    let tags = ShowTags(
      album: .value("2026-02-27: Chicago, IL - Sleeping Village (SBD)"),
      date: .iso(year: 2026, month: 2, day: 28),
      venue: .value("The Metro"),
      source: .value("FM")
    )

    expectNoDifference(
      tags.fillingFieldsFromAlbum(),
      ShowTags(
        album: tags.album,
        date: .iso(year: 2026, month: 2, day: 28),
        venue: .value("The Metro"),
        location: .value("Chicago, IL"),
        source: .value("FM")
      )
    )
  }

  @Test(arguments: [
    "Unknown Date: Unknown City - Unknown Venue (unknown)",
    "2026-13-40: Chicago, IL - Sleeping Village",
    "Christmas & Fan Club Singles (Compilation)",
    "Dave Hause - Live from Chicago",
  ])
  func doesNotFillFromInvalidOrPlaceholderTitle(_ album: String) {
    let result = ShowTags(album: .value(album)).fillingFieldsFromAlbum()
    expectNoDifference(result.date, .unknown)
    expectNoDifference(result.venue, .unknown)
    expectNoDifference(result.location, .unknown)
  }

  @Test
  func placeholdersAndEmptyComponentsDoNotFillThoseFields() {
    let placeholder = ShowTags(
      album: .value("2026-02-27: Unknown City - Unknown Venue")
    ).fillingFieldsFromAlbum()
    expectNoDifference(placeholder.date, .iso(year: 2026, month: 2, day: 27))
    expectNoDifference(placeholder.location, .unknown)
    expectNoDifference(placeholder.venue, .unknown)

    let emptyLocation = ShowTags(
      album: .value("2026-02-27:    - Sleeping Village")
    ).fillingFieldsFromAlbum()
    expectNoDifference(emptyLocation.date, .iso(year: 2026, month: 2, day: 27))
    expectNoDifference(emptyLocation.location, .unknown)
    expectNoDifference(emptyLocation.venue, .value("Sleeping Village"))

    let emptyVenue = ShowTags(
      album: .value("2026-02-27: Chicago, IL -   ")
    ).fillingFieldsFromAlbum()
    expectNoDifference(emptyVenue.date, .iso(year: 2026, month: 2, day: 27))
    expectNoDifference(emptyVenue.location, .value("Chicago, IL"))
    expectNoDifference(emptyVenue.venue, .unknown)
  }
}
