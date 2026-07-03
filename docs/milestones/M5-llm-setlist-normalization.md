# Milestone 5 — LLM setlist normalization (messy text → canonical setlist)

*Build order for Codex. Architect/editor-in-chief: this doc is the contract. The
output format is [../setlist-formatting-rules.md](../setlist-formatting-rules.md)
(the model's target and system prompt); the model boundary + the query-profile
catalog are jon-platform `docs/ios/ai-model-access.md` → **Query profiles** and
`ai-model-access.md` at large; the strategic arc is
[../implementation-plan.md](../implementation-plan.md) (this enhances the Phase 1.5 /
Phase 3 setlist ingest — it is not a new phase). Where this doc and those conflict,
stop and flag it — don't silently diverge.*

## Sequencing note (architect → Jon)

- **First headless consumer of the query-profile catalog** (`ai-model-access.md` →
  Query profiles). This milestone is where that catalog gets *built*, per the "build
  at the first headless consumer, not before" rule in that section.
- **Distinct product area from the live-show import path (M1–M4).** It sits on the
  M1 setlist-ingest surface, does **not** depend on M3/M4, and does **not** block
  them. The in-flight M4 Slice 0+1 batch is unaffected.
- **Cross-repo, two PRs, jon-platform first** (same order as the LLMClientKit lift,
  ADR-0011): Slice 0 builds the catalog into `LLMClientKit` (jon-platform); Slice 1
  consumes it in `VinylFeverCore` + app. Slice 0 touches no Vinyl Fever code, so it
  is **parallel-safe with the M4 batch** — but whether M5 preempts finishing M4/M3 or
  follows them is **Jon's call**; the architect will not reorder the queue
  unilaterally.

## The milestone in one sentence

Turn messy pasted / `.txt` show notes into the canonical `setlist.txt` format with a
language model, then hand the result to the **existing deterministic `SetlistParser`**
— which stays the sole `String → SetlistDraft` authority *and* the validator — so a
clean normalize improves the draft, a bad one **silently falls back to today's raw
parse**, and the human edits either way.

## Why this is M5 (and where it stops)

- **LLM-first, deterministic-as-validator** (`technical-architecture.md:64`; M1's
  "ultimately LLM-first with the deterministic layer as validator"). The model
  reformats messy text to a spec we already own (`setlist-formatting-rules.md`); the
  parser validates by *successfully parsing it*. No bespoke JSON schema, no second
  copy of the tag/track logic — `SetlistParser.parse` stays the one authority.
- **On-device floor ⇒ no key UI in v1.** `QueryProfile.structuredExtraction` is
  `.frontierPreferred`; with no frontier key configured, `FrontierResolver` degrades
  it to **on-device** (FoundationModels, macOS 27). So v1 ships with **zero
  Keychain/settings surface** — reformatting to a text spec is well within on-device
  reach — and BYO-key frontier becomes a purely additive later opt-in (a Vinyl Fever
  first: it has no AI surface today).
- **Single insertion point.** `AppModel.swift:87` (`setlistDraft =
  SetlistParser().parse(setlistInput)`) is the one normalize call; the normalizer
  wraps exactly this. `setlistInput` / `setlistDraft` / `setlistErrorMessage` already
  exist.
- **Reuses the whole draft/edit UI.** `SetlistDraft`, the editable draft surface, and
  `ShowPlan` are unchanged — the model just produces better text to parse.

**Where it stops:** no key-entry/settings UI, no in-app provider switcher, no
streaming (one-shot `complete`), web search off (`webSearchMaxUses = nil`). The
deterministic parser and hand-edit remain the safety net for every input.

## Build order

### Slice 0 — the catalog (jon-platform / `LLMClientKit`, lands first)

Build `TierIntent`, `FrontierResolver`, and the `QueryProfile` catalog exactly as
specified in `ai-model-access.md` → Query profiles (Policy A; the FUTURE note as a
comment). No Vinyl Fever changes. Tests (no network): the resolver's four cases
(no key → `.onDevice`; preferred present → preferred; preferred absent, other present
→ other, **never overriding the user**; nothing configured → `.onDevice`) and
`QueryProfile.request` wiring.

### Slice 1 — the consumer (Vinyl Fever)

1. **Dependency.** Add `.package(path: "../../jon-platform/packages/LLMClientKit")`
   to `VinylFeverCore/Package.swift` and the `LLMClientKit` product to the
   `VinylFeverCore` target. (Confirm the relative path resolves and the product name
   against `LLMClientKit/Package.swift`.)
2. **`SetlistNormalizer`** (`VinylFeverCore/Sources/VinylFeverCore/Parsing/`): a
   `@DependencyClient`-style client (matching the repo's swift-dependencies usage)
   with `normalize(_ raw: String) async throws -> String` returning canonical
   `setlist.txt` text. Live impl:
   `modelClient.complete(QueryProfile.structuredExtraction.request(resolvedTier:
   resolver.resolve(.frontierPreferred), system: SetlistFormattingPrompt, prompt: raw))`,
   return `response.text`. Injects LLMClientKit's `@Dependency(\.modelClient)` and a
   `FrontierResolver`. `SetlistFormattingPrompt` is an embedded string constant that
   mirrors `docs/setlist-formatting-rules.md` (a pure core does no bundle/file IO;
   add a "keep in sync with setlist-formatting-rules.md" note at the constant).
3. **Plug into `AppModel`** at the `:87` normalize point: `normalize(raw)` →
   `SetlistParser().parse(normalized)`; **validate** (tracks non-empty **and** not
   fewer tracks than the raw parse, tags no worse) → on failure *or* thrown/unavailable
   → `SetlistParser().parse(raw)` (today's behavior). Keep it `async`; show a light
   "normalizing…" state; normalization errors are non-fatal (fall back, never surface
   as an error the user must clear).
4. **Tests** (`VinylFeverCore`, no network): stub `ModelClient` → canonical text →
   normalizer → parser → expected `SetlistDraft`; fallback path (stub throws / returns
   garbage → raw parse used, draft never worse); 2–3 messy fixtures (disc/set/encore
   headers, numbered tracks, footnote markers, a misspelling) asserting the
   normalized-then-parsed draft. On-device live path is device-only (sim has no Apple
   Intelligence) → **Jon device pass**.

## Definition of done

A reviewer, in the running macOS app:

1. **Pastes a messy setlist** (disc/set/encore headers, numbered tracks, footnote
   markers, a misspelling) → normalizes → the draft shows clean tags + a flat track
   list matching `setlist-formatting-rules.md`, editable exactly as today.
2. **Pastes an already-canonical setlist** → the draft is no worse than today's raw
   parse (normalization is idempotent-ish, never destructive).
3. **Pastes something the model mangles, or runs with no model available** → the draft
   falls back to today's raw parse; no crash, nothing emptier than before.
4. `swift test` (`VinylFeverCore`) green; `LLMClientKit` tests green; `check-drift`
   clean; **Jon device pass** on the on-device normalize path (frontier path deferred
   with the key UI).

## Open questions for Jon / implementer

- **Validation accept bar:** "normalized parse has ≥ raw track count and tags no
  worse" (conservative — never lose tracks to a bad normalize) vs. plain "tracks
  non-empty." Start conservative; confirm after one real run against Jon's own show
  notes. *(This is the Vinyl Fever analog of ADR-0011's "prove the shape on real
  data" — don't pre-tune the bar.)*
- **Frontier opt-in (BYO key):** ride M5 as a Slice 2 (key-entry UI + provider
  switcher, mirroring yes-chef's `AISettingsView`) or a later milestone? **Recommend
  later** — v1 on-device-only keeps this front tight and proves the extract→validate
  shape before adding the Keychain surface.
- **System-prompt source:** embedded constant (recommended, pure core) vs. loading
  the doc — confirm the embedded copy is the intended coupling to
  `setlist-formatting-rules.md`.

---
*First consumer of the query-profile catalog (`ai-model-access.md` → Query profiles).
The catalog is built here (Slice 0) and proven here (Slice 1); the pattern promotes to
a jon-platform cross-app ADR once Yes Chef also consumes it.*
