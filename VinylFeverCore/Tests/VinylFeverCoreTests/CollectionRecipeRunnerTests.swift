import CustomDump
import Foundation
import SQLiteData
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct CollectionRecipeRunnerTests {
  private let engine = CollectionRecipeEngine()

  // MARK: - appendIfAbsent (the covers case)

  @Test
  func appendsBracketedCaptureToTitle() throws {
    let recipe = coversRecipe()
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal?.delta.title, "Hurt (Nine Inch Nails)")
    expectNoDifference(proposal?.issues, [])
    expectNoDifference(proposal?.reason, "Appended “Nine Inch Nails” to title.")
  }

  @Test
  func affixTemplateIsRuntimeConfigurable() throws {
    let recipe = coversRecipe(affixTemplate: " [{value}]")
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal?.delta.title, "Hurt [Nine Inch Nails]")
  }

  @Test
  func appendIsIdempotentWhenValueAlreadyPresent() throws {
    let recipe = coversRecipe()
    // Second run: the title already carries the artist (filename is unchanged).
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt (Nine Inch Nails)")
    )
    expectNoDifference(proposal, nil)
  }

  @Test
  func noProposalWhenPatternDoesNotMatch() throws {
    let recipe = coversRecipe()
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt.m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal, nil)
  }

  // MARK: - strip (the scrub_titles.py case, model off)

  @Test
  func stripRemovesMatchFromTargetFieldAndIsIdempotent() throws {
    let recipe = CollectionRecipe(
      id: UUID(1),
      collectionPolicyID: UUID(0),
      name: "Strip Explicit",
      pattern: #"\s*\(Explicit\)"#,
      targetField: .title,
      op: .strip
    )
    let first = try engine.run(recipe: recipe, filename: "x.m4a", current: AudioTags(title: "Song (Explicit)"))
    expectNoDifference(first?.delta.title, "Song")

    // Running again over the stripped title is a no-op.
    let second = try engine.run(recipe: recipe, filename: "x.m4a", current: AudioTags(title: "Song"))
    expectNoDifference(second, nil)
  }

  // MARK: - setIfEmpty / replace

  @Test
  func setIfEmptyFillsBlankButSkipsPopulated() throws {
    let recipe = CollectionRecipe(
      id: UUID(1),
      collectionPolicyID: UUID(0),
      name: "Stamp album artist",
      pattern: #"\[(?<value>[^\]]+)\]"#,
      targetField: .albumArtist,
      op: .setIfEmpty
    )
    let filled = try engine.run(recipe: recipe, filename: "01 [Jon Phillips].flac", current: AudioTags())
    expectNoDifference(filled?.delta.albumArtist, "Jon Phillips")

    let skipped = try engine.run(
      recipe: recipe,
      filename: "01 [Jon Phillips].flac",
      current: AudioTags(albumArtist: "Someone Else")
    )
    expectNoDifference(skipped, nil)
  }

  @Test
  func replaceOverwritesUnlessUnchanged() throws {
    let recipe = CollectionRecipe(
      id: UUID(1),
      collectionPolicyID: UUID(0),
      name: "Force title",
      pattern: #"\[(?<value>[^\]]+)\]"#,
      targetField: .title,
      op: .replace
    )
    let changed = try engine.run(recipe: recipe, filename: "[Real Title].m4a", current: AudioTags(title: "Old"))
    expectNoDifference(changed?.delta.title, "Real Title")

    let noop = try engine.run(recipe: recipe, filename: "[Real Title].m4a", current: AudioTags(title: "Real Title"))
    expectNoDifference(noop, nil)
  }

  @Test
  func nonStringTargetFieldIsUnsupported() throws {
    let recipe = coversRecipe(targetField: .trackNumber)
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal, nil)
  }

  @Test
  func disabledRecipeProposesNothing() throws {
    let recipe = coversRecipe(enabled: false)
    let proposal = try engine.run(
      recipe: recipe,
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal, nil)
  }

  // MARK: - The verbatim guard (shared with the setlist evidence check)

  @Test
  func verbatimGuardAcceptsPresentAndRejectsAbsentValues() {
    let filename = "Hurt [Nine Inch Nails].m4a"
    // Case- and spacing-insensitive, so a real capture passes.
    #expect(TextEvidence.appears("nine   inch nails", in: filename))
    // An invented value the model might return is rejected → RecipeIssue.valueNotInFilename.
    #expect(!TextEvidence.appears("Johnny Cash", in: filename))
  }

  // MARK: - Persistence + FK cascade

  @Test
  func recipesPersistRoundTripAndCascadeOnPolicyDelete() throws {
    let database = try VinylFeverDatabase.open(path: temporaryDatabasePath())
    let policy = CollectionPolicy(id: UUID(1), name: "Great Covers", details: "Cover songs")
    let recipe = CollectionRecipe(
      id: UUID(2),
      collectionPolicyID: policy.id,
      name: "Cover artist → title",
      pattern: #"\[(?<value>[^\]]+)\]"#,
      targetField: .album,
      op: .strip,
      affixTemplate: " [{value}]"
    )

    try database.write { db in
      try CollectionPolicy.upsert { policy }.execute(db)
      try CollectionRecipe.upsert { recipe }.execute(db)
    }

    // Enum-typed columns (targetField/op) round-trip as text.
    let persisted = try database.read { db in try CollectionRecipe.all.fetchAll(db) }
    expectNoDifference(persisted, [recipe])

    // Deleting the policy cascades to its recipes.
    try database.write { db in
      try CollectionPolicy.find(policy.id).delete().execute(db)
    }
    let afterCascade = try database.read { db in try CollectionRecipe.all.fetchAll(db) }
    expectNoDifference(afterCascade, [])
  }

  // MARK: - Helpers

  private func coversRecipe(
    targetField: ProposedTags.Field = .title,
    op: CollectionRecipe.Op = .appendIfAbsent,
    affixTemplate: String = " ({value})",
    enabled: Bool = true
  ) -> CollectionRecipe {
    CollectionRecipe(
      id: UUID(1),
      collectionPolicyID: UUID(0),
      name: "Cover artist → title",
      pattern: #"\[(?<value>[^\]]+)\]"#,
      targetField: targetField,
      op: op,
      affixTemplate: affixTemplate,
      enabled: enabled
    )
  }
}

private func temporaryDatabasePath() throws -> String {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("VinylFever.sqlite").path(percentEncoded: false)
}
