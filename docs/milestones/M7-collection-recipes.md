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

- **`collectionPolicies` table** (minimal: `id`, `name`, `details`) — the FK
  anchor and first concrete instance of the Collection Policy primitive.
- **`collectionRecipes` table** (SQLiteData, STRICT, cloned from
  `compilationAlbums` conventions) holding `{ collectionPolicyID (FK, cascade
  delete), name, pattern, captureName, targetField, op, affixTemplate,
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

*S0 and S1 are detailed below. S2 stays at the sketch above until S1's carry-over
is known — the slice-review workflow folds findings into the next slice, so
speccing it finely now would be thrown away.*

Everything lands in `VinylFeverCore` (S0 is UI-free). New files, each with a
template already in the tree:

| File | Contents | Template |
| --- | --- | --- |
| `Model/CollectionPolicy.swift` | `@Table struct CollectionPolicy { let id: UUID; var name; var details }` | [CompilationAlbum.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/CompilationAlbum.swift) |
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

## S1 execution map

*The app-layer slice: a folder-targeted recipe workbench. S0's runner and the
existing `ApplyPlan`/`writeTags` rail already cover the machinery, so S1 adds **no
`VinylFeverCore`** — it is UI + `AppModel` wiring that clones the compilation-append
flow. Flag any core reach in review.*

**Shape (resolved 2026-07-09).** A recipe run and a collection append stay **two
separate gestures** for now — author/tune/run a recipe against a Finder folder here;
append to a compilation over on the Collections screen. No policy↔collection binding
and no auto-run in S1; whether to fuse them is a "use it, then decide" question (see
Decisions). The surface is a **new top-level `Policies` sidebar section**, peer to
Live Shows and Collections — not bolted onto the already-584-line `CollectionsView`,
and deliberately not implying a binding that isn't built.

The flow mirrors compilation append end-to-end (registry → folder-pick → read tags →
build plan → preview diffs → apply), so every step has a proven template in
[CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)
and the `compilation*` methods in
[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift).

New files:

| File | Contents | Template |
| --- | --- | --- |
| `VinylFever/Features/Policies/PoliciesView.swift` | Policy registry (CRUD) → recipe editor for the selected policy → live-sample preview → apply. Split into sections the way `CollectionsView` is if it grows. | `CollectionsView.swift` |

Edits to existing files:

- **[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift)** — add
  `AppSection.policies` (title `"Policies"`, an SF Symbol) at the `AppSection` enum
  (`:1415`); recipe/policy UI state; and two methods cloned from the compilation
  counterparts: `buildRecipeSample(recipe:folder:)` (clone the append read loop at
  `:739`–`:758` — `fileSystemClient.scanAudioFolder` → per-file
  `audioMetadataClient.read` → `collectionRecipeRunner.run(recipe:filename:current:)`,
  collecting non-`nil` proposals) and `applyRecipePlan(_:)` (clone
  `applyCompilationPlan` at `:784`).
- **[AppShellView.swift](../../VinylFever/Features/AppShell/AppShellView.swift)** —
  route `.policies → PoliciesView(model:)` in the section `switch` (`:23`).

The pieces:

- **Policy + recipe CRUD** against S0's tables. `@FetchAll(CollectionPolicy.order(by:
  \.name))` for the policy list (create / rename / delete — **delete cascades its
  recipes** via the FK; make that a visible DoD check). For the selected policy,
  `@FetchAll` recipes filtered on `collectionPolicyID`. Editor form fields: `name`;
  `op` picker over `Op.allCases`; `targetField` picker over the **string-valued**
  fields only (filter `ProposedTags.Field.allCases` by `isStringValued`); `pattern`;
  `captureName`; `affixTemplate` (surface it only for `appendIfAbsent`); `enabled`.
  `useModel`/`prompt` are **inert in S1** — render them disabled with an "arrives in
  S2" affordance and persist their defaults, so S2 lights them up with no migration.
  Route mutations through `defaultDatabase` writes the way the compilation registry
  does.
- **Live-sample preview — the tuning loop.** Folder pick (`NSOpenPanel`, cloned from
  `CollectionsView.openFolder`) → `buildRecipeSample` runs the **one selected recipe**
  over each file and shows ~15–20 proposed diffs (filename, field, current → proposed).
  A proposal carrying non-empty `issues` renders a **review flag** and is excluded
  from apply — never auto-applied (the setlist "refuse to call it clean" rule). The
  panel re-runs as the recipe is edited; it does not write. Running a whole policy's
  recipe set in one pass is a natural fast-follow, **not** an S1 requirement — S1 is
  single-recipe.
- **Apply — feeds the existing rail unchanged.** Build an `ApplyPlan` whose
  `ApplyTrackPlan.tags` is the recipe's single-field `proposal.delta`, with the same
  `copy → writeTags` operation pair as `ApplyPlan(compilationPlan:)`, then run
  `ApplyExecutor().apply(plan, toolPaths:)`. Correctness is already guaranteed by the
  rail: `AudioTaggingCommands.plan` emits a write command only for non-`nil` fields
  ([:112](../../VinylFeverCore/Sources/VinylFeverCore/Tagging/AudioTaggingCommands.swift)),
  so the delta changes its one field and leaves every other tag on the copied file
  intact. Like every other flow, this stages tagged copies under `Working/` — it is
  **not** an in-place library edit (that would touch the write rail; out of scope —
  see Decisions).

Tests: `AppModel`-level coverage of `buildRecipeSample` (proposals collected, issue
items flagged) and `applyRecipePlan` (issue items excluded, single-field delta lands),
using the injected `collectionRecipeRunner` + fake file/metadata clients — clone the
compilation apply test support. Pure-view code stays untested.

DoD (from the slice list): a user authors a model-off recipe end-to-end, previews real
diffs over a chosen folder, applies, and the written tags are verifiable; deleting a
policy cascades its recipes. No model involved.

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

## Decisions (resolved 2026-07-09, S1 boundary)

- **Recipe surface → a new top-level `Policies` sidebar section**, peer to Live Shows
  and Collections. Not nested in `CollectionsView` (already 584 lines) and not
  attached to a compilation-album record.
- **Recipe run and collection append stay two separate gestures.** No policy↔
  collection binding and no auto-run of recipes on append in S1: not every track that
  lands in a collection meets a recipe's requirements, so coupling them now would
  over-fit. Run the recipe against a folder here; append on Collections. **Open
  question, deferred by design:** whether to fuse the two runs once the folder-run
  flow has been used enough to show the pattern — answer from real use, don't
  pre-guess. **Resolved 2026-07-10 → fuse it:** real use surfaced the two-gesture
  friction; the binding is specced as [M8](M8-collection-policy-binding.md).
- **Recipe apply rides the existing `copy → Working/ → writeTags` rail; no in-place
  library edit in S1.** In-place tag editing would require a new write-rail path,
  which is out of scope. Whether recipe cleanup should ultimately write in place
  rides with the fuse-the-runs question above.
