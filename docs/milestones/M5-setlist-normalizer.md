# Milestone 5 — Setlist Normalizer (raw notes → `setlist.txt`)

*Build order for the executor. Architect/editor-in-chief: this doc is the contract.
The resolved spec is in [../setlist-formatting-rules.md](../setlist-formatting-rules.md)
(**Automation Implications** onward — the sandwich, the LLM output contract, the
controlled source vocabulary, the resolved decisions), the model boundary is
`/Users/jon/code/jon-platform/packages/LLMClientKit`, and the house stance is
`/Users/jon/code/jon-platform/AGENTS.md`. Where this doc and those conflict, stop
and flag it — don't silently diverge.*

## Sequencing note (architect → Jon)

This is a **new product front**, parallel to the live-show/compilation path
(M1–M4). Its defining property is **independence**: it is pure text-in / JSON-out
in `VinylFeverCore`, so it does **not** depend on macOS 27, the Music.app import
surface, or the M3 beta-3 device-check pause ([m3-paused-until-beta3]). It is
buildable and dogfoodable **now**, which is exactly why it is queued next while
M3 S2 / M4's live certify leg / the M4 Reconcile fast-follow all sit behind the
shared live-read spike. Nothing here touches Music.app.

**Open sequencing decision (Jon's, not the executor's):** whether M5 is sliced by
Codex like M1–M4, or hand-coded by Jon. Slice 0 is deliberately model-free so it
can start either way. Flagged in `CURRENT_HANDOFF.md`; resolve before dispatch.

## The milestone in one sentence

Turn the *other* text artifact — noisy raw trading notes — into a previewable,
normalized `setlist.txt` via the resolved **sandwich** (deterministic pre-segment
→ frontier LLM emitting structured JSON → deterministic validate → mandatory human
preview), where the source of truth is **what is physically on the media**, never
a reconstructed show, and no source label is ever invented.

## Why this is M5 (and where it stops)

The existing `SetlistParser` parses the **output** shape (`ARTIST:`/`ALBUM:` tags,
`NN. Title` lines). Run against raw notes it emits garbage — treating headers,
`Source:` lines, hash blocks, and prose as tracks. The unbuilt, hard problem is the
**transform raw → normalized**, and the 18-file corpus review (2026-07-03) proved
even "find the actual track list" is a semantic judgment. So deterministic parsing
cannot *lead* — but it earns its place as the two bookends around the model.

- **The model does the judgment; the bookends make it trustworthy.** Pre-segment
  hints (never decides); the LLM interprets; the validator refuses invented sources
  and malformed shapes; preview is mandatory even at high confidence.
- **It reuses the shared model boundary, adds no library work.** Consume
  `LLMClientKit` as a path dependency and mirror Galavant's `HoursExtractor`
  (same shape: structured data out of messy free text, *always extraction, never
  invention*). Prompt-and-parse to start; promote to forced `ModelTool` only if the
  nested arrays prove unreliable — see [llmclientkit-shared-model-boundary].
- **BYO-key, degrades gracefully.** Request `.frontierPreferred` via
  `FrontierResolver`; the boundary degrades to on-device only when *no* key is
  configured, so the Normalizer never branches on key presence. Keys reuse the
  shared iCloud-Keychain `APIKeyStore` — a Claude key entered in Galavant or Yes
  Chef is already visible here.

Where it stops: this is the raw→`setlist.txt` transform + its preview/write. It
does **not** tag audio, import to Music.app, or touch the M1–M4 spine.

## Definition of done

A reviewer can, in the running macOS app:

1. **Paste or drop raw trading notes** (pasted text or a `.txt` file) and get a
   normalized draft: tags (artist, album artist, date, venue, location, **source**),
   an ordered track list (with optional per-track notes), and an **audit of what was
   dropped**.
2. **See the preview before any write** — every file, every time, even at high
   confidence. The preview shows the proposed `setlist.txt`, the inferred `source`
   with the quoted `sourceEvidence` it came from, and the `dropped[]` lines.
3. **Trust the guardrails** — a draft that fails validation (missing required tags,
   bad `ALBUM`/`DATE` shape, a `source` not in the controlled vocabulary or without
   evidence in the input, `|` inside a Grouping token, insane track count) is marked
   **low-confidence and forced to review**, never auto-written.
4. **Approve → write `setlist.txt`.** Only on explicit approval is the file written.

Invariants that must hold at merge:

- `swift build` / `swift test` green. The **deterministic bookends and the JSON
  contract are covered offline** — pre-segment region classification and the
  validator by golden-file tests per corpus file; the model leg via `StubModelClient`
  (`testValue` returns nothing, so the deterministic path stays the tested default).
  A live frontier call is never the only coverage and never required by a test.
- **No auto-write, ever.** Preview gates every write. Grep-able: the only file write
  is behind the approval action.
- **No invented sources.** The validator confirms the emitted `sourceEvidence`
  string actually appears in the input; a source absent from the controlled
  vocabulary fails.
- House stack honored: no TCA, no SwiftData; value-type records; `@Observable`
  feature model; `@Dependency` clients (`\.modelClient`, `\.apiKeyStore`);
  swift-navigation for the preview/settings destinations.

## In scope

- **Model changes** (small, in `Model/`): `ShowTags` gains an explicit `source:
  Field` (today implied inside `ALBUM`); `SetlistTrack` gains `note: String?`.
- **Pre-segment** (pure, `Parsing/` or new `Normalizing/`): CRLF/BOM/whitespace
  normalization; excise FFP/MD5/shntool hash blocks; classify candidate regions
  (`header` | `tracklist` | `lineage` | `prose`). Annotates only — decides nothing.
- **LLM output contract** (value type): `tags{…, source}`, `tracks[{title, note,
  confidence}]`, `sourceEvidence`, `confidence`, `dropped[]` — Codable, the JSON in
  the spec's *LLM output contract* section.
- **`SetlistNormalizer`** (`Sendable` struct + `DependencyKey`, mirrors
  `HoursExtractor`): live builds `ModelRequest(system:prompt:)` (system = the rules
  doc + controlled vocabulary + contract), calls `modelClient.complete`, defensively
  slices/parses the JSON out of `response.text`; malformed output → low-confidence
  draft, never a crash.
- **Validate** (pure): required tags present; `ALBUM`/`DATE` (ISO) shape; `source`
  in the controlled vocabulary **and** `sourceEvidence` present in input; no `|` in a
  Grouping token; track-count sanity vs. the source region. Failure marks
  low-confidence, does not auto-fix.
- **Preview + write** (`@Observable` feature model + view): render the proposed
  `setlist.txt`, source-evidence, and dropped audit; approve → write.
- **Key entry** (only net-new UI beyond preview): a small per-app settings screen
  bound to `\.apiKeyStore`, needed only if the user enters the key inside Vinyl
  Fever rather than relying on the synced one.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Honoring embedded per-file formatter instructions ("format these like…") | **fast-follow, gated behind preview** | It's also the prompt-injection surface; decide deliberately when first hit |
| Auto-correcting impossible/typo dates (month `22`) | **stays a validator flag** | Flag to low-confidence review; never guess a correction |
| Forced `ModelTool` structured output + shared JSON helper in LLMClientKit | **promote if prompt-and-parse proves unreliable** | Rule of three (Hours + Evaluation + this); no library change needed to ship |
| On-device / tiered escalation for this feature | **later optimization** | Frontier-only to start; the reasoning cases need it |
| Tagging audio / importing the normalized show to Music.app | **the M1–M4 path** | M5 stops at `setlist.txt`; it's the input-side transform |

## Architecture & module layout

```
VinylFeverCore/Sources/VinylFeverCore/
├── Model/         # ShowTags += source: Field; SetlistTrack += note: String?
├── Normalizing/   # + pure: pre-segment (region hints), NormalizedDraft contract
│                  #   (Codable), validator — no model, no I/O
├── Clients/       # + SetlistNormalizer (DependencyKey, mirrors HoursExtractor);
│                  #   reuse @Dependency(\.modelClient), \.apiKeyStore from LLMClientKit
└── (Parsing/      # existing SetlistParser parses the OUTPUT shape — untouched)
```

`Package.swift`: add `.package(path: "../../jon-platform/packages/LLMClientKit")`
(2 levels up from `VinylFeverCore/`; Galavant uses 3) and its product to the target.
**Boundary rule:** the pre-segment, the contract type, and the validator are pure and
model-free; the actual frontier call lives behind `\.modelClient` so the whole
sandwich is unit-testable offline with `StubModelClient`.

## Domain model (shape, not final — refine in code, flag big changes)

```swift
// Model changes ------------------------------------------------------
// ShowTags += var source: Field = .unknown
// SetlistTrack += var note: String? = nil

// LLM output contract (Codable) --------------------------------------
enum DraftConfidence: String, Codable, Sendable { case high, low }

struct NormalizedTrack: Codable, Equatable, Sendable {
  var title: String
  var note: String?
  var confidence: DraftConfidence
}
struct NormalizedTags: Codable, Equatable, Sendable {
  var artist, albumArtist, date, venue, location, source: String
}
struct NormalizedDraft: Codable, Equatable, Sendable {   // what the model emits
  var tags: NormalizedTags
  var tracks: [NormalizedTrack]
  var sourceEvidence: String          // must appear in the input — the anti-invention check
  var confidence: DraftConfidence
  var dropped: [String]               // audit trail for the preview
}

// Pre-segment hints (bookend 1) --------------------------------------
enum RegionKind: Equatable, Sendable { case header, tracklist, lineage, prose }
struct RegionHint: Equatable, Sendable { var kind: RegionKind; var text: String }

// Validation (bookend 3) ---------------------------------------------
enum ValidationIssue: Equatable, Sendable {
  case missingTag(String)
  case badAlbumShape, badDate
  case sourceNotInVocabulary(String)
  case sourceEvidenceNotInInput
  case pipeInGroupingToken
  case trackCountImplausible(count: Int)
}
struct NormalizationResult: Equatable, Sendable {
  var draft: SetlistDraft              // the existing output type, populated
  var issues: [ValidationIssue]        // empty ⇒ high-confidence; non-empty ⇒ forced review
  var dropped: [String]
}
```

`source` is a first-class `Field`, not a substring of `ALBUM`. `sourceEvidence`
existing-in-input is the mechanism that makes "no invented source" *checkable*.

## The slices (each is one PR into `main`)

`main` is protected — each slice is a branch + PR, small enough to review in one
sitting, each ending green (build + tests). The executor ticks the box in the slice
PR that completes it; GitHub PR state is canonical.

- [x] Slice 0 — Model changes + pre-segment + validator + renderer (model-free)
- [x] Slice 1 — `SetlistNormalizer` via LLMClientKit; wire the full sandwich (no UI)
- [x] Slice 2 — Preview gate + write `setlist.txt` + per-app key-entry screen

> **Built in one pass 2026-07-04 by the architect (Jon asked for direct
> implementation, not a Codex dispatch).** Core is green: `swift test` → **101 tests
> in 24 suites pass**, including the new `SetlistPreSegmenter`,
> `SetlistNormalizationValidator`, `SetlistText`, and `SetlistNormalizer` suites. The
> macOS app target builds (`xcodebuild … -skipMacroValidation` → BUILD SUCCEEDED). The
> **preview/settings SwiftUI is compile-verified only — GUI behavior is unrun** and
> needs Jon at the keyboard (paste real notes, enter a Claude key, save a file).
>
> **Corrections to the pre-build API notes above (written from memory; verified
> against the real headers):** `LLMClientKit` has **no `FrontierResolver` /
> `.frontierPreferred`** — the tier is `ModelTier.frontier(.anthropic)`, used
> directly. `StubModelClient` **does** exist (in `TieredModelClient.swift`;
> `.constant(_:)` / `.echo`). `HoursExtractor`/Galavant are **not in this checkout**,
> so the client follows the local `@DependencyClient` idiom (like
> `AudioMetadataClient`) rather than the bare-struct shape, with a `LiveSetlistNormalizer`
> engine holding `modelClient` + an id source so the pipeline is testable without a
> live model. `SourceLabel` **already models the controlled vocabulary** (`builtInTokens`),
> so the validator and the prompt both source their vocab from it — no second list.
>
> **One deviation from the S0 plan, needs Jon:** the real 18-file corpus lives in a
> prior working session, **not in the repo**, so it could not be committed as
> fixtures. S0's tests use representative inline cases instead. **Drop the real corpus
> under `VinylFeverCore/Tests/VinylFeverCoreTests/Fixtures/RawSetlists/` and add a
> golden-file pass** to get the per-corpus-file regression signal the plan called for.

### Slice 0 — Deterministic bookends (no model)

The model-free half, buildable with zero LLMClientKit wiring. **Commit the 18-file
raw corpus** as test fixtures first (it lives in the working session, not yet in the
repo — check it in under `VinylFeverCoreTests/Fixtures/RawSetlists/`). Add the model
changes (`ShowTags.source`, `SetlistTrack.note`) and the `NormalizedDraft` contract
type. Build **pre-segment** (CRLF/BOM/whitespace normalize, excise hash blocks,
classify regions) and the **validator** (required tags, ALBUM/DATE shape, source ∈
controlled vocabulary with `sourceEvidence` present in input, no `|` in Grouping,
track-count sanity). **Tests:** golden-file per corpus file for region classification
(hash blocks excised, tracklist region found); validator table over hand-authored
`NormalizedDraft`s (each `ValidationIssue` triggered + a clean pass). **Done when:**
every corpus file pre-segments without crashing and the validator's pass/fail is
pinned by golden tests — all with no model call.

### Slice 1 — Model leg + wired sandwich (no UI)

Add the `LLMClientKit` path dependency. Build `SetlistNormalizer` (`Sendable` +
`DependencyKey`, mirroring `HoursExtractor`): live builds the `ModelRequest` (system
= rules doc + controlled vocabulary + contract), calls `modelClient.complete`,
defensively parses the `NormalizedDraft` JSON out of `response.text`, degrading to a
low-confidence draft on malformed output. Wire the full sandwich: pre-segment (S0) →
normalizer → validate (S0) → `NormalizationResult`. Request `.frontierPreferred`.
**Tests:** the sandwich end-to-end with `StubModelClient` returning canned JSON —
clean high-confidence, malformed-JSON degradation, a validator-caught invented
source; `testValue` returns nothing so no test hits a live model. **Done when:** a
raw fixture drives a `NormalizationResult` offline and the parse/degrade/validate
seams are pinned.

### Slice 2 — Preview gate + write + key entry

The dogfood surface. An `@Observable` feature model + view render the proposed
`setlist.txt`, the inferred source with its quoted `sourceEvidence`, per-track
confidence, and the `dropped[]` audit. **Mandatory preview — no auto-write even at
high confidence.** Approve → write `setlist.txt` (behind a `FileOperationClient`
seam, the only write). Add the small per-app settings screen bound to
`\.apiKeyStore` (the library ships the store + `masked()`, not the screen).
**Tests:** feature-model state (approve writes / cancel doesn't; a low-confidence
result surfaces issues and still requires explicit approval). **Done when:** Jon
pastes raw notes, sees the preview + dropped audit, approves, and a correct
`setlist.txt` lands — with the key read from the synced store or entered in-app.

## Constants register (pre-justified — jon-platform "constants need a rationale")

- **Controlled source vocabulary is fixed by the spec** (`(SBD)`, `(D-SBD)`,
  `(DSBD)`, `(AUD)`, `(FM)`, `(ALD)`, `(Matrix)`, `(SBD/ALD)`, `(SBD/AUD)`,
  `(unknown)`, …). The validator draws from it; do not extend it in code without
  updating [../setlist-formatting-rules.md](../setlist-formatting-rules.md) first.
- **Grouping delimiter = ` | `** (inherited from the policy doc; a `|` *inside* a
  token is a validation failure, not a silent join).
- **Source of truth = the media.** Use the structured numbered/disc list; drop
  prose "complete set" re-lists and "not recorded" songs; keep **both** sub-sets
  when a release physically holds two (early+late show, main+radio session).
- **Model tier = frontier / BYO-required.** Degrades to on-device only with no key
  at all; the prose-inference, dirty-OCR, and multi-line-jam cases lean on reasoning
  the on-device tier can't yet be assumed to reach.
- **Preview is unconditional.** No confidence threshold auto-writes; trust comes
  from seeing what was dropped.

## Decisions for Jon to confirm (not the executor's to make alone)

1. **Implementer & sequencing:** Codex slices (like M1–M4) or Jon hand-codes M5?
   Slice 0 is model-free so it starts either way. *(No lean — Jon's call.)*
2. **Corpus provenance:** confirm the 18 raw files can be committed as fixtures
   as-is (personal notes; check for anything not wanted in the repo). *(Lean: commit;
   they're the only real regression signal.)*
3. **Structured output strategy:** start prompt-and-parse and promote to forced
   `ModelTool` only if the nested arrays prove unreliable? *(Lean: yes — house
   style; promotion is also the rule-of-three moment to lift a shared JSON helper
   into LLMClientKit.)*
4. **Embedded formatter instructions** (deferred): honor-behind-preview, or ignore
   for now? *(Lean: defer — it's the prompt-injection surface; decide when hit.)*

## Working agreement

- Each slice: branch → PR → merge (main protected; self-merge after the
  architect's `approve`). Commit messages end with the `Co-Authored-By` trailer;
  PR bodies end with the tool trailer.
- Tests with swift-testing; control the model/keys/files/uuid via `@Dependency`.
  Every deterministic path is covered offline; the frontier call is never the only
  coverage and never required by a test (`StubModelClient` for the model leg).
- Prefer the installed `swiftui-*`/`pfw-*` skills + LLMClientKit headers over memory
  for `ModelClient` / `ModelRequest` / `APIKeyStore` shapes — they may be past the
  model's training cutoff.
- Surface any new tag/contract-field/constant in the PR description; flag, don't
  bury. If the model invents a source the validator can't tie to input evidence,
  that's a *fail-to-review*, never a silent write.
