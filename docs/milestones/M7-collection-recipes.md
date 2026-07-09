# Milestone 7 — Collection Recipes

*First implementation of the [Collection Recipes](../collection-recipes.md)
design: per-collection, user-authored metadata rules that emit a `ProposedTags`
delta into the existing apply-with-preview rail. New schema (one table) and one
new `VinylFeverCore` pipeline; no change to the write rail, the preview, or the
live-show flow. Rules in [../technical-architecture.md](../technical-architecture.md),
[../metadata-policy-model.md](../metadata-policy-model.md), and
`/Users/jon/code/jon-platform/AGENTS.md` apply; where this doc and those
conflict, stop and flag it.*

## The milestone in one sentence

Let a user author a small rule per collection — a filename regex plus an optional
onboard-model classification step — that proposes a metadata edit (e.g. "append
the bracketed original-artist to the title"), runs the existing setlist
"sandwich" (deterministic extract → optional LLM judgment → deterministic
validate → always preview), and hands its `ProposedTags` delta to the
`ApplyPlan` / `writeTags` rail already in place — **shipping the deterministic,
model-off half first.**

## Why now

The compilation-album append policy and the setlist normalizer both landed, which
means the two templates this milestone clones already exist and are proven: the
`compilationAlbums` table
([Schema.swift](../../VinylFeverCore/Sources/VinylFeverCore/Database/Schema.swift))
for a small per-collection registry, and
[SetlistNormalizer.swift](../../VinylFeverCore/Sources/VinylFeverCore/Normalizing/SetlistNormalizer.swift)
for the extract→classify→validate sandwich with its degrade-to-review floor.
Critically, the anti-hallucination guard this feature needs — "the proposed value
must appear verbatim in the filename" — is already written and tested as
`SetlistNormalizationValidator.evidenceAppears(_:in:)`. The remaining ad-hoc tag
cleanup still lives as loose Python (`scripts/python/scrub_titles.py`,
`rule_scrub_tags.py`, `strip_prefix_underscore.py`); this milestone promotes that
class of rule into a first-class, previewable, per-collection app surface.

## Scope

Full design in [../collection-recipes.md](../collection-recipes.md). The moving
parts:

- **`collectionPolicies` table** (minimal: `id`, `name`, `description`) — the FK
  anchor and first concrete instance of the Collection Policy primitive.
- **`collectionRecipes` table** (SQLiteData, STRICT, cloned from
  `compilationAlbums` conventions) holding `{ collectionPolicyID (FK, cascade
  delete), name, filenamePattern, captureName, targetField, op, affixTemplate,
  useModel, prompt, enabled }`.
- **`CollectionRecipe`** model; `targetField` is the existing
  [`ProposedTags.Field`](../../VinylFeverCore/Sources/VinylFeverCore/Model/ShowPlan.swift)
  so there is no translation layer to the write rail.
- **`CollectionRecipeRunner`** client seam (one file in → optional
  `RecipeProposal` out), whose `liveValue` runs the four bookends. Stage 3 reuses
  `evidenceAppears`; stages enforce idempotency and field-scope. `useModel = false`
  short-circuits the model call entirely.
- **Recipe editor** under the Collection Policy surface, with a **live preview on
  a real sample** (15–20 diffs from the actual folder) as the tuning loop.
- **Execution** points a recipe at a Finder folder; proposals feed the existing
  `ApplyPlan` / `FileOperation.writeTags` rail and the documented Preview
  Requirements diff.

## Slices

- **S0 — Tables + model + deterministic runner.** *(core, no UI)* Add the
  minimal `collectionPolicies` migration (the FK anchor) and the
  `collectionRecipes` migration; the `CollectionRecipe` type + `Op` enum + the
  `affixTemplate` `{value}` substitution; `CollectionRecipeRunner` with the
  **model-off path only** (extract → validate → emit, no `ModelClient` dependency
  yet). Cover `appendIfAbsent` (with a couple of `affixTemplate` variants) and
  `strip` against golden fixtures the way the setlist corpus is tested —
  including the idempotency and verbatim-guard cases. DoD: `swift test` green; a
  recipe over a fixture folder yields correct `ProposedTags` deltas; running
  twice is a no-op; deleting a policy cascades its recipes.
- **S1 — Editor + live sample preview.** Recipe editor under the Collection Policy
  screen (CRUD against the table) with the live-sample diff panel driving off S0's
  runner. Wire the folder-pick → run → preview → existing `ApplyPlan` rail. DoD:
  a user authors a model-off recipe end-to-end, previews real diffs, applies, and
  the tags are written and verifiable. No model involved yet.
- **S2 — Model-on classify stage.** Add the `useModel` branch: a
  `.onDevicePreferred` `ModelRequest` with the fixed schema + guard system prompt,
  prompt-and-parse `{apply, value, reason}`, defensive decode with the
  degrade-to-review floor. The covers recipe is the acceptance case. Stage 3's
  verbatim guard (already in place from S0) is the safety net. DoD: the covers
  recipe classifies `[artist]` vs `[Live]`/`[Remaster]` on a real sample; every
  proposal is preview-gated; a stray model output lands in review, never on disk.

## S0 execution map

*Detailed for S0 only. S1/S2 stay at the sketch above until S0's carry-over is
known — the slice-review workflow folds findings into the next slice, so
speccing them finely now would be thrown away.*

Everything lands in `VinylFeverCore` (S0 is UI-free). New files, each with a
template already in the tree:

| File | Contents | Template |
| --- | --- | --- |
| `Model/CollectionPolicy.swift` | `@Table struct CollectionPolicy { let id: UUID; var name; var description }` | [CompilationAlbum.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/CompilationAlbum.swift) |
| `Model/CollectionRecipe.swift` | `@Table struct CollectionRecipe` (schema columns) + `Op` enum + `affixTemplate` `{value}` substitution | `CompilationAlbum.swift` |
| `Recipes/CollectionRecipeRunner.swift` | `@DependencyClient` seam + `liveValue` **model-off path** (extract → validate → emit) | [SetlistNormalizer.swift](../../VinylFeverCore/Sources/VinylFeverCore/Normalizing/SetlistNormalizer.swift) minus `ModelClient` |

Enum columns (`op`, `targetField`) store as raw text and expose a typed accessor,
the way `CompilationAlbum.ruleset` projects onto flat columns — do **not** add
custom SQLite codecs.

Two edits to existing files:

- **[Schema.swift](../../VinylFeverCore/Sources/VinylFeverCore/Database/Schema.swift)**
  — two `registerMigration` blocks, `collectionPolicies` **before**
  `collectionRecipes` (FK order), each mirroring the `compilationAlbums`
  migration. `eraseDatabaseOnSchemaChange` (DEBUG) keeps this additive-safe in
  dev.
- **Shared verbatim guard** — `evidenceAppears(_:in:)` is currently a `static
  func` on
  [SetlistNormalizationValidator.swift:112](../../VinylFeverCore/Sources/VinylFeverCore/Normalizing/SetlistNormalizationValidator.swift).
  Extract it to a small shared helper (e.g. a free function or `TextEvidence`
  type) so the recipe validator and the setlist validator share one
  implementation rather than duplicating the check. **This is the only refactor
  of existing code S0 makes** — flag any wider reach in review.

Tests: `Tests/VinylFeverCoreTests/CollectionRecipeRunnerTests.swift` plus a
fixtures folder mirroring `Fixtures/RawSetlists/…/Golden`. Cases:
`appendIfAbsent` across a couple of `affixTemplate` variants, `strip`, the
idempotency no-op (run twice), the verbatim-guard rejection (capture altered so
it no longer appears in the filename → `RecipeIssue.valueNotInFilename`), and the
FK cascade (delete a policy → its recipes vanish).

## Out of scope

- Any change to the write rail, `ApplyPlan`, `FileOperation.writeTags`, or the
  preview contract — recipes only *produce* a delta.
- Recipe evidence sources beyond the filename (folder path, sibling files,
  MusicBrainz). Filename-only for v1.
- Recipe sharing/export/import (the design notes it is portable; the surface is a
  later milestone).
- Any change to the live-show import flow (M6).

## Decisions (resolved 2026-07-09)

- **Membership link → `collectionPolicyID` foreign key** (not a Grouping token),
  `ON DELETE CASCADE`. A recipe cannot outlive its policy. Consequence, folded
  into S0: this milestone stands up the minimal `collectionPolicies` table as the
  FK anchor — the first concrete Collection Policy row. Recipe-to-policy is an FK;
  policy-to-track membership stays Grouping-based per the policy model.
- **Append format → an `affixTemplate` recipe field** (default `" ({value})"`),
  substituted deterministically at run time. Container symbols are recipe data,
  authored once and frozen, applied identically across the batch — never a
  per-file model decision. Only `appendIfAbsent` reads it.

No open decisions. Slice boundaries above are the proposed review units.
