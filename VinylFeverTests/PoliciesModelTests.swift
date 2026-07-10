import Dependencies
import Foundation
import SQLiteData
import Testing
import VinylFeverCore

@testable import VinylFever

/// Covers the M7 S1 recipe workbench wiring on `AppModel`: `buildRecipeSample`
/// (proposals collected, issue items flagged) and the apply path (issue items
/// excluded, single-field delta lands). Uses the injected `collectionRecipeRunner`
/// plus fake file/metadata clients — the engine and write rail are tested in core.
@MainActor
@Suite
struct PoliciesModelTests {
  // MARK: - buildRecipeSample

  @Test
  func collectsProposalsAndFlagsIssues() async {
    let fileA = Self.file(1, "a.flac")
    let fileB = Self.file(2, "b.flac")
    let fileC = Self.file(3, "c.flac") // the recipe returns no proposal for this one

    let model = withDependencies {
      $0.fileSystemClient.scanAudioFolder = { _ in [fileA, fileB, fileC] }
      $0.audioMetadataClient.read = { _ in AudioTags(title: "Song") }
      $0.collectionRecipeRunner.run = { _, filename, _ in
        switch filename {
        case "a.flac":
          RecipeProposal(delta: .delta("Song (Live)", for: .title), reason: "append")
        case "b.flac":
          RecipeProposal(
            delta: .delta("Song [x]", for: .title),
            reason: "append",
            issues: [.valueNotInFilename]
          )
        default:
          nil
        }
      }
    } operation: {
      AppModel()
    }

    await model.buildRecipeSample(recipe: Self.recipe(), folder: URL(filePath: "/tmp/folder"))

    // Only the two files that produced a proposal appear; the third is dropped.
    #expect(model.recipeSampleItems.map(\.id) == [fileA.id, fileB.id])
    // The proposal's issues surface as a review flag.
    #expect(model.recipeSampleItems.first { $0.hasIssues }?.id == fileB.id)
    // Display strings are computed off the recipe's target field.
    #expect(model.recipeSampleItems.first?.current == "Song")
    #expect(model.recipeSampleItems.first?.proposed == "Song (Live)")
    #expect(model.recipeSampleState == .completed(scanned: 3, proposed: 2))
  }

  @Test
  func skipsFilesThatFailToRead() async {
    let good = Self.file(1, "good.flac")
    let bad = Self.file(2, "bad.flac")

    let model = withDependencies {
      $0.fileSystemClient.scanAudioFolder = { _ in [good, bad] }
      $0.audioMetadataClient.read = { request in
        if request.url.lastPathComponent == "bad.flac" {
          struct Unreadable: Error {}
          throw Unreadable()
        }
        return AudioTags(title: "Song")
      }
      $0.collectionRecipeRunner.run = { _, _, _ in
        RecipeProposal(delta: .delta("Song (Live)", for: .title), reason: "append")
      }
    } operation: {
      AppModel()
    }

    await model.buildRecipeSample(recipe: Self.recipe(), folder: URL(filePath: "/tmp/folder"))

    #expect(model.recipeSampleItems.map(\.id) == [good.id])
    #expect(model.recipeSampleState == .completed(scanned: 2, proposed: 1))
  }

  // MARK: - Apply

  @Test
  func applyExcludesIssueItems() async {
    let model = AppModel()
    model.recipeSampleFolder = URL(filePath: "/tmp/folder")
    // Every item is flagged, so nothing is applicable and the executor never runs.
    model.recipeSampleItems = [
      Self.item(1, "a.flac", proposed: "Song [x]", issues: [.valueNotInFilename])
    ]

    await model.applyRecipePlan()

    #expect(model.recipeApplyState == .idle)
  }

  @Test
  func planCarriesSingleFieldDeltaForApplicableItemsOnly() {
    let clean = Self.item(1, "a.flac", proposed: "Song (Live)")
    let flagged = Self.item(2, "b.flac", proposed: "Song [x]", issues: [.valueNotInFilename])
    let folder = URL(filePath: "/tmp/folder")

    // Mirror what `applyRecipePlan` feeds the builder.
    let applicable = [clean, flagged].filter { !$0.hasIssues }
    let plan = AppModel.recipeApplyPlan(from: applicable, folder: folder)

    let plan1 = try! #require(plan)
    #expect(plan1.tracks.map(\.id) == [clean.id])
    // Exactly the one target field is set — every other field stays nil.
    #expect(plan1.tracks.first?.tags == ProposedTags.delta("Song (Live)", for: .title))
    // The write rail's copy → writeTags pair, one per track.
    #expect(plan1.operations.count == 2)
    #expect(plan1.tracks.first?.workingFile
      == folder.appendingPathComponent("Working", isDirectory: true)
      .appendingPathComponent("a.flac"))
  }

  @Test
  func emptyApplicableSetYieldsNoPlan() {
    #expect(AppModel.recipeApplyPlan(from: [], folder: URL(filePath: "/tmp/folder")) == nil)
  }

  // MARK: - Compilation append binding

  @Test
  func boundAppendFusesEnabledRecipeDeltasAndExcludesIssueDeltasFromApply() async throws {
    let database = try VinylFeverDatabase.open(path: Self.temporaryDatabasePath())
    let policy = CollectionPolicy(id: UUID(20), name: "Covers")
    let cleanRecipe = CollectionRecipe(
      id: UUID(21),
      collectionPolicyID: policy.id,
      name: "Title rewrite",
      pattern: "",
      targetField: .title
    )
    let flaggedRecipe = CollectionRecipe(
      id: UUID(22),
      collectionPolicyID: policy.id,
      name: "Sort album rewrite",
      pattern: "",
      targetField: .sortAlbum
    )
    let disabledRecipe = CollectionRecipe(
      id: UUID(23),
      collectionPolicyID: policy.id,
      name: "Disabled recipe",
      pattern: "",
      targetField: .artist,
      enabled: false
    )
    try await database.write { db in
      try CollectionPolicy.upsert { policy }.execute(db)
      try CollectionRecipe.upsert { cleanRecipe }.execute(db)
      try CollectionRecipe.upsert { flaggedRecipe }.execute(db)
      try CollectionRecipe.upsert { disabledRecipe }.execute(db)
    }

    let file = Self.file(10, "song.flac")
    let entry = CompilationAlbum(
      id: UUID(24),
      name: "Covers",
      identity: AlbumIdentity(album: "Covers", albumArtist: "Various Artists"),
      collectionPolicyID: policy.id
    )
    let model = withDependencies {
      $0.defaultDatabase = database
      $0.fileSystemClient.scanAudioFolder = { _ in [file] }
      $0.audioMetadataClient.read = { _ in
        AudioTags(title: "Song", sortAlbum: "Original")
      }
      $0.collectionRecipeRunner.run = { recipe, _, _ in
        switch recipe.id {
        case cleanRecipe.id:
          RecipeProposal(
            delta: .delta("Song (Live)", for: .title),
            reason: "title rewrite"
          )
        case flaggedRecipe.id:
          RecipeProposal(
            delta: .delta("Flagged Sort", for: .sortAlbum),
            reason: "sort rewrite",
            issues: [.valueNotInFilename]
          )
        default:
          // If the disabled recipe were accidentally loaded, this would make the
          // regression visible in the resulting plan.
          RecipeProposal(
            delta: .delta("Disabled", for: .artist),
            reason: "disabled recipe"
          )
        }
      }
    } operation: {
      AppModel()
    }

    await model.buildCompilationAppendPlan(entry: entry, sourceFolder: URL(filePath: "/tmp/folder"))

    let plan = try #require(model.compilationApplyPlan)
    let track = try #require(plan.tracks.first)
    #expect(track.proposed.title == "Song (Live)")
    #expect(track.proposed.artist == nil)
    #expect(track.proposed.sortAlbum == nil)
    #expect(model.compilationRecipeProposalsByFileID[file.id]?.count == 2)
    #expect(model.compilationRecipeProposalsByFileID[file.id]?.contains { !$0.proposal.issues.isEmpty } == true)

    let applyPlan = ApplyPlan(compilationPlan: plan)
    #expect(applyPlan.tracks.first?.tags.title == "Song (Live)")
    #expect(applyPlan.tracks.first?.tags.sortAlbum == nil)
  }

  @Test
  func unboundAppendPlanIsUnchangedAndDoesNotRunRecipes() async throws {
    let file = Self.file(30, "song.flac")
    let entry = CompilationAlbum(
      id: UUID(31),
      name: "Covers",
      identity: AlbumIdentity(album: "Covers", albumArtist: "Various Artists")
    )
    let current = AudioTags(title: "Song", album: "Original", sortAlbum: "Original")
    let folder = URL(filePath: "/tmp/unbound-folder")
    let model = withDependencies {
      $0.fileSystemClient.scanAudioFolder = { _ in [file] }
      $0.audioMetadataClient.read = { _ in current }
      $0.collectionRecipeRunner.run = { _, _, _ in
        RecipeProposal(delta: .delta("Must not run", for: .title), reason: "unexpected")
      }
    } operation: {
      AppModel()
    }

    await model.buildCompilationAppendPlan(entry: entry, sourceFolder: folder)

    let expected = CompilationApplyPlan(
      entry: entry,
      sourceRoot: folder,
      files: [file],
      currentTagsByFileID: [file.id: current]
    )
    #expect(model.compilationApplyPlan == expected)
    #expect(model.compilationRecipeProposalsByFileID.isEmpty)
  }

  // MARK: - Fixtures

  private static func file(_ n: Int, _ name: String) -> ScannedAudioFile {
    ScannedAudioFile(
      id: UUID(n),
      url: URL(filePath: "/tmp/folder/\(name)"),
      format: .flac,
      sortKey: name
    )
  }

  private static func recipe() -> CollectionRecipe {
    CollectionRecipe(
      id: UUID(9),
      collectionPolicyID: UUID(0),
      name: "Covers",
      pattern: #"\[(?<value>[^\]]+)\]"#,
      targetField: .title
    )
  }

  private static func item(
    _ n: Int,
    _ name: String,
    proposed: String,
    issues: [RecipeIssue] = []
  ) -> RecipeSampleItem {
    RecipeSampleItem(
      file: file(n, name),
      currentTags: AudioTags(title: "Song"),
      proposal: RecipeProposal(delta: .delta(proposed, for: .title), reason: "append", issues: issues),
      fieldLabel: "Title",
      current: "Song",
      proposed: proposed
    )
  }

  private static func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("vinyl-fever-m8-s1-\(UUID().uuidString).sqlite")
      .path
  }
}
