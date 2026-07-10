# Milestone 9 — Manual Append Metadata

*Give the collection **Append** flow a per-append affordance to type a **Grouping**
token and a **Comments** note that ride along with the batch being appended. This is
dogfooding feedback from real use (2026-07-10): the append preview stamps
collection-owned identity and (when a policy is bound, M8) recipe edits, but there is
no way to attach a one-off human note — a source label, a session tag — to *this*
append without editing the registry entry or a policy first. Rules in
[../technical-architecture.md](../technical-architecture.md),
[../metadata-policy-model.md](../metadata-policy-model.md), and
`/Users/jon/code/jon-platform/AGENTS.md` apply; where this doc and those conflict,
stop and flag it.*

## The milestone in one sentence

At append time, let the user type a free-text **Grouping** token (unioned into the
existing grouping merge) and a **Comments** note (appended to each file's existing
comment), have both show in the same one preview, and write them in the same one
apply — with the values held **ephemerally for that append only**, persisted nowhere.

## Why now

M8 fused compilation stamping and policy recipes into one previewed/one-applied
append. Using it surfaced the gap: the two tag producers are both *rules* (the
registry ruleset and the bound policy). There is no channel for a **manual, this-batch
only** note — the human-in-the-loop escape hatch every previewed pipeline wants. Jon's
ask, verbatim: "an affordance to enter text for the Grouping metatag and text to be
appended to the Comments metatag" when appending a folder.

Scope decision (Jon, 2026-07-10): **per-append, ephemeral.** Two fields in the append
surface, typed fresh each append, applied to every track in the batch, persisted
nowhere. Not fields on the registry entry, not on a policy. This is the most literal
reading of "enter text *when appending*" and keeps the slice off the schema.

The asymmetry that sets the two slices:

- **Grouping already has a merge rail.** `CompilationApplyPlan.mergedGrouping(existing:addedTokens:)`
  ([CompilationApplyPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift))
  already unions and de-dupes tokens from the ruleset, recipes, and the file's existing
  grouping. A manual token is just **one more `addedTokens` source** — no new model.
- **Comments does not exist as a tag.** `AudioTags` has no `comments` field
  ([AudioTags.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/AudioTags.swift));
  the only `comment=` strings in the tree are the artwork-stream `comment=Cover (front)`
  markers, unrelated. So Comments is a **net-new tag field threaded end-to-end**: read
  in both parsers, written by both taggers, surfaced in the diff. That lift — not the UI
  — is the reason this is a milestone and not a one-file fix, and it is why the core work
  (S0) is separated from the app work (S1) in the usual house split.

## Semantics (the load-bearing decisions)

- **Grouping is a union, never a clobber.** The typed token runs through the same
  `mergedGrouping` as every other grouping source; it does not replace the ruleset /
  recipe / existing tokens. Idempotent by construction (union + de-dupe). Empty field →
  no token → today's grouping exactly.
- **Comments is *append*, not *set*.** The proposed comment is the file's **existing
  source comment** with the typed note appended after a fixed separator — a **newline**
  (`"\n"`), locked (Jon, 2026-07-10); an empty existing comment yields just the note.
  "Append" is Jon's word and the point — a source label added *alongside* whatever a
  file already carries. Make the separator a named constant.
- **Idempotency is anchored to the source read.** The plan is rebuilt from the source
  files' current tags every time, so the note is appended to `current.comments` (the
  source), never to an already-appended intermediate. Re-previewing the same batch with
  the same note produces the same comment — no accumulation. Choose a separator and
  make the append a pure function of `(sourceComment, note)`; do not read-modify-write a
  Working copy.
- **Empty fields are byte-identical to today.** No token and no note ⇒ no grouping
  change beyond today's merge and **no** Comments diff row or write. This is the same
  conditional-diff discipline M8 used for recipe-owned title/artist/sortAlbum: a new
  `ProposedTags.Field` case must not perturb plans that don't use it.

## Slices

- [ ] **S0 — `comments` as a first-class tag (core, no UI).** Thread a `comments`
  field through the read/write tag path so the pipeline can carry a track comment at
  all, with the *append* semantics above expressed as a pure merge. No append-flow
  wiring, no UI. DoD: `swift test` green; a FLAC and an mp3/m4a fixture round-trip a
  comment (read → proposed → written args); appending a note to a file with an existing
  comment preserves the original + separator + note; appending to an empty comment
  yields just the note; the merge is idempotent; a plan built with **no** note is
  byte-identical to today (no Comments diff row, no `comment` write arg).
- [ ] **S1 — Append-time Grouping + Comments fields + Collections UX polish (app
  layer).** Two ephemeral text fields on the append surface feeding the plan build so
  both appear in the one preview; one apply writes both. Values live in `AppModel`
  append-scratch state, cleared when the append completes or the folder/album selection
  changes. Bundled with two same-screen dogfooding tweaks (Jon, 2026-07-10): **bigger
  registry artwork**, and **the Append Folder action relocated** out of the
  always-visible header into the selection-gated detail so it only appears once a
  collection is picked (not merely disabled). DoD: typing a Grouping token shows it
  merged in the Grouping diff row and written; typing a Comments note shows a Comments
  diff row and is appended on apply; clearing both reproduces today's append exactly;
  the fields reset between appends and do not leak into another album's append; the
  Append Folder affordance is absent with no selection and present (lower) once a
  registry entry is selected; registry artwork renders at the larger size.

*Ungated — no device dependency. Comment read/write is deterministic file tagging
(ffprobe / metaflac / ffmpeg), not the Music.app live-read that gates M3/M4.*

## S0 execution map

Everything lands in `VinylFeverCore`. The `grouping` field is the exact template for
every touch point — follow it line for line and add the `comments` sibling.

| File | Change | Template / anchor |
| --- | --- | --- |
| [AudioTags.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/AudioTags.swift) | add `public var comments: String?` (+ init param, nil default) | the `grouping` property/param right above it |
| [ShowPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/ShowPlan.swift) | `ProposedTags`: add `public var comments: String?` (init, nil default) and a `case comments` to `Field` (`:125`, `:164`) | the `grouping` var + `case grouping` |
| [FLACMetadataParser.swift](../../VinylFeverCore/Sources/VinylFeverCore/Tagging/FLACMetadataParser.swift) | map the Vorbis `COMMENT` field → `comments` in `VorbisCommentParser` | the `GROUPING` mapping |
| [FFProbeMetadataParser.swift](../../VinylFeverCore/Sources/VinylFeverCore/Tagging/FFProbeMetadataParser.swift) | map the `comment` format/stream tag → `comments` | the `grouping` mapping |
| [AudioTaggingCommands.swift](../../VinylFeverCore/Sources/VinylFeverCore/Tagging/AudioTaggingCommands.swift) | FLAC: `appendFLACTag("COMMENT", value: tags.comments, field: .comments, …)` (`:73`); ffmpeg: `appendFFmpegMetadata("comment", value: track.tags.comments, field: .comments, …)` (`:218`) | the adjacent `GROUPING` / `grouping` append calls |
| [CompilationApplyPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift) | a **conditional** `CompilationTagDiff(field: "Comments", …)` row emitted only when a note is present, so empty-note plans stay byte-identical; a pure `appendedComment(source:note:)` helper for the merge | the conditional title/artist rows M8 added; `mergedGrouping` for the "pure helper" shape |

The append helper (`appendedComment(source:note:) -> String?`) is the one genuinely new
piece of logic — keep it a free-standing pure function so it is fixture-testable in
isolation, exactly like `mergedGrouping`.

Tests: a `comments` round-trip in `AudioTaggingCommandTests` / the metadata-parser
tests (FLAC + ffmpeg args carry the comment; parsers read it back); an
`appendedComment` unit test (existing-comment preserve + separator, empty-source, empty-note
returns source unchanged, idempotent re-append); and a `CompilationApplyPlan` test that
a `nil` note reproduces today's diffs/args exactly and a present note adds exactly the
Comments row + write arg.

The one easy-to-get-wrong line: the **conditional** Comments diff/write. A new
`Field.comments` case is `CaseIterable`, so it will auto-appear in any `allCases`-driven
channel (e.g. the recipe preview) — make sure a `nil` comment never renders or writes.
Call it out in review, same as M8's byte-identical-unbound guarantee.

## S1 execution map

App layer only; flag any core reach in review. The compilation-append methods are the
end-to-end template.

Edits:

- **[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift)** — add ephemeral
  append-scratch state (`compilationAppendGrouping`, `compilationAppendComments`,
  both `String`, default `""`). In `buildCompilationAppendPlan` (`:751`), pass the typed
  grouping token in as an extra grouping source and the comments note into the plan
  build so the merge/diff pick them up. Clear both wherever the append is reset / the
  folder is dropped (mirror the `compilationAppendFolder = nil` sites at `:989` and the
  selection-change rebuild at `:861`). Ephemeral: never read from or written to
  `AppSetting` / the DB.
- **[CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)**
  — two labelled `TextField`s in `CompilationAppendSection` (near the folder path /
  policy picker), bound to the AppModel scratch state, that trigger a plan rebuild on
  commit so the preview reflects them. Keep them disabled/hidden until a folder is
  picked, consistent with the rest of the section.
- **Same file, UX polish (bundled dogfooding):**
  - **Bigger registry artwork.** `ArtworkThumbnail` is hardcoded `frame(width: 44,
    height: 44)` (`:715`). Enlarge it — target ~64–72 for the registry rows. It is
    shared by `CompilationAlbumRow` and the seed-candidate rows; either bump both or
    parameterize the size so the registry list reads bigger without distorting the seed
    list. Confirm the row layout still balances at the larger size.
  - **Relocate the Append Folder action.** Today `CollectionHeader` (`:135`) renders
    "Append Folder" always, merely `.disabled(!canAppend)` (`:156`), and the toolbar
    carries a second Append button gated the same way (`:80`). Per the screenshot, the
    primary Append affordance should live **inside the selection-gated
    `CompilationAppendSection`** (which only renders when `selectedAlbum != nil`), so it
    is absent — not just disabled — with no selection, and sits lower on the page. Drop
    the header's Append button (leave "Seed Registry"); the toolbar Append may stay
    (already selection-gated) or be dropped for consistency — Codex's call.

Whether the fields feed the plan by rebuilding on commit or by being read at build time
is Codex's call — the contract is only that **what the preview shows is what apply
writes** (the house one-previewed/one-applied rule).

Tests: `AppModel`-level coverage that a typed token reaches the plan's grouping merge
and a typed note reaches the Comments diff/apply, and that both reset between appends
(no leak across album selection). Clone the compilation-append test support. Pure-view
code stays untested.

## Out of scope

- **Persisting Grouping/Comments** on the registry entry, a policy, or `AppSetting` —
  ephemeral per-append by decision. If repeat-append retyping becomes a real pain,
  that is a later, evidence-backed slice (persisted default pre-filling the ephemeral
  fields), not this one.
- **Any other tag becoming manually editable at append time.** This milestone adds
  exactly Grouping (existing field, existing merge) and Comments (new field). A general
  per-append tag editor is not the ask.
- **Comments on recipes / as a recipe-driven field.** No recipe writes comments; the
  note is a manual channel only. If a policy should stamp a standing comment, that is a
  metadata-policy change, not this.
- **The live-show / setlist append surface.** Compilation append only, matching M8.
- **Any change to the write rail, `ApplyPlan`, or `FileOperation.writeTags` beyond
  adding the `comment` arg** — S0 extends the existing tag-args builders, it does not
  reshape the rail.

## Decisions (open — resolve before/at S0 review)

- **Comment separator → newline (`"\n"`), LOCKED** (Jon, 2026-07-10). Chosen for
  readability in Music's comment field. Make it a named constant; no S0-review
  re-litigation.
- **Grouping field granularity.** One token or a delimiter-split multi-token entry.
  Default: treat the field as a single token run through `mergedGrouping` (which already
  splits/normalizes on the grouping delimiter), so pasting a delimited string still
  works. Confirm no surprise if the user types the delimiter.
- **Comments = append confirmed** (not set) per Jon's wording. Flagged here only so it
  is not silently re-litigated at review.
