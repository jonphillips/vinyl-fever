import Foundation

/// Combines the collection's authoritative stamping delta with recipe deltas for
/// one file. Collection identity wins; recipes contribute the fields that belong
/// to the track and grouping accumulates tokens from both sources.
public enum RecipeTagMerge {
  public static func merge(
    compilation: ProposedTags,
    recipes: [ProposedTags]
  ) -> ProposedTags {
    var merged = compilation

    for recipe in recipes {
      // Recipes may enrich track metadata, but never replace the collection's
      // album identity or its structural compilation fields.
      if let title = recipe.title {
        merged.title = title
      }
      if let sortAlbum = recipe.sortAlbum {
        merged.sortAlbum = sortAlbum
      }
      if let artist = recipe.artist {
        merged.artist = artist
      }
      if let grouping = recipe.grouping {
        merged.grouping = CompilationApplyPlan.mergedGrouping(
          existing: merged.grouping,
          addedTokens: grouping.components(separatedBy: CompilationRuleset.groupingDelimiter)
        )
      }

      merged.clearedFields.formUnion(recipe.clearedFields)
    }

    // Identity is deliberately restored after the recipe pass. This also makes
    // the precedence explicit if a future recipe producer emits album fields.
    merged.album = compilation.album
    merged.albumArtist = compilation.albumArtist
    merged.isCompilation = compilation.isCompilation
    merged.trackNumber = compilation.trackNumber
    merged.trackTotal = compilation.trackTotal
    merged.discNumber = compilation.discNumber

    // Recipe producers cannot override the collection's identity or structural
    // values, so their cleared-field membership must not override those fields
    // either. Keep recipe clears for any future recipe-owned fields.
    let collectionOwnedFields: Set<ProposedTags.Field> = [
      .album, .albumArtist, .isCompilation, .trackNumber, .trackTotal, .discNumber,
    ]
    merged.clearedFields.subtract(collectionOwnedFields)
    merged.clearedFields.formUnion(compilation.clearedFields.intersection(collectionOwnedFields))

    return merged
  }
}
