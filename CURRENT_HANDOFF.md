# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-10 (M8 S0 merged (#46) — FK + `ProposedTags` merge core; the S0
review carry-over folded into the S1 execution map (#47). M8 S1 (bind + fused append,
app) is now the active turn)._

## Active fronts

- **M9 — manual append metadata** *(ungated, no device dependency)*
  ([ledger](docs/milestones/M9-manual-append-metadata.md)). Dogfooding ask (Jon,
  2026-07-10): a per-append affordance to type a **Grouping** token and a **Comments**
  note that ride along with the appended batch — held **ephemerally for that append
  only**, persisted nowhere. Grouping is a small extension (one more source into the
  existing `mergedGrouping` union); **Comments is a net-new tag field threaded
  end-to-end** (model → both parsers → both taggers → conditional diff), which is why
  it splits into **S0 (comments as a first-class tag, core)** and **S1 (append-time
  fields, app)**. S1 also bundles two same-screen dogfooding tweaks (bigger registry
  artwork; the Append Folder action moved out of the header into the selection-gated
  detail so it only shows once a collection is picked). Neither slice touches the schema
  or the Music.app live-read gate. Not yet dispatched — architect authored the ledger;
  Codex may open S0 whenever it wants a green ungated slice.

- **M8 — collection policy binding**
  ([ledger](docs/milestones/M8-collection-policy-binding.md)). **S0 (FK + `ProposedTags`
  merge, core) merged (#46)** — nullable `collectionPolicyID` (`ON DELETE SET NULL`),
  `RecipeTagMerge` (collection wins album identity; grouping unions), and
  `CompilationApplyPlan` accepting pre-computed recipe deltas. The S0 review carry-over is
  folded into the ledger's S1 execution map (#47) — chiefly that recipe
  `title`/`artist`/`sortAlbum` need a preview diff channel (they write but won't show
  otherwise), the `RecipeTagMerge` `clearedFields` asymmetry, and issue-gating being S1's
  job. **S1 (bind + fused append, app) is the active turn** — policy picker to set/clear the
  binding + `buildCompilationAppendPlan` running the bound policy's recipes into S0's plan
  build, one preview / one apply, issue-flagged proposals preview-gated. Ungated — no
  device dependency.

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
  ([ledger](docs/milestones/M7-collection-recipes.md)). **All slices merged — recipe
  workbench complete.** S0 (tables + deterministic runner) #40; S1 (recipe workbench,
  `Policies` section) #42 + runner-wiring fix #43; S2 (model-on classify stage) #44. The
  S1-boundary "fuse the two runs" question it deferred by design is now M8's subject
  (front above). No open follow-ups.
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

1. **M6 S2 (content polish)** — moves without the spike. Extract
   `PlanActionBar` from `PlanReadinessSummary` (split the button `HStack`/`can*`
   props from the `*RunStatus` calls) and relocate the status views into the **Output**
   tab (S1 left it a placeholder); condense `TrackPlanRow` to hoist album-level fields
   into one header; collapse the Output tab once terminal; and move the Source picker
   into the header (S1 kept it in the Setlist tab to stay a pure relocation).
2. **The live-read device check is the master unblocker** for everything else:
   **M3 S2** (library verify), **M3 S3** (`Working/` cleanup), and both M4 remainders
   (Reconcile fast-follow + trusting the live certify leg) all wait on it. Running
   the macOS-27 beta-3 read-back spike **once** clears all four; they don't collide.
   This is Jon's spike to run.
3. **One-true-import-folder fix** — ungated standalone slice (front above). Passthrough
   mp3/m4a copy-through into `Output/` so one folder holds every import-ready track.
   Good green slice to slot between spike-gated fronts; needs no device check.
4. **M9 S0 (comments as a first-class tag, core)** — ungated standalone, good green
   slice between spike-gated fronts. Thread a `comments` field through the read/write
   tag path (model → both parsers → both taggers → conditional diff) with an
   idempotent *append* merge (`appendedComment(source:note:)`), no UI. Follow the
   `grouping` field line-for-line. Full map + the byte-identical-unbound guarantee in
   the [M9 ledger](docs/milestones/M9-manual-append-metadata.md); S1 (append-time
   fields, app) follows.

5. **M8 S1 (bind + fused append, app)** — merged (#48). *(kept for history until the
   next handoff sweep.)*

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
