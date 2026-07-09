# Collection Recipes

A **Collection Recipe** is a small, user-authored, per-collection rule that
proposes a metadata edit from evidence already present on a file — most often
its filename. It exists so a user can express a one-off cleanup intent ("the
cover's original artist is in square brackets in the filename; put it at the end
of the title") without anyone building a MusicBrainz-grade deterministic parser
for it, and without the LLM ever being trusted to write tags directly.

Recipes are a rule *flavor* of a [Collection Policy](metadata-policy-model.md),
not a new subsystem. They produce a `ProposedTags` delta and hand it to the
existing apply-with-preview rail. Everything downstream of that delta already
exists.

## Why This Shape

Two observations drove the design.

First, the motivating example is *deterministic*. "Bracketed filename text not
already in the title → append it" is a regex plus a substring check. It needs no
model, and you actively do not want one: across a large batch you need file #3
and file #180 formatted identically, which is a property of code, not of a
sampled language model.

Second, the thing that *is* hard is semantic: the same `[...]` slot holds an
artist (`[Nine Inch Nails]`) and a non-artist qualifier (`[Live]`,
`[2019 Remaster]`, `[Explicit]`). Telling those apart is a judgment a regex
cannot make and a small onboard model can. So the LLM's job in a recipe is
**classification of extracted evidence**, never string surgery and never the
write.

This splits cleanly onto the existing setlist "sandwich": deterministic extract
→ optional model judgment → deterministic validate → always preview. See
[SetlistNormalizer.swift](../VinylFeverCore/Sources/VinylFeverCore/Normalizing/SetlistNormalizer.swift).

## The Two Exposed Knobs

A recipe exposes both a **regex** and a **prompt**, deliberately, but they are
two stages with a contract between them, not two free-text blobs:

- **Regex** — deterministic extraction and gate. It pulls named variables out of
  the filename and decides whether a file is even a candidate. Fully auditable:
  the user can read it and know exactly what it captures.
- **Prompt** — the semantic judgment over those captured variables, emitting the
  constrained edit.

The regex's named capture groups are precisely the variables the prompt is
allowed to reason about. That shared vocabulary is what stops the two knobs from
drifting apart; they are tuned together against one sample, not independently.

Casual authoring writes the English intent and lets Claude generate the regex
behind it; the regex sits in an "advanced" reveal for anyone who wants to verify
or hand-tune the rail. Control for those who want it, English for those who
don't.

## The Model Toggle

The LLM is a **per-recipe toggle**, because most cleanup rules are pure-regex.

- `useModel = false` — a purely deterministic rule: free, instant, and stable.
  This is the existing ad-hoc Python (`scripts/python/scrub_titles.py`,
  `rule_scrub_tags.py`, `strip_prefix_underscore.py`) promoted into the app as a
  first-class, previewable, per-collection policy rule. For these, "once it's
  right it's right" is literally true.
- `useModel = true` — the classification stage runs per file. The recipe
  *definition* still freezes once authored, but each *run* re-judges every file,
  so the preview-before-write is a permanent safety rail here, not just a tuning
  aid.

Recipes default to the `.onDevicePreferred` tier, not `.frontierPreferred`: the
classification is small and runs per file across a large batch, which is the
cost/privacy sweet spot for the onboard model. The `ModelClient` seam degrades
cleanly when no key is configured, exactly as the Normalizer relies on.

## Data Model

Stored in SQLiteData, mirroring the `compilationAlbums` table conventions in
[Schema.swift](../VinylFeverCore/Sources/VinylFeverCore/Database/Schema.swift)
(STRICT, TEXT primary key defaulting to `uuid()`):

```sql
CREATE TABLE "collectionRecipes" (
  "id"                 TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "collectionPolicyID" TEXT NOT NULL REFERENCES "collectionPolicies"("id") ON DELETE CASCADE,
  "name"               TEXT NOT NULL DEFAULT '',
  "pattern"            TEXT NOT NULL DEFAULT '',      -- regex; matches the filename (capture ops) or the target field (strip)
  "captureName"        TEXT NOT NULL DEFAULT 'value',
  "targetField"        TEXT NOT NULL DEFAULT 'title',
  "op"                 TEXT NOT NULL DEFAULT 'appendIfAbsent',
  "affixTemplate"      TEXT NOT NULL DEFAULT ' ({value})', -- how appendIfAbsent wraps the value
  "useModel"           INTEGER NOT NULL DEFAULT 0,     -- the LLM on/off toggle
  "prompt"             TEXT NOT NULL DEFAULT '',       -- ignored when useModel = 0
  "enabled"            INTEGER NOT NULL DEFAULT 1
) STRICT
```

The `collectionPolicyID` foreign key is the recipe's owning policy; `ON DELETE
CASCADE` means a recipe cannot outlive its policy. This presumes a
`collectionPolicies` table exists — see [Build Order](#build-order), where M7
stands up a minimal one as the anchor.

The Swift model speaks the field vocabulary the write rail already uses —
`targetField` is
[`ProposedTags.Field`](../VinylFeverCore/Sources/VinylFeverCore/Model/ShowPlan.swift),
so there is no translation layer between a recipe and the tags it edits:

```swift
public struct CollectionRecipe: Equatable, Sendable, Identifiable {
  public var id: UUID
  public var collectionPolicyID: CollectionPolicy.ID  // FK — the recipe's owning policy
  public var name: String
  public var pattern: String                 // e.g. #"\[(?<value>[^\]]+)\]"#
  public var captureName: String
  public var targetField: ProposedTags.Field
  public var op: Op
  public var affixTemplate: String           // appendIfAbsent wrap, e.g. " ({value})"; author-time, frozen
  public var useModel: Bool
  public var prompt: String
  public var enabled: Bool

  public enum Op: String, CaseIterable, Sendable {
    case appendIfAbsent   // covers case: append capture to title if not already present
    case setIfEmpty       // only fill a blank field
    case replace          // overwrite
    case strip            // regex match → remove (the scrub_titles.py case, model off)
  }
}
```

An `Op` is a **transform** over `(captured evidence, current field value) → new
field value`; append is only the transform the covers case needs, not the shape
of every recipe. The set is a deliberately **closed enum** — each op is
auditable and fixture-testable, with no arbitrary-code path. `strip` is already a
pure deletion, the opposite of an append. If this list ever grows past a handful,
that is the signal to consider a more general transform; until then, named ops
are the right altitude. `affixTemplate` is op-specific config that only
`appendIfAbsent` reads: a `{value}` placeholder substituted deterministically, so
the container symbols (`(…)`, `[…]`, `feat. …`) are recipe data — authored once
and frozen like the regex and prompt — never a per-file model decision.

## Execution: The Sandwich

The runner is a client seam, structurally identical to
`LiveSetlistNormalizer.normalize`. One file in, an optional delta out; `nil`
means the recipe does not touch this file.

```swift
@DependencyClient
public struct CollectionRecipeRunner: Sendable {
  public var run: @Sendable (_ recipe: CollectionRecipe,
                             _ filename: String,
                             _ current: AudioTags) async throws -> RecipeProposal?
}

public struct RecipeProposal: Equatable, Sendable {
  public var delta: ProposedTags        // flows straight into ApplyPlan.writeTags
  public var reason: String             // shown in the preview "why" column
  public var issues: [RecipeIssue]      // non-empty ⇒ force review, never auto-apply
}
```

The `liveValue` body runs four bookends:

1. **Extract (deterministic).** `op` decides where `pattern` looks: the capture
   ops (`appendIfAbsent`, `setIfEmpty`, `replace`) run it over the **filename** and
   take the named capture; `strip` runs it over the **current `targetField`
   value** and removes every match. No match → return `nil`; the file is
   untouched.
2. **Classify (LLM, only when `useModel`).** A `ModelRequest` on the
   `.onDevicePreferred` tier with a fixed system prompt carrying the output
   schema and the verbatim guard, plus the user's `prompt`, the captured
   variables, and the current tags. Prompt-and-parse a small JSON
   `{apply, value, reason}`, defensively decoded with the same degrade-to-review
   floor the Normalizer uses. When `useModel` is off, this stage is
   `apply = true, value = capture` verbatim — no model call.
3. **Validate (deterministic, model-free).** The guards:
   - **`value` must appear verbatim in the filename.** This is the
     anti-hallucination tripwire, and it is already written: `TextEvidence.appears`
     (extracted from the setlist validator's evidence check) is exactly this test
     (case- and whitespace-insensitive substring). It stops the model inventing or
     "correcting" an artist name.
   - **Idempotency.** Skip if `targetField` already contains `value`; running a
     recipe twice never double-appends.
   - **Field scope.** The op may only write `targetField`. No helpful,
     unrequested edits to other fields.
4. **Emit.** Build the `ProposedTags` delta by applying `op`. For
   `appendIfAbsent`: `title = current.title + affixTemplate.with(value)`, where
   `affixTemplate` substitutes `{value}` (default `" ({value})"`). Other ops
   (`setIfEmpty`, `replace`, `strip`) transform the field their own way.

An idempotent no-op — the value is already present, the field is already
populated, or a `strip` changed nothing — returns `nil` (no proposal), *not* an
issue: there is simply nothing to review. `issues` is reserved for genuine
problems that must not auto-apply:

```swift
public enum RecipeIssue: Equatable, Sendable {
  case valueNotInFilename        // the anti-hallucination tripwire
  case modelOutputUnparseable    // degraded floor → review (produced only on the useModel path)
}
```

Following the validator's house rule, a non-empty `issues` set never
auto-applies — it forces the item into human review. The validator refuses to
call something clean; it does not auto-fix.

## Where It Slots

- **Definition** — the `collectionRecipes` table, edited in a recipe editor
  under the Collection Policy screen. `collectionPolicyID` is a foreign key to
  the owning policy (`ON DELETE CASCADE`); the policy in turn carries the
  Grouping token that governs *track* membership per the
  [policy model](metadata-policy-model.md). Recipe-to-policy is an FK; policy-to-
  track stays Grouping.
- **Execution** — point a recipe at a Finder folder (the policy doc's "apply to
  a selected folder" gesture). For each file, `runner.run(...)` produces a
  `RecipeProposal`; the proposals feed the existing `ApplyPlan` /
  `FileOperation.writeTags` rail and the
  [Preview Requirements](metadata-policy-model.md) diff. Nothing new is built
  downstream of the delta.
- **Authoring loop** — the recipe editor shows a **live preview on a real
  sample** (15–20 proposed diffs from the actual collection). That is the tuning
  surface: tweak regex or prompt, watch the diffs settle, and when the sample is
  clean, run the full set. It is also where Claude helps hand-tune misfires.

## Portability

A recipe is a small, self-contained record — name, regex, prompt, op,
target field, model flag. It can be shared between collections or exported the
way the setlist normalizer treats its spec as a buildable, media-as-truth
artifact. Nothing in a recipe references app-internal state beyond the field
vocabulary.

## Build Order

Ship **model-off first.** A `CollectionRecipe` with `useModel = false` is a pure
regex rule: the existing ad-hoc Python promoted into the app, fully
deterministic, and testable against golden fixtures the way the setlist corpus
is. That first slice delivers the table, the editor, the
extract → validate → emit → preview rail, and the live-sample tuning loop with
zero model variance.

Because `collectionPolicyID` is a foreign key, the first slice also stands up a
**minimal `collectionPolicies` table** (`id`, `name`, `details` — the
identity fields the [policy model](metadata-policy-model.md) lists) as the FK
anchor. This is the first concrete instantiation of the Collection Policy
primitive that document is built around; reconciling the existing
`compilationAlbums` registry onto it is a later, separate step.

The covers assistant is then one flag flip plus the classify stage — and stage
3's verbatim guard is already in place to catch the model when it strays.
