# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-03 (M4 S0+S1 merged #26; S2 dispatched)._

## Active fronts

- **M3 — live-show import + library verify**
  ([ledger](docs/milestones/M3-import-and-library-verify.md)). S0 + S1 merged
  (#19, #20). **S2 (library verify) is next**, folding the S1 review carry-over
  (live-read/`location` device check, per-track `add` batching, `add` return
  shape). S3 (`Working/` cleanup) after.
- **M4 — compilation-album append (first Phase 6)**
  ([ledger](docs/milestones/M4-compilation-album-append.md)). Build order + policy
  **merged** (#21); **scope append-only.** **S0 + S1 merged (#26)** — registry +
  folder seeding + policy-stamping engine + preview, all `Working/`-only, no import.
  **S2 (append + import + drift certification) dispatched** — build order written in
  the ledger, folds the #26 review carry-over (off-strip preview, m4a real-tool
  clearing assertion, `.jpg` fallback name). **First M4 slice to touch Music.app** —
  gated on the shared live-read/`location` device check. Codex's turn.
- **Setlist Normalizer — live-show path engine (NEW).** Spec **resolved**
  2026-07-03 against an 18-file raw corpus; see *Automation Implications* in
  [setlist-formatting-rules.md](docs/setlist-formatting-rules.md). Architecture
  settled (sandwich: deterministic pre-segment → frontier LLM JSON via
  `LLMClientKit` → deterministic validate → mandatory preview; source of truth =
  what's on the media). No milestone ledger yet; no slices started. **Key point:
  buildable now — pure text-in/JSON-out in `VinylFeverCore`, independent of macOS 27
  and the M3 beta-3 pause.**

## Next up

1. **Codex (executor):** open a draft PR for **M4 Slice 2** — append + import +
   drift certification, per the *Slice 2 build order* in the ledger. Land the **pure
   comparator + mock-snapshot tests first** (buildable now); the **live Music.app
   leg is gated on the shared live-read/`location` device check** — if still blocked
   on the macOS-27 beta-3 spike, ship the pure half and mark the live leg
   `question-for-architect`. New `.compilationCertify` `RunRecord.Kind` — surface it
   in the PR body. Build + tests green, then mark ready.
2. **M3 S2** (library verify) is the alternate front and shares that same live-read
   device check — doing the check once unblocks both. They don't collide.
3. **Setlist Normalizer:** draft a milestone ledger and decide the implementer
   (Codex slices vs. Jon hand-coding). First slice is the model-free bookends —
   deterministic pre-segment + validator with a golden-file test per corpus file —
   so it needs no `LLMClientKit` wiring to start.

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
