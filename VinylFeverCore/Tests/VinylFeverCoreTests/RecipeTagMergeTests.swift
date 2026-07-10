import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

struct RecipeTagMergeTests {
  @Test
  func collectionOwnsIdentityAndRecipesOwnTrackFields() {
    let compilation = ProposedTags(
      album: "Great Covers",
      albumArtist: "Various Artists",
      grouping: "Collection",
      isCompilation: true,
      trackNumber: nil,
      trackTotal: nil,
      discNumber: nil,
      clearedFields: [.isCompilation, .trackNumber, .trackTotal, .discNumber]
    )
    let recipe = ProposedTags(
      title: "Hurt (Nine Inch Nails)",
      album: "Recipe Album",
      sortAlbum: "Hurt",
      artist: "Nine Inch Nails",
      albumArtist: "Recipe Artist",
      grouping: "Covers | 1990s",
      isCompilation: false,
      trackNumber: 7,
      clearedFields: [.album]
    )

    let merged = RecipeTagMerge.merge(compilation: compilation, recipes: [recipe])

    expectNoDifference(merged.album, "Great Covers")
    expectNoDifference(merged.albumArtist, "Various Artists")
    expectNoDifference(merged.title, "Hurt (Nine Inch Nails)")
    expectNoDifference(merged.sortAlbum, "Hurt")
    expectNoDifference(merged.artist, "Nine Inch Nails")
    expectNoDifference(merged.grouping, "Collection | Covers | 1990s")
    expectNoDifference(merged.isCompilation, true)
    expectNoDifference(merged.trackNumber, nil)
    expectNoDifference(merged.clearedFields, [.isCompilation, .trackNumber, .trackTotal, .discNumber])
  }

  @Test
  func groupingUnionIsCaseInsensitiveAndIdempotent() {
    let compilation = ProposedTags(grouping: "Collection | Covers")
    let recipe = ProposedTags(grouping: "covers | 1990s")

    let once = RecipeTagMerge.merge(compilation: compilation, recipes: [recipe])
    let twice = RecipeTagMerge.merge(compilation: once, recipes: [recipe])

    expectNoDifference(once.grouping, "Collection | Covers | 1990s")
    expectNoDifference(twice, once)
  }
}
