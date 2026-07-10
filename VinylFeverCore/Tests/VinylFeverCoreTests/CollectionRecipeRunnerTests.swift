import CustomDump
import Foundation
import LLMClientKit
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

  // MARK: - The model classify stage (S2)

  /// The covers acceptance case: an on-device model keeps a real cover artist and
  /// rejects a `[Live]`/`[Remaster]` annotation carried by the same bracket pattern.
  @Test
  func modelClassifiesCoverArtistApplyAndRejectsAnnotations() async throws {
    let runner = coversModelRunner()

    let applied = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(applied?.delta.title, "Hurt (Nine Inch Nails)")
    expectNoDifference(applied?.issues, [])
    expectNoDifference(applied?.reason, "Nine Inch Nails is the original artist.")

    // `[Live]` matches the same pattern but the model rejects it → no proposal.
    let rejected = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Live].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(rejected, nil)
  }

  /// A hallucinated value the model returns is caught by stage 3's verbatim guard and
  /// forced into review — never silently applied.
  @Test
  func hallucinatedModelValueIsFlaggedForReview() async throws {
    let runner = runner(returning: #"{"apply": true, "value": "Johnny Cash", "reason": "guess"}"#)
    let proposal = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal?.issues, [.valueNotInFilename])
  }

  /// An unparseable response degrades to the deterministic candidate, flagged so it is
  /// preview-gated and cannot land on disk.
  @Test
  func unparseableModelOutputDegradesToFlaggedReview() async throws {
    let runner = runner(returning: "sorry, I can't help with that")
    let proposal = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    // The deterministic candidate is surfaced so the human sees what would happen…
    expectNoDifference(proposal?.delta.title, "Hurt (Nine Inch Nails)")
    // …but flagged, so the apply path excludes it.
    expectNoDifference(proposal?.issues, [.modelOutputUnparseable])
  }

  /// A model-on run is idempotent: the second pass over an already-stamped title is a
  /// no-op even though the model would still say "apply".
  @Test
  func modelPathIsIdempotent() async throws {
    let runner = coversModelRunner()
    let proposal = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt (Nine Inch Nails)")
    )
    expectNoDifference(proposal, nil)
  }

  /// `apply: true` with no `value` falls back to the captured candidate rather than
  /// failing — the candidate is in the filename by construction, so it stays clean.
  @Test
  func modelApplyWithoutValueFallsBackToCandidate() async throws {
    let runner = runner(returning: #"{"apply": true}"#)
    let proposal = try await runner.run(
      recipe: coversModelRecipe(),
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal?.delta.title, "Hurt (Nine Inch Nails)")
    expectNoDifference(proposal?.issues, [])
  }

  /// A model-off recipe never reaches the model — the deterministic engine handles it,
  /// even though the runner has a `ModelClient` in hand.
  @Test
  func modelOffRecipeNeverCallsTheModel() async throws {
    let runner = LiveCollectionRecipeRunner(
      modelClient: StubModelClient { _ in
        Issue.record("model-off recipe must not call the model")
        return ModelResponse(text: "")
      }
    )
    let proposal = try await runner.run(
      recipe: coversRecipe(), // useModel defaults to false
      filename: "Hurt [Nine Inch Nails].m4a",
      current: AudioTags(title: "Hurt")
    )
    expectNoDifference(proposal?.delta.title, "Hurt (Nine Inch Nails)")
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

  /// The covers recipe with the model classify stage turned on.
  private func coversModelRecipe() -> CollectionRecipe {
    var recipe = coversRecipe()
    recipe.useModel = true
    recipe.prompt = "Keep the bracketed original artist; reject Live/Remaster annotations."
    return recipe
  }

  /// A runner whose model always returns `text`.
  private func runner(returning text: String) -> LiveCollectionRecipeRunner {
    LiveCollectionRecipeRunner(modelClient: StubModelClient.constant(text))
  }

  /// A runner whose stub reads the candidate out of the user prompt and rejects
  /// `[Live]`/`[Remaster]` annotations, standing in for the on-device covers classifier.
  private func coversModelRunner() -> LiveCollectionRecipeRunner {
    LiveCollectionRecipeRunner(modelClient: StubModelClient { request in
      let prompt = request.messages.last { $0.role == .user }?.text ?? ""
      let candidate = prompt
        .split(separator: "\n")
        .last { !$0.isEmpty && !$0.hasPrefix("Decide") }
        .map(String.init) ?? ""
      let annotations = ["Live", "Remaster", "Remastered", "Demo"]
      if annotations.contains(where: { candidate.localizedCaseInsensitiveContains($0) }) {
        return ModelResponse(text: #"{"apply": false, "value": "", "reason": "annotation, not an artist"}"#)
      }
      return ModelResponse(
        text: #"{"apply": true, "value": "\#(candidate)", "reason": "\#(candidate) is the original artist."}"#
      )
    })
  }
}

private func temporaryDatabasePath() throws -> String {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("VinylFever.sqlite").path(percentEncoded: false)
}
