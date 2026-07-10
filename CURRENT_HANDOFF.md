# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-10 (handoff cleanup. M7/M8/M9 retired — all slices merged, no
open work; history in their ledgers/PRs. Live-read spike confirmed cleared on-device
(Jon). M3 descoped/closed (Jon) — live pipeline works on-device; S2/S3 automation slices
not needed. M10 authored.)_

## Active fronts

- **M10 — collection inbox (drag-drop track append)** *(ungated for S0/S1 staging/drain;
  the append it feeds reaches Music.app exactly as M8/M9)*
  ([ledger](docs/milestones/M10-collection-inbox.md)). **Authored 2026-07-10, all slices
  open.** Drop loose song files onto a compilation album → copy into an app-owned Inbox
  under Application Support (`Inbox/<albumID>/`) → the existing
  `buildCompilationAppendPlan(entry:sourceFolder:)` consumes that folder unchanged →
  certified append **trashes** the album's staged copies so the Inbox drains. New input
  adapter + new home, **not** a new pipeline. **S0** Inbox store (core, filesystem is
  truth, no schema); **S1** drop target + drain wiring + no-policy nudge (app); **S2**
  Inbox visibility surface (the "assurance it emptied" ask). Load-bearing decisions
  locked (fixed AppSupport root; Trash-after-certify-under-root-only); the rest are
  Codex-callable defaults. Codex may open S0 any time — no device check.

- **M6 — live-show import UI refactor** — **S2 remainder only**
  ([ledger](docs/milestones/M6-live-show-import-ui-refactor.md)). UX-only, ungated. #50
  landed just the `TrackPlanRow`/`LibraryTrackResolutionRow` condensing (and didn't tick
  the ledger). Still open: extract `PlanActionBar` from `PlanReadinessSummary`; relocate
  the run-status views into the **Output** tab (S1 left it a placeholder) and collapse it
  once terminal; move the Source picker into the header. Mark S2 in the ledger when it
  lands.

- **M4 — compilation-album append** *(append flow complete; in daily use — it is the base
  M8/M9/M10 build on)* ([ledger](docs/milestones/M4-compilation-album-append.md)). All
  slices merged (#26/#28). The spike clears the **live certify leg** (pre/post reads
  around `MusicAppClient.add` — now trustable). The one real remainder is the **Reconcile
  fast-follow** (re-point the registry entry when identity drift is found + sharpen
  same-title/different-owner duplicate detection), and it is **evidence-gated by design**:
  build it only when a real append actually spawns a `Great Covers 2` drift. None observed
  in daily use yet — so nothing to dispatch.

- **Standalone — one-true-import-folder fix** *(ungated, no milestone)*. Passthrough
  mp3/m4a still land `verifyWorkingOnly` in `Working/` while transcoded FLAC goes to
  `Output/`, so a finished set is split across two folders
  ([ConversionPlan.swift](VinylFeverCore/Sources/VinylFeverCore/Model/ConversionPlan.swift),
  [ConversionExecutor.swift](VinylFeverCore/Sources/VinylFeverCore/Apply/ConversionExecutor.swift)).
  **DoD:** every import-ready track lands in **one** folder — passthrough mp3/m4a get a
  plain copy (no re-encode) into `Output/`, every track's `verificationFile` points there,
  `Working/` becomes pure scratch. Deterministic, fixture-testable, no device check. A good
  green slice to slot between other fronts.

## Recently landed (detail lives in the ledgers/PRs, not here)

M5 setlist normalizer (#30/#31) · M7 collection recipes (#40/#42/#43/#44) · M8 policy
binding (#46/#48) · M9 manual append metadata (#51/#52/#53). No open follow-ups on any.

## Next up

1. **M10 S0** — Inbox store (core, ungated). Ready to start.
2. **M6 S2 remainder** — the UI splits above; ungated, moves any time.
3. **One-true-import-folder fix** — ungated standalone; single folder for every
   import-ready track.

*(The M4 Reconcile fast-follow is evidence-gated, not spike-gated — see below — so it is
not queued here.)*

## Pending Jon decisions

- **M4 identity-drift decisions (#2/#3) + the Reconcile fast-follow.** Still evidence-
  gated: decide the identity-match-forgiveness and no-match behavior *when* a real append
  actually mangles a title into a `Great Covers 2`. Daily use has surfaced none yet, so
  there is nothing to decide today — this stays parked until the evidence appears.

## The rule

PR draft ⇄ ready is the handoff signal (whose turn). On approving a slice, update this
file's **Next up** as part of the approval. History lives in the PRs and the milestone
ledgers, never here.
