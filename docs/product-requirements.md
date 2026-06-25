# Product Requirements

## Product Thesis

Vinyl Fever is a Mac-first personal operations console for local music-file
workflows. It makes existing Python and shell tools discoverable, repeatable,
previewable, and safe.

Vinyl Fever does not replace Apple Music, MusicBrainz Picard, MusicBrainz, or
a full audio player. It prepares, repairs, audits, and tracks music files before
and after they enter Apple Music.

## Primary Need

Jon has several recurring music-library jobs:

- Live-show management: import shows from local files, verify readiness, and view
  already-imported shows by artist in chronological order.
- Collection management: songs belong to user-defined collection policies, each
  with playlist/smart-playlist meaning, grouping, artwork, and lookup policies.
- Metadata management: new or already-imported songs need corrected file tags,
  MusicBrainz-assisted source lookup, artwork choices, sort fields, playlist
  membership, or full delete-and-reimport handling when Music.app will not
  refresh.
- Library audit: missing artwork, mixed formats, duplicate-looking files, stale
  metadata, incomplete imports, and work queues.

The app should answer:

- What do I have?
- What kind of job is this?
- What workflow should I run?
- What exactly will change?
- Which original files are protected?
- What did I run last time?
- Is this ready for Apple Music?
- Did Music.app actually reflect the fix?

## Non-Goals

Do not build these in v1:

- Apple Music replacement.
- Audio player.
- Streaming integration.
- Full Picard clone.
- Full MusicBrainz database clone.
- Cloud service or custom server.
- Authentication.
- iOS-first workflow.
- Automatic destructive cleanup.
- Fully unattended metadata guessing.
- Fully automated Music.app deletion or import.

## Product Shape

The app should have three main product areas, each with its own UI and workflow
shape:

- Live Show Management
- Collection Management
- Metadata Management

Shared infrastructure can support all three areas, but it is not a fourth
user-facing product area.

v1 scope decision: ship two front doors — Live Show Management and Collection
Management. Metadata Management remains a real concept but is not yet a defined
top-level area; in v1 its work surfaces as operations on tracks plus a
remediation / library-health task list backed by the shared infrastructure. It
can be promoted to a full top-level area later once it is concrete. This avoids
committing nav to an admittedly hazy third silo.

Shared infrastructure includes scanning, preview, file planning, logging,
metadata helpers, MusicBrainz lookup, and file safety.

Live Show Management has two faces:

- An ephemeral import tool: process the show, approve it, delete the generated
  `Working/` folder, import it, verify it, and move on.
- A library view: show already-imported live shows by artist in chronological
  order, so Jon can see what is missing without scrolling Apple Music manually.

Once a live show is verified in Apple Music, Apple Music is the practical source
of truth for the show's existence and display. Vinyl Fever may keep logs,
derived indexes, and audit records, but live-show imports are not projects.

Collection Management is persistent: collection policies, playlist/smart-playlist
meaning, membership, lookup rules, artwork policy, and issue queues remain useful
over time. Collections are playlist/collection definitions, not projects.

Metadata Management is task-oriented but recurring: it handles tag repair,
MusicBrainz/source lookup, artwork decisions, and Apple Music remediation for new
or already-imported tracks. This area is intentionally still hazier than the
other two and should be clarified through focused requirements work.

## Mac-First Platform Stance

The execution surface is macOS.

Reasons:

- Raw folders and local music files live on the Mac.
- Existing engines are Bash, Python, ffmpeg, ffprobe, metaflac, and mutagen.
- Music.app import and remediation are Mac-centered workflows.
- iPad does not have equivalent access to arbitrary local folders or shell tools.

Use SwiftUI and shared package boundaries so an iPad companion can exist later.
Do not design v1 around iPad execution.

Potential future iPad companion surfaces for v2 or later:

- Work queue review.
- Cover-art planning.
- Metadata policy editing.
- Run history review.
- Checklist/status workflows.

## Safety Requirements

Every workflow must distinguish:

- Scan
- Preview
- Run
- Verify

Default behavior:

- Preserve originals.
- Write to `Working/`, output, staging, or archive folders.
- Never overwrite without explicit confirmation.
- Log every run.
- Keep exact command/parameters/output.
- Prefer Trash or archive over permanent deletion.
- During prep, do not assume Music.app reflects file tags correctly.
- After verified live-show import, treat Apple Music as the practical source of
  truth for that show's library presence.

## Current Core Script

`scripts/shell/music_pipeline.sh` is the current canonical live-show
pipeline engine.

It is not a thin launcher. It currently performs a guided interactive workflow:

- Creates or reuses `Working/`.
- Copies original tracks into `Working/`.
- Optionally consolidates multi-disc/set folders.
- Normalizes filenames to `TrackNN.<ext>`.
- Prompts for setlist content.
- Applies setlist-driven filenames and tags.
- Embeds optional cover art.
- Prompts for album source suffix.
- Optionally converts FLAC to ALAC.

The app should treat this as the first workflow engine to adapt, not as an
already finished JSON API.

## Script Posture

Existing scripts are evidence, not product requirements.

They contain valuable workflow knowledge: ordering assumptions, metadata rules,
safety instincts, filename heuristics, prompts, and external tool usage. But the
app should not blindly recreate their interaction model.

Script reassessment must happen before certifying user-facing UI. Before
building UI around a script, identify:

- What problem the script solves.
- Which decisions are stable product rules.
- Which decisions were temporary ChatGPT/manual glue.
- Which steps can now be automated.
- Which steps should move into Swift.
- Which steps still belong in Python/shell because they orchestrate audio tools.

The expected direction is Swift-first for app workflows: move stable planning,
parsing, metadata decisions, and file-plan generation into typed Swift code
early. Keep Python/shell only where they remain the best tool for audio
transforms or external command orchestration.

For example, the current live-show pipeline asks Jon to paste setlist text that
has often been massaged elsewhere. The app should instead explore a flow where
Jon selects a setlist source and music files, then local parsing or an LLM-backed
helper normalizes the setlist and proposes the file/tag plan.
