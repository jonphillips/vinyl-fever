# Milestone 6 — Live-show import UI refactor

*UX refactor of the existing live-show import surface (Phase 5 —
[M1](M1-live-show-plan-preview.md)/[M2](M2-live-show-apply-convert.md)/[M3](M3-import-and-library-verify.md)).
No new capability, no schema change, no core-logic change — this restructures
`LiveShowsView` only. Rules in [../technical-architecture.md](../technical-architecture.md)
and `/Users/jon/code/jon-platform/AGENTS.md` still apply; where this doc and those
conflict, stop and flag it.*

## The milestone in one sentence

The live-show import screen works end-to-end but is one long undifferentiated
scroll (~8–10 screen-heights) that mixes inputs, actions, a streaming run log,
duplicated metadata, and history at equal weight — **restructure it into a fixed
header + pipeline-stage strip + a four-tab body, move global config out to
Settings, and give the flow a terminal "Done" state** — without touching
`AppModel`'s run logic or `VinylFeverCore`.

## Why now

M1–M3 proved the pipeline; M5 wired the normalizer in. The flow is correct but
the surface doesn't reflect its own structure. It is a *pipeline* (files → parse
setlist → build plan → apply/verify/import → resolve) presented as a flat
document. Concrete problems, all confirmed in the code:

- **No terminal state.** `scanShowFolder` resets state on *entry*
  (`AppModel.swift:71`); nothing ever sets `scannedShowFolder = nil`, so there is
  no way to clear a finished show. There is no "Done".
- **No pipeline-stage rollup.** Progress is spread across five independent states
  (`applyState`, `conversionState`, `verificationState`, `libraryImportState`,
  `libraryReadState`, `AppModel.swift:50-54`). Nothing derives "where am I".
- **Metadata shown 4+ times.** Album/Sort Album/Artist/Album Artist appear in the
  source section, `ProposedMetadataSummary`, and identically in all 11
  `TrackPlanRow`s — ~40 redundant rows that never vary.
- **Execution detail is primary content.** File copy/tag operations
  (`ApplyOperationsPreview`) and the five `*RunStatus` walls render full-height
  inline, forever.
- **Global config lives inside a single show.** The source-label Vocabulary editor
  (`SourceMetadataSection`, `LiveShowsView.swift:1284-1310`) is app-global,
  mostly locked built-ins, identical for every show.

## Locked decisions (Jon, 2026-07-05)

1. **Layout:** fixed top region (header + completion pill + pipeline strip + tab
   bar) over a single scrolling tab body. Four tabs: **Setlist · Plan · Output ·
   History**.
2. **Inputs grouping:** the audio-file list, setlist text editor, detected-files
   chips, and cover art all live under the **Setlist** tab (chosen over
   expandable stage cards — lower risk, keeps the linear flow).
3. **Done action:** returns to the empty state. `clearScannedShow()` sets
   `scannedShowFolder = nil` and resets run state; `LiveShowsView` then falls back
   to `EmptyLiveShowsView` automatically. No persistent imported-show list (that
   would be a new data model — out of scope here).
4. **Vocabulary → Settings**, as a new `Section("Source labels")` in the existing
   `Settings` scene. The Source *picker* + album title stay on the show (per-show,
   not config).

## Target structure

```
VStack(spacing: 0) {
  ShowHeader        // title · path · Source picker · Open Folder · Done
  CompletionPill    // "Imported · resolved 11/11" — only in terminal state
  PipelineStrip     // 4 status cards (Files/Setlist/Plan/Music); tap → select tab
  ActivityTabBar    // segmented: Setlist · Plan · Output · History
  Divider()
  ScrollView { <selected tab body> }
}
```

Header/strip/tabs stop scrolling away; only the active tab scrolls.

Tab bodies are mostly relocation of existing structs, not rewrites:

| Tab | Existing structs |
| --- | --- |
| **Setlist** | Audio Files `ScanSection`, `SetlistInputSection` (`:1345`), Setlists + Cover `CandidateList` |
| **Plan** | new `PlanActionBar` (extracted buttons) + `ProposedMetadataSummary` (`:855`, shown once) + condensed `TrackPlanRow` |
| **Output** | the five `*RunStatus` views (`:553-853`) + `ApplyOperationsPreview` (`:882`) |
| **History** | `RunHistorySection` (`:1105`) as-is |

## AppModel additions (small; no logic change to the pipeline)

```swift
enum PipelineStage { case setup, planned, applied, verified, imported, resolved }
var pipelineStage: PipelineStage { /* switch over the 5 existing run states */ }
var isShowComplete: Bool { /* libraryReadState .completed && didResolveAll */ }
func clearScannedShow() { /* scannedShowFolder = nil + reset run states + setlist */ }
func resetPlanRun()     { /* reset the 5 run states + lastSuccessfulApplyPlan */ }
```

`pipelineStage`/`isShowComplete` are derived, not stored. The selected tab is
view-local `@State`; strip cards set it.

## Slices

- **S0 — Vocabulary → Settings.** *(smallest, self-contained, no structural
  change)* Add `Section("Source labels")` to `SettingsView`; move the Vocabulary
  block (`LiveShowsView.swift:1284-1310`) + `SourceLabelRow` (`:1317`) there, wired
  to the existing `addSourceLabel`/`deleteSourceLabel`/`newSourceLabelToken`
  methods (`AppModel.swift:179-225`, unchanged). Drop the vocabulary half of
  `SourceMetadataSection`; keep the Source picker + album title on the show. DoD:
  labels manage from Settings (Cmd-,); the show no longer renders the 15-row list;
  `swift test` green; app builds.
- **S1 — Shell.** Header + completion pill + pipeline strip + tab scaffold;
  `clearScannedShow()` / `resetPlanRun()` + `pipelineStage` / `isShowComplete`.
  Tab bodies initially just wrap the existing sections unchanged, so the structure
  is verifiable before content is touched. DoD: four tabs navigate; Done returns to
  the empty state; strip reflects stage.
- **S2 — Content polish.** Extract `PlanActionBar` from `PlanReadinessSummary`
  (`:336-551` — split the button `HStack`/`can*` props from the `*RunStatus`
  calls); condense `TrackPlanRow` (`:941`) to hoist album-level fields into one
  header and show only per-track variance; collapse the Output tab once terminal.

## Out of scope

Persistent imported-show list/badging; any `VinylFeverCore` change; any run-logic
change in `AppModel` beyond the four additions above; new schema.

## Decisions for Jon

- None open. The two layout/behavior forks were resolved 2026-07-05 (see Locked
  decisions). Slice boundaries above are the proposed review units.
