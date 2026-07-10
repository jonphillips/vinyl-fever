# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-10 (M8 milestone doc authored — collection↔policy binding,
answering M7 S1's deferred fuse question; the one-true-import-folder fix filed as a
standalone ungated slice below. Both are Codex's to open when it reaches them; M7 S1
remains the active turn)._

## Active fronts

- **M8 — collection policy binding**
  ([ledger](docs/milestones/M8-collection-policy-binding.md)). Specced, **not yet
  started.** Answers the fuse-the-runs question M7 S1 deferred by design: bind a
  `CollectionPolicy` to a `CompilationAlbum` (nullable FK, `ON DELETE SET NULL`) so one
  append runs the policy's recipes **and** the compilation stamping in one preview /
  one apply. No new pipeline — a pure `ProposedTags` merge (collection wins album
  identity; grouping unions) plus binding wiring. S0 (FK + merge, core) then S1 (bind +
  fused append, app). Ungated — no device dependency. **Sequenced after M7 S1** (it
  builds on the recipe runner S1 exercises).

- **Standalone fix — one true import folder** *(ungated, no milestone)*. Today the
  convert stage sends transcoded FLAC to `Output/` but leaves already-compatible
  mp3/m4a marked `verifyWorkingOnly` in `Working/`
  ([ConversionPlan.swift](VinylFeverCore/Sources/VinylFeverCore/Model/ConversionPlan.swift),
  `ConversionTrackPlan.init(applyTrack:outputDirectory:)`), so the finished set is
  split across two folders and Working still holds the transcoded-FLAC intermediates —
  the user hand-combines/sorts/deletes every append. **Slice DoD:** every import-ready
  track lands in **one** folder regardless of source format — passthrough mp3/m4a get a
  plain copy (no re-encode) into `Output/` and every track's `verificationFile` points
  there; `Working/` becomes pure scratch. Contained to
  [ConversionPlan.swift](VinylFeverCore/Sources/VinylFeverCore/Model/ConversionPlan.swift)
  (give passthrough tracks a real `Output` destination) +
  [ConversionExecutor.swift](VinylFeverCore/Sources/VinylFeverCore/Apply/ConversionExecutor.swift)
  (copy-through for passthrough, which today only converts); deterministic, fixture-
  testable, no device check. Related to but **distinct from** M3 S3 (`Working/`
  cleanup, which *is* spike-gated) — this one need not wait. Codex may open it any time
  it wants a green ungated slice between gated fronts.

- **M7 — collection recipes**
  ([ledger](docs/milestones/M7-collection-recipes.md)). **S0 (tables + deterministic
  model-off runner) merged (#40)** — `collectionPolicies`/`collectionRecipes`,
  `CollectionRecipeRunner`, and the shared `TextEvidence` verbatim guard. **S1 (recipe
  workbench) is specced and ready** — its execution map is authored in the ledger,
  with the two S1-boundary decisions (new top-level `Policies` section; recipe-run and
  append kept as separate gestures) recorded there. **Codex's turn: open the S1 draft
  PR.** No core changes in S1 — app-layer UI + `AppModel` wiring cloning the
  compilation-append flow.
- **M6 — live-show import UI refactor** *(the one unblocked front)*
  ([ledger](docs/milestones/M6-live-show-import-ui-refactor.md)). UX-only
  restructure of `LiveShowsView`; no core/schema/run-logic change, so **nothing here
  waits on the device spike.** Layout + Done behavior decided (Jon, 2026-07-05).
  **S0 (vocabulary→Settings) merged (#32); S1 (shell + four-tab scaffold) merged
  (#33)** — header/completion-pill/pipeline-strip/tab-bar + `pipelineStage` /
  `isShowComplete` / `clearScannedShow()` / `resetPlanRun()`, tab bodies still
  wrapping the existing sections unchanged. **S2 (content polish) is next.**
- **M3 — live-show import + library verify**
  ([ledger](docs/milestones/M3-import-and-library-verify.md)). S0 + S1 merged
  (#19, #20). **S2 (library verify) is next**, folding the S1 review carry-over
  (live-read/`location` device check, per-track `add` batching, `add` return
  shape). S3 (`Working/` cleanup) after. **Gated on the live-read spike (below).**
- **M4 — compilation-album append (first Phase 6)**
  ([ledger](docs/milestones/M4-compilation-album-append.md)). **All slices merged —
  append flow complete.** S0+S1 (#26) registry + policy-stamping engine; **S2 merged
  (#28)** — append + import + `.compilationCertify` drift certification, with the #28
  review's two comparator fixes folded in-branch (`028de3e`). **Two things remain,
  both deferred by design, both gated on the live-read spike:** the **Reconcile
  fast-follow** (re-point entry on drift + sharpen same-title/different-owner
  duplicate detection + resolve identity-match forgiveness on *real* mis-certify
  evidence) and trusting the **live certify leg** itself. Nothing to dispatch until
  the device check runs.

_M5 (Setlist Normalizer) fully landed (#30/#31): all three slices + the real 18-file
raw corpus and its golden-file pass are in `main`. No open follow-ups._

## Next up

1. **M7 S1 (recipe workbench)** — specced and ready; Codex opens the draft PR. New
   top-level `Policies` section: policy/recipe CRUD → live-sample preview over a picked
   folder → apply through the existing rail. App-layer only, no core. Full execution
   map + DoD in the [M7 ledger](docs/milestones/M7-collection-recipes.md).
2. **M6 S2 (content polish)** — moves without the spike. Extract
   `PlanActionBar` from `PlanReadinessSummary` (split the button `HStack`/`can*`
   props from the `*RunStatus` calls) and relocate the status views into the **Output**
   tab (S1 left it a placeholder); condense `TrackPlanRow` to hoist album-level fields
   into one header; collapse the Output tab once terminal; and move the Source picker
   into the header (S1 kept it in the Setlist tab to stay a pure relocation).
3. **The live-read device check is the master unblocker** for everything else:
   **M3 S2** (library verify), **M3 S3** (`Working/` cleanup), and both M4 remainders
   (Reconcile fast-follow + trusting the live certify leg) all wait on it. Running
   the macOS-27 beta-3 read-back spike **once** clears all four; they don't collide.
   This is Jon's spike to run.
4. **One-true-import-folder fix** — ungated standalone slice (front above). Passthrough
   mp3/m4a copy-through into `Output/` so one folder holds every import-ready track.
   Good green slice to slot between spike-gated fronts; needs no device check.
5. **M8 S0 (FK + `ProposedTags` merge)** — the fuse-the-runs milestone, sequenced after
   M7 S1 lands. Core-only, ungated. Full map in the
   [M8 ledger](docs/milestones/M8-collection-policy-binding.md).

## Pending Jon decisions

- **M6** — none open (the two layout/behavior forks were resolved 2026-07-05; see the
  ledger's *Locked decisions*).
- **M4 #2 / #3** (identity-match forgiveness; no-match behavior) — **deferred by
  design.** Answer after a real append runs and shows how Apple Music mangles the
  strings; don't pre-guess. Note: S2 merged but its **live** append leg is still
  gated on the beta-3 read-back check, so the evidence isn't in hand yet — these ride
  with the Reconcile fast-follow. M4 #1 decided (folder-seed only); #4/#5/#6 rode
  their documented defaults.
- **M3 live-read / `location` carry-over** — the Slice 0→1 review flagged that the
  live ScriptingBridge read + location-primary matching were never exercised
  against a real imported album (Music's "copy to Media folder" may make
  `location` point at the copied path, not `Output/`). Needs a device check before
  Slice 2 leans on it. See the carry-over notes in the M3 ledger.

## The rule

PR draft ⇄ ready is the handoff signal (whose turn). On approving a slice, update
this file's **Next up** as part of the approval — don't leave the pointer stale.
History lives in the PRs and the milestone ledgers, never here.
