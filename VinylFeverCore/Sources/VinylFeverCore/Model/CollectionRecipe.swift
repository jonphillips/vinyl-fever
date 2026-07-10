import Foundation
import SQLiteData

/// A small, user-authored, per-collection rule that proposes a metadata edit from
/// evidence on a file (its filename, or the target field itself). Full design in
/// `docs/collection-recipes.md`. This is the S0 (model-off) shape: a deterministic
/// regex rule. The `useModel`/`prompt` columns exist now but are inert until the
/// S2 classify stage reads them.
///
/// `op` decides where the pattern looks:
/// - `appendIfAbsent` / `setIfEmpty` / `replace`: the pattern matches the
///   **filename**; its named capture (`captureName`) is the value written to
///   `targetField`.
/// - `strip`: the pattern matches the **current `targetField` value**; every match
///   is removed from it (the `scripts/python/scrub_titles.py` case).
@Table
public struct CollectionRecipe: Equatable, Identifiable, Sendable {
  public let id: UUID
  /// FK to the owning policy. `ON DELETE CASCADE` in the schema — a recipe never
  /// outlives its policy.
  public var collectionPolicyID: CollectionPolicy.ID
  public var name: String
  /// Regex source. Its role (filename vs. target field) is set by `op`; see above.
  public var pattern: String
  /// Named capture the capture-ops read, e.g. `value` for `#"\[(?<value>[^\]]+)\]"#`.
  public var captureName: String
  /// The tag field the recipe edits. Reuses the write rail's own field vocabulary
  /// so there is no translation layer to `ProposedTags`.
  public var targetField: ProposedTags.Field
  public var op: Op
  /// How `appendIfAbsent` wraps the captured value. `{value}` is substituted
  /// deterministically, so container symbols (`(…)`, `[…]`, `feat. …`) are recipe
  /// data — authored once and frozen — never a per-file model decision.
  public var affixTemplate: String
  public var useModel: Bool
  public var prompt: String
  public var enabled: Bool

  public init(
    id: UUID,
    collectionPolicyID: CollectionPolicy.ID,
    name: String,
    pattern: String,
    captureName: String = "value",
    targetField: ProposedTags.Field = .title,
    op: Op = .appendIfAbsent,
    affixTemplate: String = " ({value})",
    useModel: Bool = false,
    prompt: String = "",
    enabled: Bool = true
  ) {
    self.id = id
    self.collectionPolicyID = collectionPolicyID
    self.name = name
    self.pattern = pattern
    self.captureName = captureName
    self.targetField = targetField
    self.op = op
    self.affixTemplate = affixTemplate
    self.useModel = useModel
    self.prompt = prompt
    self.enabled = enabled
  }

  /// The transform a recipe applies: `(evidence, current field value) → new field
  /// value`. A deliberately closed enum — each op is auditable and fixture-testable,
  /// with no arbitrary-code path. Append is only the covers case's transform, not
  /// the shape of every recipe.
  public enum Op: String, CaseIterable, Equatable, Hashable, QueryBindable, Sendable {
    case appendIfAbsent
    case setIfEmpty
    case replace
    case strip
  }
}

/// `ProposedTags.Field` is defined in the write rail without a database
/// conformance; adding it here (same module) lets a recipe store the field
/// directly as a text column, the way `RunRecord.Kind` does.
extension ProposedTags.Field: QueryBindable {}

extension ProposedTags.Field {
  /// The subset of tag fields a recipe can read/write as free text. Non-string
  /// fields (`isCompilation`, track/disc numbers) are out of scope for recipes.
  public var isStringValued: Bool {
    switch self {
    case .title, .album, .sortAlbum, .artist, .albumArtist, .grouping:
      true
    case .comments, .isCompilation, .trackNumber, .trackTotal, .discNumber:
      false
    }
  }
}

extension AudioTags {
  /// Read the current value of a recipe's string-valued target field.
  public func stringValue(for field: ProposedTags.Field) -> String? {
    switch field {
    case .title: title
    case .album: album
    case .sortAlbum: sortAlbum
    case .artist: artist
    case .albumArtist: albumArtist
    case .grouping: grouping
    default: nil
    }
  }
}

extension ProposedTags {
  /// Set a single string-valued field, leaving every other field untouched — a
  /// recipe only ever proposes a delta on its one `targetField`.
  public static func delta(_ value: String, for field: ProposedTags.Field) -> ProposedTags {
    var tags = ProposedTags()
    switch field {
    case .title: tags.title = value
    case .album: tags.album = value
    case .sortAlbum: tags.sortAlbum = value
    case .artist: tags.artist = value
    case .albumArtist: tags.albumArtist = value
    case .grouping: tags.grouping = value
    default: break
    }
    return tags
  }
}
