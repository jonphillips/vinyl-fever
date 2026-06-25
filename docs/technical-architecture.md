# Technical Architecture

## House Architecture

Follow `/Users/jon/code/jon-platform/AGENTS.md`.

Settled defaults:

- SwiftUI.
- Point-Free libraries, but no TCA.
- Plain value records.
- `@Observable` feature models.
- Dependency-backed clients.
- SQLiteData for app state.
- CloudKit only if/when sync is useful.
- No SwiftData.
- No custom server.
- No authentication.

## Platform Architecture

Mac is the v1 execution platform.

The shared core should live in an SPM package so future iPad companion surfaces
can reuse models, policies, read models, and non-file-execution UI in v2 or
later.

Suggested boundary:

- Shared package: domain models, typed workflow definitions, metadata policies, scanner
  result values, run log values, pure planning logic, tests.
- macOS app target: file pickers, security-scoped bookmarks, Process execution,
  Music.app integration, Quick Look/reveal, local tool discovery.
- Future iPad target: review/status/policy editing surfaces, not shell execution.

## Shared Components And External Services

Distinguish two kinds of "shared package":

- Vinyl Fever's own core package (above): domain models, policies, planning
  logic, for a possible future iPad companion. App-internal.
- jon-platform cross-app packages that Vinyl Fever *consumes*. Vinyl Fever does
  not re-document or reimplement these; it depends on them and links the canonical
  spec.

### AI model access

The setlist normalizer and the live-show mislabel audit go through the house
`ModelClient` boundary — tiered on-device → Apple cloud → BYO-key frontier, with
the user's key in the Keychain. The canonical spec is
`jon-platform/docs/ios/ai-model-access.md`; do not restate it here.

This layer already exists, built and tested, as Galavant's `GalavantAI` module.
That spec designates it a portfolio-extraction candidate: app-internal in its
first app, lifted to a neutrally-named shared package when a second real app needs
it. Vinyl Fever is that second consumer. The extraction trigger and timing are a
cross-app decision — see `jon-platform/docs/adr/0001-extract-model-layer.md` and
the Shared Components open question.

Per-feature tier targeting and no-key behavior:

- Mislabel audit: cheap classification; the on-device floor is sufficient. Usable
  with no frontier key.
- Setlist normalization: structured extraction over messy prose; realistically
  wants a frontier model for good results. With no frontier key, deterministic
  validation still runs and Jon hand-edits; the LLM quality enhancer is simply
  off. Do not design this feature assuming a key is always present.

### MusicBrainz, Cover Art Archive, AcoustID

- MusicBrainz and Cover Art Archive need no credential. `MusicBrainzClient` is a
  plain `URLSession` JSON client. The obligations are a descriptive `User-Agent`
  and roughly 1 request/second rate limiting, not auth. Browser automation is not
  relevant; these are clean REST APIs.
- AcoustID (audio-fingerprint lookup) is the only external service that would need
  an API key, and only if fingerprinting enters scope. It is out of v1. If added,
  decide then whether it reuses the shared Keychain key-store pattern.

## Persistence

Use SQLiteData for app state.

SQLiteData starts with the app. Do not defer real persistence until after a JSON
or in-memory prototype.

Use JSON for:

- Import/export snapshots.
- Immutable run artifacts when useful.
- Interchange with scripts.

Do not use JSON workflow manifests as the v1 workflow model. Model workflows as
typed Swift values and functions first. Add JSON only later when there is a real
need for export/import or script interchange.

Do not use SwiftData.

For the source-of-truth split between the local files, the Apple Music library,
and SQLiteData, see the Source Of Truth And Storage Ownership section in
[Metadata Policy Model](metadata-policy-model.md). In short: SQLiteData holds
policies, run logs, queues, decisions, app-owned fields Apple Music cannot carry,
and a rebuildable cache/index of the Apple Music scan. It is not the source of
truth for file contents or library presence. Folder scans and the live-show
index are caches with a timestamp; treat them as stale-tolerant, not
authoritative.

App state candidates:

- Work queues.
- Workflow definitions known to the app.
- Script registrations.
- Runs.
- Run artifacts.
- Folder scans.
- Issues.
- Collection Policies.
- MusicBrainz candidate decisions.
- Apple Music remediation tasks.
- Verification statuses.

## Clients

Use dependency-backed clients rather than global services.

Likely clients:

- `ScriptClient`: run executable with arguments/environment, stream stdout/stderr,
  return exit code and raw output.
- `FileSystemClient`: enumerate folders, inspect paths, copy/move/trash/reveal.
- `AudioMetadataClient`: read tags/durations/artwork status through Swift or
  Python helpers.
- `MusicLibraryScanClient`: read exported Music Library XML or Music.app data and
  derive the live-show artist/date view.
- `LocalModelClient`: optional local model review for ambiguous live-show album
  labels and other classification tasks.
- `MusicBrainzClient`: search and fetch metadata through a helper or direct API.
- `MusicAppClient`: inspect exported XML or query Music.app in later phases.
- `ChecksumClient`: produce hashes for source files and verification.
- `DateClient`, `UUIDClient`, `Clock`: standard dependency-controlled values.

The setlist normalizer and the live-show mislabel audit are AI features and must
call models through the house `ModelClient` boundary (tiered on-device → Apple
cloud → BYO-key), not Apple's `LanguageModel` directly and not a one-off model
API. See `jon-platform/docs/ios/ai-model-access.md` before adding any AI feature.

## Toolchain And Execution Environment

Three decisions that block the first real run and must be settled before Phase 2:

- PATH discovery. A Finder-launched `.app` does not inherit the shell `PATH`, so
  `which ffmpeg`/`metaflac`/`python` will fail even though they work in Terminal.
  The app must probe known locations (`/opt/homebrew/bin`, `/usr/local/bin`) and
  offer a Settings screen to override tool paths. Treat "locate external tools"
  as a first-class, tested concern.
- Sandboxing. This is household software, never App Store, so run non-sandboxed
  (Developer ID + hardened runtime). Spawning Homebrew tools and reading
  arbitrary folders from a sandbox is not worth the fight.
- Python surface. The legacy scripts depend on `mutagen`/`musicbrainzngs` in a
  local `.venv`; shelling into a user venv is fragile. Prefer the locatable C
  CLIs for tagging — `metaflac` for FLAC Vorbis comments and embedded art,
  `ffmpeg`/AVFoundation for MP3/M4A — which shrinks Python to the batch/dedup
  utilities that may not even ship in v1.

## Script Inventory

Known scripts in `scripts/` (`scripts/shell/` and `scripts/python/`) include:

- `music_pipeline.sh`: interactive live-show prep engine.
- `batch_flac_to_alac_sets.py`: batch FLAC archive sets to ALAC, with dry-run.
- `remix_archive_convert.py`: single-folder FLAC to ALAC conversion for remix
  archive style folders.
- `opus_to_aac.py`: OPUS to AAC/M4A conversion, with dry-run.
- `rule_scrub_tags.py`: deterministic tag scrubber, dry-run by default.
- `scrub_titles.py`: consensus title scrubber, dry-run by default.
- `tag_dupe_finder.py`: duplicate finder/quarantine helper.
- `compare_directories_dupes.py`: directory comparison report/quarantine helper.
- `unify_music_dirs.py`: unify two directories and quarantine duplicates.
- `triage_sort_by_artist.py`: sort files into artist triage folders.
- `cover_compilation.py`: covers-compilation metadata/artwork tool.
- `prep_release.sh`: release prep/checksum/fingerprint helper.

This list is illustrative, not authoritative, and already drifts from disk (for
example `compare_compilations_to_canonical.py` and `strip_prefix_underscore.py`
also exist but are not listed). Treat the folder as the inventory rather than
maintaining a hand-kept list.

Each script needs reassessment before app UI is built around it. Do not assume
`--dry-run` means no writes unless verified. For example, `prep_release.sh`
dry-run currently protects filename renames but still performs cleanup and writes
fingerprint/checksum outputs.

## Workflow Definitions

Workflow definitions should be typed Swift values. They should describe
capabilities and risks, not just command names.

v1 scoping: do not build a generic workflow/script registry or a catalog UI over
arbitrary registered scripts. At household scale there are only a handful of
workflows for one user, so model the two or three real flows as concrete typed
Swift values and functions. Keep `ScriptClient` narrowed to the specific
audio-conversion tools (ffmpeg/metaflac), not "run any registered script." The
field list below is the aspirational shape a workflow can take, not a v1 schema
to implement up front:

Important fields:

- ID.
- Name.
- Workflow area.
- Script path.
- Inputs.
- Parameters.
- Supported modes.
- Whether the current script is interactive.
- Whether it can run unattended.
- Dry-run scope.
- Source mutation policy.
- Output policy.
- Overwrite policy.
- Delete/trash/archive behavior.
- Required external tools.
- Expected structured result or raw output behavior.
- Verification steps.

## Run Log

Every run should capture:

- Workflow ID/name.
- Workflow area.
- Script path and file hash if useful.
- Start/end time.
- Input paths.
- Output paths.
- Working directory.
- Parameters.
- Environment variables used, such as `EXT`.
- Exact command.
- stdout and stderr.
- Exit code.
- Files created.
- Files modified.
- Files skipped.
- Warnings.
- Errors.
- User confirmations when applicable.
- Verification result.

## Safety Model

Prefer explicit file plans.

For any run, the app should be able to show:

- Source files.
- Working copies.
- Output files.
- Existing conflicts.
- Files that may be overwritten.
- Files that may be deleted, trashed, or archived.
- Which actions are reversible.

Default policy:

- Originals immutable by default.
- No silent overwrite.
- No permanent delete.
- Source mutation requires explicit opt-in.
- Interactive scripts are labeled as such.

## Music.app Integration

Treat Music.app as a destination and display layer, not the system of record.

Implementation levels:

1. Prepare files for manual import.
2. Reveal/open folders for manual import.
3. Read exported Music Library XML or query Music.app for audit.
4. Prepare reimport packages.
5. Only later consider automation for deletion/import, and keep it explicit.

### Verification Surface

The mechanism that reads the Apple Music library to verify imports is an early
architectural decision, not a later one, because it defines
`MusicLibraryScanClient`/`MusicAppClient` and gates the entire
scan/preview/run/verify loop. Decide it in Phase 1.

Three candidates, each with a catch:

- Exported `Library.xml`: has the file `Location`, but export is manual, the
  format is increasingly deprecated, and it goes stale the moment you import.
- AppleScript / ScriptingBridge: can read persistent IDs, album, track count, and
  the file location for local items, and can write; but it is brittle and slow on
  large libraries.
- MusicKit (`MusicLibrary`): clean API, but often does not expose file paths and
  needs an entitlement.

Default for a household Mac app: AppleScript/ScriptingBridge as the primary read
surface, with `Library.xml` as a fallback importer. Do not design around MusicKit
where file-path mapping is required. The file-to-library-item mapping is the
hardest part of this surface; spike it before building UI on top.

## Script Reassessment

Existing scripts should not drive the UI by default.

Before wrapping a script in a polished interface, perform a short reassessment:

- Identify the stable domain intent.
- Identify the safety rules worth preserving.
- Identify manual or ChatGPT-assisted steps that should become app features.
- Prefer Swift for stable app workflow logic, parsing, planning, metadata policy,
  file-plan generation, and preview models.
- Keep Python/shell only where they remain the best tool for audio transforms,
  ffmpeg/metaflac/mutagen orchestration, or migration utilities.
- Decide whether each remaining non-Swift step belongs in Python, shell, or an
  LLM helper.
- Decide whether the script should be wrapped, split, rewritten, or retired.

`music_pipeline.sh` is especially important here. It proves the live-show
workflow, but the desired app experience should not require terminal prompts or
manual setlist massaging. A future structured live-show workflow should accept
files and setlist input directly, produce a previewable plan, and then apply that
plan to working copies.

Do not spend product time polishing a bridge to the interactive
`music_pipeline.sh`. Rewrite the live-show pipeline early in Swift-first app
logic, keeping only the audio-tool operations outside Swift where that remains
the right boundary.
