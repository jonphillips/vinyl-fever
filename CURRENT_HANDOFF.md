# Current Handoff

**Top-level "you are here" pointer — not a source of truth.** Native PR
draft/ready state and each milestone doc's slice ledger are canonical (per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`). This file only names
the active fronts, whose turn it is, and pending decisions — it points at the
canonical state and never restates PR/slice history. If it disagrees with GitHub,
GitHub wins; fix this file.

_Last touched: 2026-07-04 (M4 S2 merged #28 — M4 append complete; M5 Setlist
Normalizer ledger drafted)._

## Active fronts

- **M3 — live-show import + library verify**
  ([ledger](docs/milestones/M3-import-and-library-verify.md)). S0 + S1 merged
  (#19, #20). **S2 (library verify) is next**, folding the S1 review carry-over
  (live-read/`location` device check, per-track `add` batching, `add` return
  shape). S3 (`Working/` cleanup) after.
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
- **M5 — Setlist Normalizer (raw notes → `setlist.txt`) — BUILT 2026-07-04, in
  working tree (uncommitted).** ([ledger](docs/milestones/M5-setlist-normalizer.md)).
  Jon asked the architect to implement it directly (not a Codex dispatch). All three
  slices done in one pass: model changes + pre-segment + validator + renderer (S0),
  `SetlistNormalizer` via `LLMClientKit` prompt-and-parse (S1), preview-gate sheet +
  `setlist.txt` write + Settings Claude-key entry (S2). **`swift test` → 101 tests
  pass; the macOS app builds.** **Not yet committed / no PR / GUI unrun.** Two
  follow-ups: (a) commit + PR; (b) the real 18-file corpus isn't in the repo, so S0
  used inline fixtures — drop the corpus in for the golden-file pass. GUI needs Jon to
  run once (paste notes, enter key, save).

## Next up

1. **Land M5.** It's built + green in the working tree but uncommitted. Review the
   diff, commit on a branch, open the PR. Then two small follow-ups: drop the real
   18-file corpus in for a golden-file pass, and run the GUI once end-to-end (paste
   notes → enter a Claude key in Settings → Normalize → Save `setlist.txt`).
2. **The live-read device check is the master unblocker** for everything else:
   **M3 S2** (library verify), **M3 S3** (`Working/` cleanup), and both M4 remainders
   (Reconcile fast-follow + trusting the live certify leg) all wait on it. Running
   the macOS-27 beta-3 read-back spike **once** clears all four; they don't collide.
   This is Jon's spike to run.

## Pending Jon decisions

- **M5 implementer** — *resolved 2026-07-04:* architect implemented directly (not
  Codex). Remaining M5 asks are mechanical: commit + PR, and confirm the 18 raw
  fixture files can be committed as-is (M5 ledger *Decisions for Jon* #2).
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
