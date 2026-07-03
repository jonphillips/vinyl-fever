# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-03._

## Active fronts

- **M3 — live-show import + library verify**
  ([ledger](docs/milestones/M3-import-and-library-verify.md)). S0 + S1 merged
  (#19, #20). **S2 (library verify) is next**, folding the S1 review carry-over
  (live-read/`location` device check, per-track `add` batching, `add` return
  shape). S3 (`Working/` cleanup) after.
- **M4 — compilation-album append (first Phase 6)**
  ([ledger](docs/milestones/M4-compilation-album-append.md)). Build order + policy
  **merged** (#21); **scope append-only.** **Dispatched: Slice 0 + Slice 1 as one
  batch** — both land before anything touches Music.app. Codex's turn.
- **M5 — LLM setlist normalization** (**next front**, Jon's pick 2026-07-03)
  ([ledger](docs/milestones/M5-llm-setlist-normalization.md)). Build order drafted;
  **awaiting Jon's go to dispatch.** First headless consumer of the query-profile
  catalog (jon-platform `ai-model-access.md` → Query profiles). Cross-repo, two PRs:
  **Slice 0** builds the catalog into `LLMClientKit` (jon-platform, lands first,
  **parallel-safe with the M4 batch**); **Slice 1** consumes it in `VinylFeverCore` +
  app (on-device-only v1, no key UI). Distinct area from M1–M4; blocks nothing.

## Next up

1. **Codex (executor):** open **one** draft PR batching **M4 Slice 0 + Slice 1** —
   registry model + folder seeding, then the policy-stamping engine + preview
   (writes to `Working/` copies only, no import). Build + tests green, then mark
   ready. Blocked → write it in the PR, label `question-for-architect`.
2. **Next front is M5** (LLM setlist normalization) — Jon's pick 2026-07-03,
   **awaiting his go to dispatch** (execution is a game-time call). M5 **Slice 0**
   (build the query-profile catalog into jon-platform `LLMClientKit`) touches no
   Vinyl Fever code and is **parallel-safe with the M4 batch** — it can start on
   Jon's word without waiting for M4. **M4 S2** (append + import + certify) and
   **M3 S2** (library verify) follow; none of the four collide.

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
