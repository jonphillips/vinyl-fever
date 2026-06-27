# Implementation Plan

This plan starts after Jon reviews and adjusts the product docs.

Concrete, Codex-ready build orders live in [milestones/](milestones/). The phases
below are the strategic arc; the milestone docs are the slices to implement.
Milestone 1 realizes the start of Phase 1.5 (the vertical slice) as a read-only,
no-writes plan preview — see
[milestones/M1-live-show-plan-preview.md](milestones/M1-live-show-plan-preview.md).
Milestone 2 executes that plan (Phase 4–5): the first mutation — tool discovery,
copy to `Working/`, tag, FLAC→ALAC into `Output/`, and file-level verification,
still stopping short of Music.app — see
[milestones/M2-live-show-apply-convert.md](milestones/M2-live-show-apply-convert.md).

## Phase 0: Requirements Review

Goal: converge on the app areas and vocabulary before building.

Tasks:

- Review these docs.
- Confirm the v1 front doors: Live Show Management and Collection Management.
  Metadata Management is a future area, not a v1 nav silo (see Product
  Requirements).
- Confirm the term `Collection Policy`.
- Identify any must-have scripts not listed in `technical-architecture.md`.

Output:

- Revised docs.
- Settled v1 scope.
- Open-question backlog.

## Phase 1: Workflow Reassessment

Goal: understand what the scripts actually accomplish and rewrite the live-show
pipeline around app-native interaction points before designing final UI.

Tasks:

- Decompose `music_pipeline.sh` into user intent, file operations, metadata
  operations, prompts, and external tool calls.
- Identify which steps are durable requirements and which are temporary manual
  glue.
- Design a setlist ingestion flow that accepts a setlist file or pasted text and
  normalizes it according to `setlist-formatting-rules.md` before file/tag
  planning.
- Decide where deterministic parsing is enough and where an LLM helper should be
  available.
- Identify script functions that should move into Swift early.
- Identify script functions that should remain Python/shell because they
  orchestrate ffmpeg, metaflac, mutagen, or file-system batch work.
- Draft structured `scan`, `preview`, `run`, and `verify` contracts for live-show
  processing.
- Define the approval point where the generated `Working/` folder is deleted.
- Identify Apple Music library data needed to display live shows by artist in
  chronological order.
- Design the library rescan flow for detecting live-show albums whose album title
  begins with `YYYY-MM-DD`.
- Identify where a local model could flag likely mislabeled live-show albums.

Output:

- A workflow decomposition for `music_pipeline.sh`.
- A setlist automation design.
- A rewrite map for each major step.
- A Swift-first implementation map for the live-show import workflow.
- A first design for the live-show library view.

## Phase 1.5: End-To-End Vertical Slice

Goal: prove the riskiest assumptions on one real show before building horizontal
scaffolding.

Take a single real FLAC show folder all the way through: ingest its setlist by
paste, preview the file/title/tag plan, apply to `Working/` copies, convert to
ALAC into `Output/`, import, and verify the album appears in the Apple Music scan
with the right title and track count. It is allowed to be ugly and hard-coded.

The point is to detonate setlist-normalization quality, file-plan correctness,
and the verification surface early, so Phases 3 to 5 are specified by a working
example rather than guesses.

Output:

- One show processed end to end.
- A proven verification path.
- Concrete inputs for the scanner, plan model, and live-show UI.

## Phase 2: Project Skeleton

Goal: create a Mac-first SwiftUI app skeleton in Jon's house style.

Tasks:

- Create Xcode/SPM structure.
- Add app-level `CLAUDE.md` and `AGENTS.md` pointers to `jon-platform`.
- Add shared Swift package for domain logic.
- Add SQLiteData dependency.
- Model app state in SQLiteData from the start.
- Add swift-dependencies, swift-navigation, issue reporting, and test support as
  needed.
- Add initial CI/drift-control shape if the repository becomes a real app repo.

Output:

- Empty app shell.
- Shared package.
- Test target.
- Basic navigation shell.

## Phase 3: Read-Only Scanner and Workflow Catalog

Goal: build useful read-only inspection before running file operations.

Tasks:

- Folder picker and drag/drop.
- Folder scanner result model.
- Audio file detection.
- Cover art detection.
- Setlist detection.
- Working/output folder detection.
- Typed workflow definitions for the two or three real flows (not a generic
  script registry or catalog UI; see Technical Architecture).
- Tests for scan classification.

Output:

- App can inspect a folder and recommend likely app areas/actions without
  writing.

## Phase 4: File Operations and Run Logs

Goal: execute file operations and any remaining scripts safely, then record what
happened.

Tasks:

- Add `FileOperationClient`.
- Add `ScriptClient` only for remaining shell/Python operations.
- Capture stdout/stderr separately.
- Stream output live.
- Store run logs in SQLiteData.
- Store immutable raw output artifacts when useful.
- Add typed workflow definition for the live-show import flow.
- Do not make interactive `music_pipeline.sh` bridging a product milestone.

Output:

- App can perform or launch safe operations and log the run.

## Phase 5: Structured Live-Show Management

Goal: build app-native live-show import prep and an Apple Music-backed live-show
library view.

Tasks:

- Reimplement scan/preview logic from the script evidence in app-native Swift.
- Make setlist input file-based or paste-based, but app-normalized rather than
  terminal-paste-only.
- Support initial setlist input via paste or `.txt` upload.
- Add deterministic and LLM-assisted setlist normalization.
- Expose consolidation choice as a parameter.
- Expose user-managed source suffixes as album-title-only values.
- Expose ALAC conversion choice as a parameter.
- Emit typed Swift plans/results.
- Promote approved files to a stable `Output/` location distinct from `Working/`.
- Import from `Output/`, then verify the outputs.
- Delete `Working/` only after verification succeeds, never before import.
- Display already-imported live shows by artist in date order.
- Add a rescan action for the Apple Music live-show view.
- Classify live shows initially by album titles beginning with `YYYY-MM-DD`.

Output:

- Live Show Management supports both import preparation and library review.

## Phase 6: Collection Policy Metadata Prep

Goal: support track-level collection/playlist metadata workflows.

Tasks:

- Add Collection Policy records.
- Add policy editor.
- Add pipe-delimited Grouping token support.
- Add simple matching: `Grouping` contains policy token, optionally refined by
  artist name.
- Add folder application flow: select one or more Finder folders and add the
  policy token to contained songs.
- Add MusicBrainz lookup helper.
- Add ranking policy that avoids arbitrary VA compilation matches.
- Add artwork candidate selection.
- Add metadata preview.
- Add safe output-copy writing before source retagging.

Output:

- App can apply user-defined metadata/artwork policy to tracks before import.

## Phase 7: Apple Music Remediation

Goal: support correction of already-imported items.

Tasks:

- Import/read Music Library XML or query Music.app.
- Match library items to files.
- Compare desired policy to Music.app-visible fields.
- Prepare corrected reimport packages.
- Track delete-and-reimport checklist.
- Verify after remediation.

Output:

- App can manage library repair without pretending Music.app always refreshes
  file tags reliably.
