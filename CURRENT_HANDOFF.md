# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-05 (M6 S1 shell merged #33; S0 vocabulary→Settings merged
#32; M5 fully landed)._

## Active fronts

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

1. **M6 S2 (content polish)** — the only front that moves without the spike. Extract
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
