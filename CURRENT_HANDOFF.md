# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-02._

## Active fronts

- **M3 — live-show import + library verify**
  ([ledger](docs/milestones/M3-import-and-library-verify.md)). S0 merged (#19).
  **S1 is ready and awaiting architect review — [PR #20](https://github.com/jonphillips/vinyl-fever/pull/20).**
  S2 (library verify) and S3 (`Working/` cleanup) not started.
- **M4 — compilation-album append (first Phase 6)**
  ([ledger](docs/milestones/M4-compilation-album-append.md)). Build order + policy
  **merged** (#21); **scope confirmed append-only.** Not yet dispatched to Codex;
  no slices started.

## Next up

1. **Architect:** review [PR #20](https://github.com/jonphillips/vinyl-fever/pull/20)
   (M3 S1) against the M3 done-criteria — it's ready, so it's your turn.
2. Dispatch **M4 Slice 0 + Slice 1** to Codex as one batch (cohesive; both land
   before anything touches Music.app).

## Pending Jon decisions

- **M4 #2 / #3** (identity-match forgiveness; no-match behavior) — **deferred by
  design.** Answer after Slice 2 runs one real append and shows how Apple Music
  mangles the strings; don't pre-guess. M4 #1 decided (folder-seed only);
  #4/#5/#6 ride their documented defaults.
- **M3 live-read / `location` carry-over** — the Slice 0→1 review flagged that the
  live ScriptingBridge read + location-primary matching were never exercised
  against a real imported album (Music's "copy to Media folder" may make
  `location` point at the copied path, not `Output/`). Needs a device check before
  Slice 2 leans on it. See the carry-over notes in the M3 ledger.

## The rule

PR draft ⇄ ready is the handoff signal (whose turn). On approving a slice, update
this file's **Next up** as part of the approval — don't leave the pointer stale.
History lives in the PRs and the milestone ledgers, never here.
