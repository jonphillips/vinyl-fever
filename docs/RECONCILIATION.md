# Reconciliation — vinyl-fever ⇄ jon-platform (2026-07-04)

**What this is.** A grounding pass after M5 (Setlist Normalizer) landed in the
working tree ahead of its dependency being finished, plus the first live-dogfooding
bugs Jon hit on `main`. It names the one real seam between the two repos, the true
state of the LLM path in the running app, and splits the remaining work into
self-contained sessions. This is diagnosis + plan only — no code changed in the pass
that produced it.

Not a source of truth for milestone/slice state — `CURRENT_HANDOFF.md` and the M-doc
ledgers stay canonical. This file is a bridge document; delete or fold it once the
three sessions below are dispatched.

## The one real seam: LLMClientKit isn't closed

`vinyl-fever` took a `path:` dependency on `../../jon-platform/packages/LLMClientKit`
([Package.swift:20](../VinylFeverCore/Package.swift)) and built the **entire** M5
normalizer against it — Core `Normalizing/*`, the preview sheet, the prompts, 101
green tests — *before* LLMClientKit was finished and *without* wiring it into the live
app. That is the "vinyl-fever got out over its skis" instinct, made concrete: a
fully-built, unit-tested feature sitting inert on a dependency that isn't done.

### The LLM path is dead in the running app

The most important finding from dogfooding. There are **two** setlist surfaces and
they look alike but only one is meant to be smart:

- **Parse Setlist** → [`SetlistParser().parse()`](../VinylFever/Features/AppShell/AppModel.swift)
  (`parseSetlistInput`, ~line 106). 100% deterministic regex, no model, never reads
  the Anthropic key. This is the "Parsed Setlist" surface Jon saw and read as "dumb" —
  it is dumb *by design*; it parses the **output** shape, not raw notes.
- **Normalize Notes** (Live Shows toolbar) → `SetlistNormalizerSheet` →
  `normalizeSetlistInput()` → `setlistNormalizer.normalize()` → LLMClientKit
  `ModelClient`. This is the real transform.

But [`VinylFeverApp.swift`](../VinylFever/VinylFeverApp.swift) `prepareDependencies`
sets only six live clients (`scriptClient`, `audioMetadataClient`, `toolPathClient`,
`runLogClient`, `fileOperationClient`, `musicAppClient`). It **never** sets
`$0.setlistNormalizer` or `$0.modelClient`. So `setlistNormalizer` resolves to its
unimplemented `testValue` and throws an unimplemented-dependency issue the moment the
sheet is used. The Anthropic key is written to the Keychain
(`saveFrontierKey`, ~line 123) but **nothing consumes it**. This is consistent with
the handoff's "GUI unrun" note — the wiring gap is why.

### Divergence flags (spec vs. code)

- **Tier is hardcoded, not resolved.** M5's ledger promises `.frontierPreferred` via
  `FrontierResolver`, degrading to on-device when no key is set. The engine instead
  hardcodes `tier: .frontier(.anthropic)`
  ([SetlistNormalizer.swift:48](../VinylFeverCore/Sources/VinylFeverCore/Normalizing/SetlistNormalizer.swift)).
  Resolve in the integration session — this is also the "move to any frontier" intent
  from commit `7fe58fc`.
- **Parse vs Normalize is a UX trap.** The two buttons are visually peers with no cue
  that one is regex and one is the LLM. This is precisely what misled the dogfooding
  session. Fix as part of integration.

## The four dogfooding bugs

Independent of the LLM work except where noted.

1. **Compilations folder "hangs" — it's serial, not hung.**
   [`CompilationAlbumSeeder.candidates`](../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationAlbumSeeding.swift)
   walks folders one at a time and reads every file's tags one at a time, each
   spawning an `ffprobe`/`metaflac` subprocess. No concurrency, one indeterminate
   spinner, no per-album progress. Two aggravators: (a) **all-or-nothing** — a single
   unreadable file `throw`s and aborts the whole seed, unlike the show-folder path
   which catches per-file; (b) the show-folder read already uses a `TaskGroup`
   ([`refreshCurrentMetadata`](../VinylFever/Features/AppShell/AppModel.swift), ~line
   483) — seeding just never got that treatment. Fix: concurrency + progress +
   per-file partial failure.

2. **Append one-at-a-time "hangs" at "Importing into Music."**
   [`readAlbumTracks`](../VinylFever/Clients/MusicAppClient+Live.swift) enumerates the
   **entire** library's `fileTracks` over ScriptingBridge (`.get()` materializes all of
   them) and filters in Swift — and it runs **twice per append**, pre- and post-import
   for drift certification (`appendCompilationToMusic`, AppModel ~lines 712/715). On a
   real library that full Apple-Event materialization is brutally slow and looks hung;
   `add` also has no timeout. Fix: scope the read to the target album instead of the
   whole library, and add timeouts. (Overlaps the M3 S1 live-read carry-over already
   noted in the M3 ledger.)

3. **"The model is dumb" — see the seam section above.** No model in the Parse path;
   the real path is unwired. Not a model-quality problem.

4. **Album is a compilation but tracks aren't — by design.**
   [`proposedTags`](../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift)
   (~line 117) always adds `.isCompilation` to `clearedFields` and sets it false unless
   `ruleset.setCompilationFlag`. The policy unifies the album via a single
   **albumArtist** + grouping tokens rather than the iTunes compilation checkbox
   (which fragments/relocates tracks in Music). "Compilation: true → clear" per track
   is correct. Only fix needed: surface a one-line explanation in the diff so it
   doesn't read as a bug.

## Workplan — three sessions

Ordered by dependency. Session 3 shares nothing with 1–2 and can run in parallel.

1. **jon-platform — finish LLMClientKit.** Ship the `ModelClient` liveValue (tiered,
   BYO-key, shared-Keychain `apiKeyStore`) that vinyl-fever's
   `setlistNormalizer.liveValue` already expects, plus the `FrontierResolver`
   degrade-to-on-device path and the Keychain-entitlement contract. Shared dependency,
   so it goes first. Ground in `jon-platform/packages/LLMClientKit` and
   [[llmclientkit-shared-model-boundary]].

2. **vinyl-fever — land the normalizer integration.** Wire `$0.modelClient` +
   `$0.setlistNormalizer = .liveValue` in `prepareDependencies`; switch the engine
   from hardcoded `.frontier(.anthropic)` to the resolved tier; resolve the
   **Parse vs Normalize** UX so the LLM path is discoverable and distinct. Then the two
   M5 follow-ups from the handoff: commit + PR, drop the real 18-file corpus in for the
   golden-file pass, run the GUI once end-to-end. Depends on session 1.

3. **vinyl-fever — the dogfooding bugs (bugs 1, 2, 4 above).** Seeding concurrency +
   progress + partial-failure; Music import scoped-read + timeouts; compilation-flag
   explanation in the diff. Independent of the LLM work.

## What is NOT changing

The M1–M4 spine, the compilation-flag policy (bug 4 is a doc/UX fix, not a behavior
change), and the M3 beta-3 live-read spike gating (still Jon's to run). Bug 2's
scoped-read overlaps that carry-over but the perf fix stands on its own.
