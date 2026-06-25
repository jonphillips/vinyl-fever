# App Areas

Vinyl Fever has three main product areas. Each should have its own UI and
workflow shape.

Shared infrastructure exists underneath these areas, but the user should not
have to think in a single generic workflow vocabulary.

## Area 1: Live Show Management

Live Show Management has two jobs:

- Import a live show from local files.
- View the already-imported live-show library by artist in chronological order.

The import side is a one-off operational workflow.

The normal lifecycle is:

1. Choose a show folder and setlist source.
2. Prepare working copies.
3. Normalize filenames.
4. Normalize or parse setlist data.
5. Apply show metadata, track titles, and artwork.
6. Convert to Apple-compatible output if needed.
7. Approve the output for import.
8. Promote the approved files to a stable `Output/` location distinct from
   `Working/`.
9. Import into Apple Music from `Output/`.
10. Verify (see "Verified" below).
11. Only after verification succeeds, clean up the generated `Working/` folder
    (and optionally `Output/`).
12. Move on.

`Working/` is disposable scratch; `Output/` holds the approved, import-ready
artifact. These must be distinct. The earlier "delete `Working/` then import"
ordering was only safe for the FLAC-to-ALAC path, whose output already lands
outside `Working/` in `ALAC/`. For MP3, M4A, and unconverted FLAC the tagged
files live inside `Working/`, so deleting it before import would destroy the
very files being imported. Never delete the import source before import and
verification both succeed.

After verification, Apple Music is the practical source of truth for the show.
The app should not require Jon to keep managing the imported show as a project
unless there is an unresolved issue. The durable value inside Vinyl Fever is
the run log, import status, verification record, and any reusable show metadata.

The view side should let Jon browse live shows by artist, sorted chronologically
by show date, using Apple Music library data or a derived index of that library.
This view exists so Jon can see what live shows he already has and what appears
to be missing without scrolling through Apple Music manually.

The app should include a "scan music library for live shows" action. It should
support rescanning and should initially classify live shows by album titles that
begin with `YYYY-MM-DD`. A later pass may use a local model to review album
titles and call out albums that look like live shows but are missing the expected
date-led label, or albums that are probably mislabeled as live shows.

Truth comes from Jon's show model:

- Artist
- Date
- Venue
- City/region/country
- Tour
- Source
- Recording quality
- Lineage
- Setlist
- Cover art
- Disc/track structure
- Apple Music album title
- Sort album
- Import status
- Verification status

Source suffixes are user-manageable values and appear only in album titles.

MusicBrainz can be useful for some official or known bootleg releases, but it is
not authoritative for private live recordings.

### Current Evidence

`music_pipeline.sh` is the current live-show workflow evidence.

Important current behavior:

- `EXT=flac` defaults to FLAC handling plus optional ALAC conversion.
- `EXT=mp3` handles MP3 tagging without conversion.
- `EXT=m4a` handles M4A/MP4 tagging without conversion.
- Work happens in `Working/`.
- Originals are copied before mutation.
- ALAC output goes outside `Working/`.
- The script is interactive and asks several questions.

### Product Direction

Do not treat the script's prompts as the desired UI.

Rewrite `music_pipeline.sh` very early. Do not spend time building a polished
bridge around the existing interactive script. The rewrite should surface the
right interaction points for the app.

The app should understand what the script accomplishes and then build the
workflow directly:

- Select source files or folder.
- Paste setlist text or upload a `.txt` setlist file.
- Parse and normalize setlist data.
- Follow [Setlist Formatting Rules](setlist-formatting-rules.md) for the
  standardized `setlist.txt` output.
- Use deterministic parsing first, and an LLM helper when the setlist needs
  interpretation or cleanup.
- Preview the file/title/tag/artwork plan.
- Apply the plan to working copies.
- Convert if needed.
- Verify output.
- Delete the generated `Working/` folder once the live-show output is approved.

The script may remain as historical evidence or a temporary reference, but it is
not the product interface.

### Ready To Import

A live show is ready to import when:

- The audio file count matches the setlist track count.
- Jon has approved the album title.
- Jon has approved the metadata.
- Jon has approved the final filenames.

The app should let Jon edit these fields during review before approval.

### Verified

A live show is verified after import when:

- An album matching the approved album title appears in the Apple Music library
  scan.
- The library album's track count equals the setlist track count.
- Optionally, a spot check confirms track durations are within tolerance of the
  source files.

Verification is required because writing tags to files does not guarantee
Music.app reflected them. The local-model "is this album mislabeled?" audit is a
separate, later nicety and is not part of this yes/no verification. See
Verification Surface in [Technical Architecture](technical-architecture.md) for
how the library is read.

## Area 2: Collection Management

Collection Management is persistent.

The core object is a Collection Policy: a named set of playlist/smart-playlist
meaning, metadata policy, artwork policy, and lookup rules for songs that belong
to a particular collection.

Examples:

- `Yacht Rock :: Remixes`
- `Power Pop :: Covers`
- `Jangle Essentials`
- `Great Covers`
- `90s Unified`

This area should support:

- Collection Policy editing.
- Playlist and smart-playlist intent.
- Grouping values and other durable collection fields.
- Simple v1 matching based on `Grouping` containing a phrase.
- Optional refinement by artist name.
- Applying a Collection Policy to a selected folder or set of folders from
  Finder so the contained songs will show up in the collection.
- Membership rules and issue queues.
- Artwork policy.
- MusicBrainz lookup policy.
- Long-lived review of collection health.

Collection Management is where the app remembers what a collection means over
time. Collections are not projects; they are playlist/collection definitions
that files can be sent through for inclusion.

## Area 3: Metadata Management

Metadata Management is for track/file metadata work that is not primarily a
live-show import and not primarily collection-definition work.

This area is still less defined than Live Show Management and Collection
Management. Treat the description here as a working hypothesis.

It covers:

- New song import metadata prep.
- Existing file tag repair.
- MusicBrainz-assisted original source lookup.
- Artwork lookup and selection.
- Sort field cleanup.
- Retagging according to a Collection Policy.
- Apple Music remediation for already-imported items.

Apple Music Remediation belongs here because Music.app may cache metadata,
ignore file-tag changes, or require delete-and-reimport to reflect a correction.

The app should support:

- Inspecting exported Music Library XML or Music.app item data.
- Mapping Music.app items to file paths when possible.
- Comparing actual library display fields against desired metadata policy.
- Preparing corrected files in a staging folder.
- Reimport packages.
- Manual delete-and-readd instructions/checklists.
- Verification after remediation.

Default posture:

- Do not modify Music.app destructively in v1.
- Do not auto-delete library items in v1.
- Make delete-and-reimport an explicit, logged remediation strategy.

## Shared Infrastructure

These tools support all three app areas:

- Folder scanner.
- Audio metadata reader.
- File-plan previewer.
- Run log.
- Output verifier.
- Issue queue.
- Work queue.
- Cover-art queue.
- MusicBrainz helper.
- Setlist parser/normalizer.
- File safety and checksum tools.

Shared tooling must preserve the difference between areas. A one-off live-show
import, a persistently managed collection, and a metadata repair task are
different product objects.
