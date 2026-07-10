# Milestone 8 — Collection Policy Binding

*Bind a [Collection Policy](../metadata-policy-model.md) to a compilation album so
that appending a folder runs the policy's recipes **and** the compilation
tag-stamping in one previewed, one-applied pass. This is the deferred "fuse the two
runs" question from M7 S1, now answered from real use: no new pipeline and no write-rail
change — it merges two `ProposedTags` producers that already converge on the same
`ApplyPlan` / `writeTags` rail. Rules in
[../technical-architecture.md](../technical-architecture.md),
[../metadata-policy-model.md](../metadata-policy-model.md), and
`/Users/jon/code/jon-platform/AGENTS.md` apply; where this doc and those conflict,
stop and flag it.*

## The milestone in one sentence

Give a `CompilationAlbum` an optional `collectionPolicyID`, and have the append flow
run that policy's enabled recipes over each file, merge their per-track
`ProposedTags` delta into the compilation delta, and preview and apply the combined
result — so one folder-pick does what two manual gestures do today.

## Why now

M7 S1 shipped the recipe workbench and **deliberately left recipe-run and
collection-append as two separate gestures**, recording the open question verbatim:
"whether to fuse the two runs once the folder-run flow has been used enough to show
the pattern — answer from real use, don't pre-guess"
([M7 ledger](M7-collection-recipes.md), *Decisions, S1 boundary*). The pattern has
now shown itself in use: running a policy on a folder and then an append-to-collection
on the same folder is the exact manual two-step this app exists to remove.

The groundwork makes this a merge, not a build:

- **Both producers already emit `ProposedTags`.** The compilation delta
  (`CompilationApplyPlan.proposedTags(entry:current:)`,
  [CompilationApplyPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift))
  and the recipe delta (`RecipeProposal.delta`,
  [CollectionRecipeRunner.swift](../../VinylFeverCore/Sources/VinylFeverCore/Recipes/CollectionRecipeRunner.swift))
  are the same type feeding the same rail. There is no translation layer to write.
- **The FK anchor already exists.** M7 stood up `collectionPolicies` precisely as the
  reusable Collection Policy primitive; this milestone adds the *other half* of the
  relationship — an album that points at one.
- **The runner seam is async-ready.** `CollectionRecipeRunner.run` is already
  `async throws` and already carries the model-on (`useModel`) path and the
  degrade-to-review floor, so binding it into append needs no recipe-engine change.

## Scope

The moving parts:

- **`compilationAlbums.collectionPolicyID`** — a new **nullable** FK column
  referencing `collectionPolicies(id)` **`ON DELETE SET NULL`**. Note the asymmetry
  with the recipe FK: a recipe cannot outlive its policy (`CASCADE`), but a
  collection *can* — deleting a policy unbinds the album, it does not delete it.
- **A pure `ProposedTags` merge** — `(compilationDelta, [recipeDelta]) → ProposedTags`
  with a fixed, testable precedence (below). This is the one genuinely new piece of
  logic and the heart of the milestone.
- **Append runs the bound policy's recipes.** `buildCompilationAppendPlan` (async
  already) runs each enabled recipe over every file via `collectionRecipeRunner.run`,
  collects the non-`nil` proposals per file, and feeds them into the plan build.
- **One preview, one apply.** Recipe-driven diffs and their review flags render in the
  existing `CompilationAppendSection` alongside the compilation diffs; issue-flagged
  proposals are excluded from apply — the setlist "refuse to call it clean" rule,
  identical to M7 S1.
- **A policy picker** on the collection detail to set/clear the binding.

## Merge precedence (the load-bearing decision)

Compilation stamping and recipes overlap on exactly three fields — `album`,
`albumArtist`, `grouping`. The rule:

- **`album` / `albumArtist`: the collection wins, always.** These *are* the
  collection's identity; a recipe that proposes them on an appended file is proposing
  to break the append. The compilation delta is authoritative and the recipe value is
  dropped (surface it as a skipped/for-info diff, not applied).
- **`grouping`: union.** Both legitimately contribute tokens.
  `CompilationApplyPlan.mergedGrouping` already unions and de-dupes; run the recipe's
  grouping tokens through the same merge rather than letting either clobber.
- **`title` / `artist` / `sortAlbum`: recipe-only.** No compilation conflict; the
  recipe delta lands as-is.
- **`clearedFields` union**, and the compilation delta's structural fields
  (`isCompilation`, track/disc) are untouched by recipes (`isStringValued == false`),
  so they pass through.

This precedence is a **decision, not a preference toggle** — an appended file's
album identity is not negotiable per-recipe. If real use later wants a recipe to
override identity, that is a new, evidence-backed decision; do not build the toggle
speculatively.

## Slices

- [x] **S0 — FK column + merge (core, no UI).** Add the nullable
  `collectionPolicyID` migration (`ON DELETE SET NULL`) and the `CompilationAlbum`
  field; write the `ProposedTags` merge with the precedence above; extend the
  `CompilationApplyPlan` build to accept per-file recipe deltas and fold them into
  each track's `proposed` and `diffs`. Keep `CompilationApplyPlan` a pure value type —
  it accepts *already-computed* deltas, it does not run the async runner. DoD:
  `swift test` green; fixtures show identity fields held by the collection, grouping
  unioned, title/artist taken from recipes; an issue-flagged delta is carried but
  marked non-appliable; running twice is a no-op; deleting a bound policy sets the
  album's `collectionPolicyID` to `NULL` (album survives).
- [x] **S1 — Bind + fused append (app layer).** Policy picker on the collection detail
  (set/clear `collectionPolicyID`); `buildCompilationAppendPlan` loads the bound
  policy's enabled recipes and `await`s `collectionRecipeRunner.run` per file, passing
  the collected deltas into S0's plan build; `CompilationAppendSection` renders recipe
  diffs + review flags next to the compilation diffs; one apply writes both. DoD: with
  a policy bound, one folder-pick previews compilation tags **and** recipe edits
  together and applies them together; an **unbound** album behaves byte-identically to
  today; issue-flagged proposals are preview-gated, never on disk.

*S0 and S1 are detailed below. Model-on recipes need no separate slice — the runner's
`useModel` path is already live and simply runs inside the `await` S1 introduces; its
degrade-to-review output flows through the same issue-flag gate.*

## S0 execution map

Everything lands in `VinylFeverCore`. Edits, each with a template already in the tree:

| File | Change | Template / anchor |
| --- | --- | --- |
| [Schema.swift](../../VinylFeverCore/Sources/VinylFeverCore/Database/Schema.swift) | one `registerMigration` block: `ALTER TABLE "compilationAlbums" ADD COLUMN "collectionPolicyID" TEXT REFERENCES "collectionPolicies"("id") ON DELETE SET NULL` | the `collectionRecipes` FK migration (`:117`), but nullable + `SET NULL` |
| [CompilationAlbum.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/CompilationAlbum.swift) | add `var collectionPolicyID: CollectionPolicy.ID?` (nil default in `init`) | its own existing optional columns (`seedFolderPath`) |
| [CompilationApplyPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift) | new init param `recipeDeltasByFileID: [ScannedAudioFile.ID: [ProposedTags]]` (default `[:]`); fold into each track's `proposed` via the merge before computing `diffs` | the existing `currentTagsByFileID` param it mirrors |
| `Collection/RecipeTagMerge.swift` *(new)* | pure `static func merge(compilation: ProposedTags, recipes: [ProposedTags]) -> ProposedTags` implementing the precedence | `CompilationApplyPlan.mergedGrouping` (reuse it for the grouping leg) |

Enum/precedence stays in one pure function so it is fixture-testable in isolation.
`ON DELETE SET NULL` (not `CASCADE`) is the one easy-to-get-wrong line — call it out
in review.

Tests: `Tests/VinylFeverCoreTests/RecipeTagMergeTests.swift` — identity-held,
grouping-union, recipe-only fields, `clearedFields` union, issue-flagged carried but
non-appliable, idempotent second run. Plus a `CompilationApplyPlan` test that a
non-empty `recipeDeltasByFileID` changes only the expected diffs and an empty one
reproduces today's plan exactly (the unbound-album guarantee, asserted at the core
layer).

## S1 execution map

App layer only; flag any core reach in review. The flow already has an end-to-end
template in the compilation-append methods.

Edits:

- **[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift)** — in
  `buildCompilationAppendPlan` (`:747`), after reading `currentTagsByFileID`, if
  `entry.collectionPolicyID != nil` load that policy's enabled recipes
  (`@FetchAll`-style read via `defaultDatabase`), then for each file `await`
  `collectionRecipeRunner.run(recipe:filename:current:)` across the policy's recipes,
  collecting non-`nil` `proposal.delta` (and carrying `proposal.issues` for the flag)
  into `recipeDeltasByFileID`; pass that into the `CompilationApplyPlan` init. Reuse
  the read loop already in place at `:761`–`:774`. An unbound album skips the whole
  block and builds exactly as today.
- **[CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)**
  — a policy picker on the selected-album detail (`@FetchAll(CollectionPolicy…)` for
  the options; write `collectionPolicyID` through the same registry upsert path as the
  cover/ruleset edits); render recipe-driven rows + review flags inside
  `CompilationAppendSection` next to the compilation `CompilationTagDiff` rows.

Tests: `AppModel`-level coverage that a bound policy's deltas reach the plan and
issue-flagged items are excluded from apply, using the injected
`collectionRecipeRunner` + fake file/metadata clients — clone the compilation apply
test support. Pure-view code stays untested.

DoD: as the slice list. Add an explicit regression check that an unbound album's
built plan is unchanged.

### Carry-over from S0 review

S0's core landed correctly (FK + `SET NULL`, precedence, byte-identical unbound
guarantee). Three items surfaced in review that S1 must resolve — do not inherit
them as tacit assumptions:

- **Recipe-owned fields have no preview channel (load-bearing).** `title` / `artist` /
  `sortAlbum` land in `CompilationTrackPlan.proposed` (and are written to disk via
  `ApplyPlan`), but `CompilationApplyPlan.diffs()` emits no row for them — it stays
  collection-shaped (Album/Album Artist/Grouping/Compilation/Track/Disc/Artwork) so
  the byte-identical unbound guarantee holds. A recipe that rewrites titles — the
  canonical case — would therefore **apply without appearing in the preview**, which
  breaks "one previewed, one applied." S1 must surface recipe edits, and **must not**
  rely on `CompilationTrackPlan.diffs` to carry them. Fix path: emit *conditional*
  Title/Artist/SortAlbum diff rows (only when `proposed.<field> != nil` — `proposedTags`
  never sets these, so unbound plans stay byte-identical), or render a dedicated
  recipe-diff channel from `proposal.delta`.
- **`clearedFields` union is asymmetric with the value restoration (defensive).**
  `RecipeTagMerge.merge` restores identity/structural *values* from the compilation
  delta but unions `clearedFields` blindly, so a recipe delta carrying `.album` or a
  structural field survives into the result (the S0 test asserts `album == "Great Covers"`
  while `clearedFields` contains `.album`). Masked today — real recipes never populate
  `clearedFields` and can't target structural fields, and the write layer resolves
  value-over-clear. But the **diff layer resolves clear-over-value** for Track/Disc
  Number, the opposite precedence, so any future producer emitting a structural
  `clearedField` yields a preview/apply divergence. `merge` is public API over arbitrary
  `[ProposedTags]`; harden it by restoring the identity/structural `clearedFields`
  membership from `compilation.clearedFields`, symmetric with the value restoration.
- **DoD move.** "Issue-flagged delta carried but marked non-appliable" cannot be met at
  the S0 layer (`ProposedTags` has no issue channel; issues live on `RecipeProposal`).
  S0's ledger box stays ticked for the core, but this DoD item is **inherited by S1** —
  S1 collects `proposal.issues` and gates issue-flagged proposals out of apply.

Minor, for the record: dropped recipe `album`/`albumArtist` are silently discarded
(spec line 74 wants a skipped/for-info diff — no channel exists yet); and recipe order
within a policy is significant for scalar fields (last-writer-wins), order-insensitive
for grouping.

### Carry-over from S1 review

S1 landed correctly: all three S0 carry-overs are resolved (issue-flag gate at
`buildCompilationAppendPlan`, symmetric `clearedFields` restoration in `RecipeTagMerge`,
recipe edits surfaced through a dedicated preview channel rather than
`CompilationTrackPlan.diffs`), the unbound plan is asserted byte-identical, and the
bind/fuse/exclude paths are tested. `swift test` (core) green. M8's slice list (S0 + S1)
is complete. The items below are **fast-follow candidates**, not slice blockers — there
is no S2 to inherit them, so triage each into a follow-up or accept as documented:

- **Recipe preview renders the raw delta, not the merge result (load-bearing).**
  `RecipeProposalPreview.diffs` in
  [CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)
  shows every string-valued field in `proposal.delta`, but apply runs the delta through
  `RecipeTagMerge.merge`, which **drops** recipe `album`/`albumArtist` (collection wins)
  and **unions** `grouping`. So a recipe targeting `album`/`albumArtist` previews an
  identity change that is never applied — the exact "skipped/for-info, not applied" case
  from spec line 74, and a direct hit on the "one previewed, one applied" contract; a
  `grouping` recipe previews a raw token that differs from the unioned value actually
  written (which also appears, correctly, in the compilation diff row — grouping
  double-displays). **Exact for the dominant `title`/`artist`/`sortAlbum` recipes**, which
  is why it did not surface in DoD. Fix path: reflect merge precedence in the recipe
  channel — filter identity fields out (or mark them "held by collection, not applied")
  and render `grouping` as the merged result.
- **Fetch-all-then-filter (efficiency).** `buildCompilationAppendPlan` loads *every*
  `CollectionRecipe` in the DB via `CollectionRecipe.order(by: \.name).fetchAll(db)` and
  filters `collectionPolicyID`/`enabled` in memory. Prefer a `.where`-scoped query. Minor
  at current scale.
- **Binding change leaves a stale-empty section (UX).** `setCompilationPolicy` clears the
  plan but leaves `compilationAppendFolder`/files set without rebuilding, so after
  re-binding with a folder already picked the section shows a selected folder and no plan
  until re-pick. Intentional per the in-code comment ("cannot drift"); consider
  auto-rebuilding from the retained folder.
- **Nits.** `RecipeProposalPreview.diffs` emits a row even when `proposed == current`
  (no-op shows as "X → X"); recipe precedence is name-alphabetical (deterministic but
  arbitrary — see the order note above); `CompilationRecipeProposal` sits under the
  "Recipe workbench support (M7 S1)" MARK though it is M8 support.

## Out of scope

- Any change to the write rail, `ApplyPlan`, `FileOperation.writeTags`, the preview
  contract, or the recipe engine — this milestone only *merges deltas* and *wires the
  binding*.
- A recipe-value-overrides-identity toggle (see the precedence decision — build only
  on real evidence).
- Binding a policy to a **live show** or any non-compilation surface. Compilation
  albums only for v1.
- Running an unbound folder's recipes from the Collections screen — that is what the
  Policies workbench (M7 S1) is for; the two surfaces stay distinct.
- The one-true-import-folder fix (converted-FLAC vs passthrough mp3/m4a landing in
  different folders) — a separate, ungated slice tracked in `CURRENT_HANDOFF.md`, not
  part of this milestone.

## Decisions (open — resolve before/at S0 review)

- **Binding cardinality → one policy per album (nullable FK on the album).** Chosen for
  symmetry with the recipe FK and because a collection has one metadata policy. A
  policy is still reusable across many albums (it is the FK *target*). Confirm this is
  the intended shape and not many-policies-per-album.
- **Precedence** as specified above (collection wins identity; grouping unions). This
  is the milestone's central claim — confirm at S0 review against a real bound append.
- **Empty binding UX** — an album with no policy shows the picker in a "None" state and
  the append flow is exactly today's. No auto-suggest of a policy in v1.
