# MusicWorkbench — Codex Handoff Brief

> **Superseded — historical evidence only.** This single-file brief is replaced
> by `docs/vinyl-fever/` as the working source of truth. Where it conflicts with
> those docs, the vinyl-fever docs win. In particular, ignore its persistence
> guidance (SwiftData / SQLite "Option B", JSON project files): the house stack
> is SQLiteData with no SwiftData and no JSON workflow manifests. Kept for the
> workflow knowledge it captures, not its architecture calls.

## 1. Product thesis

Build a Mac-native **Music Library Workbench**: a personal operations console for music-library tooling scripts, file preparation, metadata cleanup, live-show organization, cover-art queues, and Apple Music import prep.

The app should **not** try to replace Apple Music, MusicBrainz Picard, MusicBrainz, or a full music player. It should organize and safely run existing Python/shell workflows that prepare, audit, transform, tag, and track music files before and after import into Apple Music.

The core idea:

```text
SwiftUI app = cockpit
Python/shell scripts = engines
JSON workflow manifests = instruction labels
Run logs = black box recorder
Project queues = memory
MusicBrainz/Picard = optional metadata assistants
Apple Music = playback/library destination, not the system of record
```

This app exists because the user already has a growing pile of useful Python/shell scripts, but they are scattered, opaque, and easy to forget. The app should make them discoverable, safe, repeatable, previewable, and tied to actual music projects.

---

## 2. Primary user need

The user has recurring music-library workflows, including:

- Converting FLAC to Apple-compatible ALAC/M4A.
- Retagging existing M4A/MP4/MP3 files.
- Applying consistent Apple Music metadata.
- Embedding cover art.
- Creating, copying, or validating `setlist.txt` files.
- Preparing import-ready folders for Apple Music.
- Tracking live shows by artist/date/venue/city/tour/source.
- Maintaining cover-art projects for live-show series.
- Managing Apple Music sort behavior and album naming conventions.
- Auditing folders for missing metadata, missing art, inconsistent naming, or incomplete conversion/import status.

Current pain:

```text
music_pipeline.sh
fix_tags.py
normalize_names.py
make_setlist.py
cover_art_helper.py
flac_to_alac.py
ffmpeg_tag_m4a.py
some_old_test_script.py
some_new_version_FINAL2.py
```

Each script made sense when created, but later it is hard to remember:

- What does this script do?
- When should I use it?
- What inputs does it expect?
- What does it modify?
- Does it overwrite originals?
- What did I run last time?
- Did this album/show already get processed?
- What is missing before I import it into Apple Music?

MusicWorkbench should answer those questions.

---

## 3. Non-goals

Do **not** build these in early versions:

- Full Apple Music replacement.
- Audio player.
- Streaming integration.
- MusicBrainz Picard clone.
- Full MusicBrainz database clone.
- Cloud sync.
- iOS app.
- Multi-user sharing.
- Automatic destructive cleanup.
- AI chat as a primary interface.
- Full Apple Music library manipulation in v1.

The app’s job is not to play music. The app’s job is to make the collection sane.

---

## 4. High-level architecture

Recommended v1 architecture:

```text
SwiftUI macOS app
  ↓
Workflow definitions / manifests
  ↓
Script runner service
  ↓
Existing Python + shell scripts
  ↓
ffmpeg / ffprobe / mutagen / file system
```

The app should initially **wrap existing scripts**, not immediately rewrite them in Swift.

Reasoning:

- Existing scripts encode hard-won behavior.
- Rewriting immediately introduces unnecessary bugs.
- SwiftUI is excellent for UI, file picking, preview tables, persistence, logs, state, and macOS permissions.
- Python/shell remain better for audio-file transformation, ffmpeg orchestration, metadata probing, and quick cleanup logic.

Over time, stable and UI-adjacent logic can move into Swift, but v1 should preserve script behavior and build a safe cockpit around it.

---

## 5. Core workflow pattern

Every file operation should follow the same pattern:

```text
1. Select or drag in a folder/files
2. App scans contents
3. App classifies what it sees
4. App proposes actions
5. User previews exact changes
6. User runs the workflow
7. App logs results
8. App shows unresolved issues / next actions
```

The app should heavily distinguish between:

```text
Scan
Preview
Run
Verify
```

No workflow should silently mutate source files. Preview and logging are central product features, not polish.

---

## 6. Safety principles

Because the app touches valuable and possibly irreplaceable music files, enforce these rules:

### 6.1 Originals are immutable by default

The app should not modify source files in place unless the user explicitly chooses that behavior.

Preferred folder model:

```text
Incoming/
Working/
Finished/
Archive/
```

Default output behavior:

```text
Write to a new output folder.
Preserve originals.
Never overwrite unless explicitly confirmed.
```

### 6.2 Every run creates a log

Each run should capture:

- Workflow ID/name.
- Script path/version.
- Start/end time.
- Input folder.
- Output folder.
- Parameters.
- Command executed.
- Environment details where useful.
- Files created.
- Files modified.
- Warnings.
- Errors.
- stdout/stderr.
- Exit code.
- Duration.

### 6.3 Transformations should be reproducible

A run log should answer:

- What command did I run?
- What metadata did I apply?
- Which cover art did I embed?
- Which source files produced which output files?

### 6.4 Use checksums for confidence

For source/original files, record a checksum such as SHA-256. This helps detect accidental source mutation and supports future audit/verification.

### 6.5 Never overwrite by default

If the output folder already exists, the app should offer choices such as:

```text
- Create new version
- Compare existing output
- Overwrite after backup
- Cancel
```

### 6.6 Trash/archive instead of delete

Any removal should go to macOS Trash or an app-controlled archive, not permanent deletion.

---

## 7. Recommended project layout

Possible repository structure:

```text
MusicWorkbench/
  MusicWorkbench.xcodeproj
  App/
    Views/
    Models/
    Services/
    Persistence/
  Scripts/
    music_pipeline.sh
    tag_audio.py
    normalize_live_show.py
    generate_setlist.py
    audit_album_folder.py
    mb_lookup.py
  PythonLib/
    musiclib/
      __init__.py
      metadata.py
      filenames.py
      ffmpeg.py
      artwork.py
      setlist.py
      live_show.py
      musicbrainz.py
  Workflows/
    flac_to_alac.json
    tag_m4a.json
    normalize_live_show.json
    generate_setlist.json
    metadata_assist.json
  TestFixtures/
    LiveShowBasic/
    AlbumWithCover/
    M4AAlreadyTagged/
    MissingArtwork/
  Logs/
  MusicWorkbenchData/
    projects/
    runs/
    settings.json
```

Early on, scripts can remain in a visible development folder and the app can point to them. Later, stable scripts can be bundled with the app.

---

## 8. Workflow manifest schema

The app should catalog workflows through JSON manifest files rather than exposing raw script names.

Example manifest:

```json
{
  "id": "flac_to_alac",
  "name": "FLAC to ALAC Import Prep",
  "description": "Converts FLAC files to Apple-compatible ALAC M4A files, embeds cover art, applies tags, and prepares an import folder.",
  "script": "music_pipeline.sh",
  "inputs": [
    {
      "name": "sourceFolder",
      "label": "Source Folder",
      "type": "folder",
      "required": true
    },
    {
      "name": "outputFolder",
      "label": "Output Folder",
      "type": "folder",
      "required": false
    },
    {
      "name": "artist",
      "label": "Artist",
      "type": "text",
      "required": true
    },
    {
      "name": "album",
      "label": "Album",
      "type": "text",
      "required": true
    },
    {
      "name": "extension",
      "label": "Source Format",
      "type": "choice",
      "options": ["flac", "m4a", "mp4", "mp3"],
      "default": "flac"
    }
  ],
  "supportsScan": true,
  "supportsPreview": true,
  "supportsDryRun": true,
  "destructiveLevel": "non_destructive",
  "outputPolicy": "new_folder",
  "tags": ["conversion", "apple_music", "metadata"]
}
```

The UI should show workflow cards like:

```text
FLAC → ALAC Import Prep

Use when:
You have a folder of FLAC files and want Apple Music-ready ALAC M4A files.

Requires:
- FLAC files
- optional cover.jpg or folder.jpg
- metadata fields

Does:
- converts audio
- embeds artwork
- writes tags
- creates output folder

Does not:
- delete originals
- import into Apple Music automatically
```

---

## 9. Script command contract

Existing scripts should gradually adopt a common command interface:

```text
--help
--version
--mode scan
--mode preview
--mode run
--input
--output
--params
--json
--dry-run
```

Recommended modes:

```bash
script_name --mode scan --input /path/to/folder --json
script_name --mode preview --input /path/to/folder --params /path/to/params.json --json
script_name --mode run --input /path/to/folder --output /path/to/output --params /path/to/params.json --json
```

Example:

```bash
python normalize_live_show.py \
  --mode preview \
  --input "/Users/jon/Music/Incoming/Bruce Hornsby 1990 Bottom Line" \
  --params "/tmp/workflow-params.json" \
  --json
```

Expected JSON response for scan/preview:

```json
{
  "status": "ok",
  "detected": {
    "audioFiles": 18,
    "formats": ["flac"],
    "coverArt": "cover.jpg",
    "setlist": null,
    "likelyType": "live_show"
  },
  "proposedActions": [
    {
      "type": "convert",
      "source": "01 Song.flac",
      "destination": "01 Song.m4a"
    },
    {
      "type": "embed_artwork",
      "source": "cover.jpg",
      "target": "all output files"
    }
  ],
  "warnings": [
    "No setlist.txt found"
  ]
}
```

Once scripts speak JSON, the Swift app can treat them as workflow engines rather than opaque terminal commands.

---

## 10. Swift script runner service

Create a `ScriptRunner` service using `Process`.

Conceptual Swift shape:

```swift
final class ScriptRunner {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]
    ) async throws -> ScriptResult {
        // launch Process
        // capture stdout
        // capture stderr
        // capture exit code
        // return structured result
    }
}
```

Important design details:

- Capture stdout and stderr separately.
- Stream output live if possible.
- Decode JSON when `--json` is used.
- Preserve raw output in run logs.
- Surface warnings separately from hard errors.
- Store the exact command and params file for reproducibility.
- Treat non-zero exit codes as failed runs.
- Avoid blocking the main thread.

---

## 11. Folder scanner service

The first real feature should be a read-only folder scanner.

When the user drags in or selects a folder, detect:

- Audio file formats: FLAC, M4A, MP4, MP3, WAV, AIFF.
- Number of audio files.
- Disc subfolders.
- Cover art files: `cover.jpg`, `folder.jpg`, `front.png`, etc.
- Image dimensions where possible.
- `setlist.txt`.
- `.cue`, `.log`, `.md5`, `.ffp`, or lineage files.
- Existing metadata/tags.
- Track numbers.
- File naming patterns.
- Date patterns in folder names.
- Venue-like or city-like folder components.
- Suspicious characters.
- Mixed formats.
- Duplicate-looking files.

Example output:

```text
Folder Audit

Likely type:
Live Show

Audio:
18 FLAC files
0 M4A files
0 MP3 files

Metadata:
Track numbers found: yes
Titles found: maybe
Existing embedded tags: partial

Artwork:
cover.jpg found
Image size: 1200 × 1200

Setlist:
setlist.txt not found

Naming:
Date not found in folder name
Venue not found
Artist inferred: Bruce Hornsby

Recommended next actions:
1. Fill Live Show Metadata
2. Generate setlist.txt
3. Convert FLAC to ALAC
```

---

## 12. Job classification

The app should classify folders into job/project types:

```text
Studio Album
Live Show
Compilation
Box Set
EP / Single
Soundtrack
Cover Art Project
Unprocessed Download
Unknown
```

Detection clues:

- File extensions.
- Folder name.
- Date pattern.
- Presence of `setlist.txt`.
- Presence of cover art.
- Number of discs.
- Existing metadata.
- Track numbering.
- Artist/album-like folder names.
- Venue/city-like strings.

Example:

```text
Folder: Bruce Hornsby - 1990-08-14 - The Bottom Line

Detected:
- likely live show
- artist: Bruce Hornsby
- date: 1990-08-14
- venue: The Bottom Line
- 17 FLAC files
- no cover art
- no setlist.txt

Recommended workflows:
1. Normalize Live Show Folder
2. Generate Setlist Template
3. FLAC → ALAC Import Prep
4. Add to Bruce Hornsby Venue Series
```

---

## 13. Core data model sketch

### 13.1 Workflow

```swift
struct Workflow: Identifiable, Codable {
    let id: String
    var name: String
    var description: String
    var scriptPath: String
    var inputDefinitions: [WorkflowInput]
    var supportsScan: Bool
    var supportsPreview: Bool
    var supportsDryRun: Bool
    var destructiveLevel: DestructiveLevel
    var outputPolicy: OutputPolicy
    var tags: [String]
}
```

### 13.2 ScriptRun

```swift
struct ScriptRun: Identifiable, Codable {
    let id: UUID
    let workflowID: String
    let startedAt: Date
    var endedAt: Date?
    var status: RunStatus
    var sourcePath: String
    var outputPath: String?
    var parameters: [String: String]
    var command: String
    var stdout: String
    var stderr: String
    var exitCode: Int32?
    var changedFiles: [FileChange]
    var warnings: [String]
    var errors: [String]
}
```

### 13.3 AlbumProject

```swift
struct AlbumProject: Identifiable, Codable {
    let id: UUID
    var artist: String
    var albumTitle: String
    var albumType: AlbumType
    var sourceFolder: String
    var workingFolder: String?
    var outputFolder: String?
    var status: ProjectStatus
    var metadata: MusicMetadata
    var files: [AudioFile]
    var notes: String
    var createdAt: Date
    var updatedAt: Date
}
```

### 13.4 LiveShow

```swift
struct LiveShow: Identifiable, Codable {
    let id: UUID
    var artist: String
    var date: Date?
    var venue: String?
    var city: String?
    var region: String?
    var country: String?
    var tour: String?
    var source: String?
    var quality: String?
    var lineage: String?
    var setlistPath: String?
    var coverArtPath: String?
    var appleMusicAlbumTitle: String
    var sortAlbum: String?
}
```

### 13.5 AudioFile

```swift
struct AudioFile: Identifiable, Codable {
    let id: UUID
    var path: String
    var filename: String
    var format: AudioFormat
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval?
    var checksum: String?
    var existingTags: [String: String]
    var proposedTags: [String: String]
}
```

### 13.6 FileChange

```swift
struct FileChange: Identifiable, Codable {
    let id: UUID
    var originalPath: String
    var proposedPath: String?
    var changeType: FileChangeType
    var beforeValue: String?
    var afterValue: String?
}
```

### 13.7 MusicMetadata

```swift
struct MusicMetadata: Codable {
    var artist: String?
    var albumArtist: String?
    var album: String?
    var title: String?
    var genre: String?
    var year: String?
    var date: String?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var compilation: Bool?
    var sortAlbum: String?
    var sortArtist: String?
    var sortAlbumArtist: String?
    var comments: String?
    var grouping: String?
}
```

---

## 14. Persistence recommendation

Start simple.

Two reasonable approaches:

### Option A: JSON project files

Good for transparency and early iteration.

```text
MusicWorkbenchData/
  projects/
    bruce-hornsby-venue-series.json
    sting-tour-series.json
  runs/
    2026-06-24-143022-flac-to-alac.json
  settings.json
```

Advantages:

- Human-readable.
- Easy to debug.
- Easy to version/backup.
- Fits personal-tool ethos.

### Option B: SwiftData / SQLite

Good when the model stabilizes.

Recommendation: start with JSON or a thin persistence abstraction that can move to SwiftData later.

---

## 15. V1 feature set

Build the smallest useful app:

```text
- Workflow catalog
- Folder scanner
- Script runner
- Run log
- One real workflow: Prepare Apple Music Import
```

V1 should:

1. Let the user register existing scripts.
2. Read workflow manifests.
3. Let the user select or drag in a source folder.
4. Scan the folder.
5. Choose source format: `flac`, `m4a`, `mp4`, `mp3`.
6. Fill metadata fields.
7. Preview command and output location.
8. Run script.
9. Capture stdout/stderr.
10. Save run log.
11. Reveal output folder.

This proves the cockpit/engine model before adding more domain-specific features.

---

## 16. Specific v1 workflow: Prepare Apple Music Import

This wraps the existing `music_pipeline.sh` or equivalent.

Known behavior/requirements:

- Existing pipeline has handled `EXT=flac|mp3`.
- It should also support `m4a` and `mp4`.
- FLAC files should be converted to ALAC.
- M4A/MP4 files should be retagged through ffmpeg without FLAC-to-ALAC conversion.
- M4A/MP4 tagging should behave like MP3 tagging through an ffmpeg rewrite.
- FLAC → ALAC should only happen for `EXT=flac`.
- Extension normalization should strip the current extension correctly.
- Workflow may involve cover art and `setlist.txt`.

Possible UI:

```text
Prepare Apple Music Import

Source format:
[ FLAC ] [ M4A ] [ MP4 ] [ MP3 ]

For FLAC:
☑ Convert to ALAC
☑ Preserve originals

For M4A/MP4:
☑ Retag existing Apple-compatible files
☐ Re-encode audio

Metadata:
Artist:
Album:
Album Artist:
Genre:
Year:
Disc:
Compilation:
Sort Album:

Artwork:
☑ Embed cover.jpg

Setlist:
☑ Copy setlist.txt to output folder

Buttons:
Preview
Run
Reveal Output
Mark Ready to Import
```

---

## 17. V1.1 feature set

Add safe utility workflows:

```text
- Setlist template generator
- Cover art detection
- Missing-art queue
```

### 17.1 Generate `setlist.txt` template

Input:

```text
01 - Song One.flac
02 - Song Two.flac
03 - Song Three.flac
```

Output:

```text
01. Song One
02. Song Two
03. Song Three
```

The app should preview creating a new `setlist.txt` file and allow editing before saving.

### 17.2 Cover art detection

Detect:

- Missing cover art.
- Candidate images.
- Image dimensions.
- File type.
- Whether artwork is already embedded.

Statuses:

```text
Needs concept
Needs image
Needs crop
Needs final export
Ready to embed
Embedded
Verified
```

---

## 18. V1.2 feature set

Add live-show model and normalization.

### 18.1 Live show metadata

A live show has:

```text
Artist
Date
Venue
City
State/Country
Tour
Source
Recording quality
Lineage
Setlist
Cover art
Disc/track structure
Import status
Apple Music album title
Sort album
Series membership
```

### 18.2 Live show detail page

Example:

```text
Bruce Hornsby
1990-08-14
The Bottom Line
New York, NY

Status:
☑ Audio converted
☑ Tags applied
☐ Cover art missing
☑ Setlist present
☐ Imported to Apple Music
☐ Verified on iPhone

Files:
17 FLAC originals
17 ALAC outputs
cover.jpg missing
setlist.txt present

Actions:
- Generate cover art prompt
- Add placeholder artwork
- Re-run tagging
- Open output folder
- Mark imported
```

### 18.3 Live show naming templates

Provide editable templates:

```text
Folder name template:
{artist} - {date} - {venue} - {city}, {region}

Album title template:
{date} - {venue} - {city}, {region}

Sort album template:
{sortPrefix} {date} {venue}
```

The app should support date-first live-show album titles to reduce reliance on manual `9000`-style sort prefixes where possible.

---

## 19. V1.3 feature set

Add library audit and batch workflows.

Audit should report:

```text
Missing cover art
Missing setlist
Mixed file formats
Track count mismatch
Album title inconsistent with folder name
Sort album missing
Duplicate album folders
FLAC originals without ALAC outputs
ALAC outputs without import status
Shows imported but not archived
Unknown/unclassified folders
Possible duplicate shows
```

Example issue list:

```text
High confidence:
- 14 live shows missing cover art
- 8 folders have FLAC but no ALAC output
- 3 albums have setlist track count mismatch
- 6 M4A folders need tag rewrite

Needs review:
- 9 folders could not be classified
- 4 possible duplicate shows
```

Each issue should link to a recommended workflow.

---

## 20. V2 feature set

Consider Apple Music integration only after core workflows are stable.

Integration levels:

### Level 1: File prep only

The app prepares clean `.m4a` files in an import folder. The user manually imports into Music.app.

This is safest and should be v1.

### Level 2: Open/reveal for Music.app

The app reveals files or opens folders for manual import.

### Level 3: Inspect Music library

The app reads an exported Music library XML or uses AppleScript to query Music.app for whether an album appears to exist.

Useful questions:

```text
Has this show already been imported?
Are track counts consistent?
Does the album title match the prepared folder?
```

### Level 4: Full Music.app manipulation

Avoid early. This can become fragile and dangerous.

---

## 21. Project queues

The app should organize work by project, not just by album/folder.

Examples:

```text
Bruce Hornsby Venue Series
Sting Tour Series
John Hiatt Series
Nightwing Covers
Power Pop Cleanup
Live Shows to Import
Apple Music Sort Cleanup
```

Each project should track:

- Goal.
- Rules.
- Included albums/shows.
- Current status.
- Open issues.
- Next action.

Example:

```text
Bruce Hornsby Venue Series

Goal:
Create a consistent visual and metadata treatment for selected Bruce Hornsby live shows.

Rules:
- Date-first album titles
- Venue-forward cover art
- ALAC output
- setlist.txt included
- final import verified on iPhone

Progress:
23 total shows
17 converted
14 imported
9 missing cover art
3 need setlist cleanup

Next actions:
- Generate covers for 1990-08-14, 1992-03-21, 1993-07-12
- Re-run tagging on 4 M4A folders
```

---

## 22. Cover art queue

The app should track cover-art work separately from audio conversion.

A cover art project has:

```text
Artist
Series
Show/album
Concept
Prompt
Status
Generated image path
Final cover path
Embedded?
Imported?
```

Example UI:

```text
Cover Art Queue

Bruce Hornsby Venue Series
  12 shows missing art
  4 have candidate art
  3 ready to embed

Sting Tour Series
  8 shows missing art

Nightwing Covers
  Jangly - final
  Power Pop - needs revision
  Synthpop - final
  Melodic Rock - missing
```

The app does not need built-in image generation initially. It can simply manage status, prompt text, candidate images, and final artwork paths.

---

## 23. MusicBrainz / Picard integration

### 23.1 Important distinction

MusicBrainz Picard and MusicBrainz are related but should be treated differently.

```text
Picard = GUI-oriented tagger with some command-line automation
MusicBrainz = metadata database with proper web API
```

For MusicWorkbench:

- Use the **MusicBrainz API** as the main programmatic metadata source.
- Use **Picard** as an optional assisted matching tool.
- Do not make Picard the canonical backend.

### 23.2 Picard CLI / automation

Picard can be launched from the command line and can accept files, directories, URLs, and MBIDs. It supports executable commands through `-e` / `--exec` and command files via `FROM_FILE`.

Useful Picard commands include:

```text
LOAD path/to/directory
CLUSTER
LOOKUP_CLUSTERED
SAVE_MATCHED
REMOVE_SAVED
REMOVE_EMPTY
SCAN
```

Example generated command file:

```text
LOAD /Users/jon/Music/Incoming/SomeAlbum
CLUSTER
LOOKUP_CLUSTERED
SAVE_MATCHED
REMOVE_SAVED
REMOVE_EMPTY
```

Possible invocation:

```bash
picard -e FROM_FILE /tmp/picard-commands.txt
```

or:

```bash
picard \
  -e LOAD "/Users/jon/Music/Incoming/SomeAlbum" \
  -e CLUSTER \
  -e LOOKUP_CLUSTERED
```

Picard can help with:

- Launching a folder in Picard from MusicWorkbench.
- Clustering files.
- Looking up albums.
- Saving confident matches in assisted workflows.
- Handling messy material manually.

Picard is awkward as a core backend because:

- It is GUI-oriented, not a pure headless library.
- It does not naturally return rich JSON previews to the Swift app.
- Matching uncertainty is hard to manage invisibly.
- Fully unattended tagging is risky if Picard guesses wrong.

Recommended Picard policy:

```text
Open selected folder in Picard: yes
Generate optional Picard command files: yes
Auto-save through Picard: off by default
Treat Picard as assisted matching, not canonical app state
```

### 23.3 MusicBrainz API

MusicBrainz has a REST-style web API supporting search, lookup, browse, release metadata, artist metadata, recording metadata, relationships, disc IDs, ISRC/ISWC lookup, and JSON responses.

For this app, use MusicBrainz to:

- Search releases by artist/album.
- Fetch release details by MBID.
- Fetch tracklists.
- Fetch release dates/countries/labels/barcodes where useful.
- Link to cover-art sources.
- Present candidate metadata to the user.

The app should **not** blindly apply MusicBrainz data. It should show candidates, compare tracklists to files, and let the user choose.

### 23.4 Python helper: `musicbrainzngs`

Because the user already has Python tooling, use a Python helper script such as `mb_lookup.py` backed by `musicbrainzngs`.

Architecture:

```text
SwiftUI app
  ↓
Python metadata lookup service
  ↓
musicbrainzngs
  ↓
MusicBrainz API
```

The Python helper should:

- Set a proper MusicBrainz User-Agent.
- Respect rate limiting.
- Cache results locally.
- Return JSON to Swift.

Example command:

```bash
python mb_lookup.py \
  --artist "Bruce Hornsby" \
  --album "Scenes From The Southside" \
  --fmt json
```

Example JSON output:

```json
{
  "query": {
    "artist": "Bruce Hornsby",
    "album": "Scenes From The Southside"
  },
  "candidates": [
    {
      "release_id": "...",
      "title": "Scenes From The Southside",
      "artist_credit": "Bruce Hornsby & The Range",
      "date": "1988",
      "country": "US",
      "label": "RCA",
      "barcode": "...",
      "track_count": 9,
      "score": 98
    }
  ]
}
```

### 23.5 Metadata Assist workflow

Add a module called **Metadata Assist**.

Workflow:

```text
Scan folder
  ↓
Extract existing clues
  ↓
Search MusicBrainz
  ↓
Show candidate releases
  ↓
Compare candidate tracklist to files
  ↓
Choose metadata source
  ↓
Apply user-specific rules
  ↓
Preview final tags
  ↓
Write output copy
```

Example UI:

```text
MusicBrainz Candidates

1. Scenes From The Southside
   Bruce Hornsby & The Range
   1988 • US • RCA
   9 tracks • high confidence

2. Scenes From The Southside
   Bruce Hornsby & The Range
   1988 • Europe • RCA
   9 tracks • medium confidence
```

Track comparison table:

| Track | Current file | MusicBrainz title | Action |
|---|---|---|---|
| 1 | `01.flac` | `Look Out Any Window` | Set title |
| 2 | `02.flac` | `The Valley Road` | Set title |
| 3 | `03.flac` | `I Will Walk With You` | Set title |

Then apply local rules:

```text
Album Artist: Bruce Hornsby & The Range
Sort Album: user convention
Genre: user genre bucket
Compilation: false
Cover Art: selected cover.jpg
```

### 23.6 Canonical vs personal metadata modes

MusicBrainz/Picard will be excellent for:

- Official albums.
- Singles/EPs.
- Many releases with known tracklists.
- Some bootlegs entered into MusicBrainz.
- Files with AcoustID fingerprints.

They will be weaker for:

- Private live recordings.
- Audience tapes.
- Downloaded bootlegs.
- Custom compilations.
- User-created series projects.
- Shows where venue/date/setlist matter more than canonical release identity.

Support two modes:

```text
Canonical Mode
  Use MusicBrainz release metadata.

Personal Live Show Mode
  Use user’s own artist/date/venue/tour/setlist model.
```

Do not force live shows into MusicBrainz’s release model unless there is a real matching release.

### 23.7 Recommended integration levels

Use three levels:

#### Level 1 — Direct MusicBrainz API lookup

Default programmatic path.

```text
Search artist/release
Fetch release metadata
Fetch tracklist
Fetch cover-art links
Return JSON to Swift
```

#### Level 2 — Picard launcher / assisted mode

```text
Open selected folder in Picard
Optionally pass command sequence
Let user manually resolve
Return to MusicWorkbench afterward
```

#### Level 3 — Picard batch automation

Use carefully only when auto-save is explicitly enabled.

```text
LOAD
CLUSTER
LOOKUP_CLUSTERED
SAVE_MATCHED
REMOVE_SAVED
```

Default setting:

```text
Allow Picard to save automatically: off
```

---

## 24. Personal metadata remains authoritative

Even when MusicBrainz/Picard provide canonical metadata, MusicWorkbench should remain authoritative for personal fields:

```text
Project
Series
Live show date
Venue
Tour
Source
Quality
Apple Music sort strategy
Cover art status
Import status
Personal genre bucket
User notes
```

Canonical third-party metadata and personal metadata should be kept distinct.

---

## 25. SwiftUI value areas

SwiftUI adds value for:

- File picking and drag/drop.
- Preview tables.
- Persistent state.
- Quick Look previews.
- Project queues.
- Batch operation selection.
- Run logs.
- Human-friendly parameter forms.
- Folder classification summaries.
- macOS permission/scoped bookmark handling if sandboxed.

Use SwiftUI for the cockpit. Do not use SwiftUI to prematurely rewrite ffmpeg/mutagen-heavy logic.

---

## 26. Python value areas

Keep Python for:

- ffmpeg orchestration.
- ffprobe metadata probing.
- mutagen-based tag reading/writing.
- MusicBrainz API helper via `musicbrainzngs`.
- Bulk filename logic.
- Audio format handling.
- One-off cleanup tools.
- Experiments and migration scripts.

Over time, consolidate scattered scripts into a reusable Python package:

```text
PythonLib/musiclib/
  metadata.py
  filenames.py
  live_show.py
  artwork.py
  ffmpeg.py
  setlist.py
  musicbrainz.py
```

Then individual scripts become thin wrappers around shared functions.

---

## 27. Suggested app navigation

Sidebar:

```text
MusicWorkbench

Inbox
Workflows
  Import Prep
  FLAC → ALAC
  Tag Audio Files
  Normalize Live Show
  Cover Art
  Setlist Tools
  Metadata Assist
  Audit Library
Projects
  Bruce Hornsby Venue Series
  Sting Tour Series
  John Hiatt Series
  Nightwing Covers
Rules
Logs
Settings
```

The main UI should prioritize operational clarity over beauty.

---

## 28. Example mature dashboard

At maturity, the opening screen could show:

```text
MusicWorkbench

Inbox:
7 folders need classification

Active projects:
Bruce Hornsby Venue Series
  23 shows, 9 missing cover art, 4 need tag rewrite

Sting Tour Series
  12 shows, 5 ready to import

Nightwing Covers
  2 covers need final export

Recent runs:
FLAC → ALAC Import Prep succeeded for 1990-08-14 - The Bottom Line
M4A Tag Rewrite failed for 2001-06-03 - missing cover.jpg

Suggested next actions:
- Add cover art to 3 ready shows
- Generate setlist templates for 2 folders
- Re-run M4A tagging on 4 files with corrected extension handling
```

---

## 29. Testing strategy

Create small test fixture folders that exercise known situations:

```text
TestFixtures/
  LiveShowBasic/
    01 - Song.flac
    02 - Song.flac
  AlbumWithCover/
    01 - Track.flac
    cover.jpg
  M4AAlreadyTagged/
    01 - Track.m4a
  MissingArtwork/
    01 - Track.flac
  MixedFormats/
    01 - Track.flac
    02 - Track.mp3
  ExistingOutputConflict/
  WithSetlist/
    01 - Song.flac
    setlist.txt
```

Test:

- Folder scanner classification.
- Audio file detection.
- Cover art detection.
- Setlist detection.
- JSON workflow parsing.
- Script command construction.
- Log creation.
- Non-destructive output behavior.
- Handling of existing output folders.
- MusicBrainz lookup helper JSON shape.

---

## 30. First implementation prompt for Codex

Use this as the initial task prompt:

```text
I want to build a Mac SwiftUI app called MusicWorkbench. It is a personal operations console for my music-library tooling scripts.

The app should not replace Apple Music. It should organize and safely run existing Python/shell workflows that prepare audio files for import into Apple Music.

Core v1 goals:
1. Catalog workflows using JSON manifests.
2. Let me select or drag in a folder.
3. Scan the folder for audio files, cover art, setlist.txt, and existing metadata.
4. Show a plain-English summary of what was found.
5. Let me choose a workflow, fill parameters, preview the command, and run it.
6. Capture stdout/stderr and save a run log.
7. Never modify source files in place by default.
8. Reveal the output folder when finished.

Existing script context:
- There is a music_pipeline.sh that handles EXT=flac|mp3 and should also support m4a/mp4.
- FLAC files should be converted to ALAC.
- M4A/MP4 files should be retagged through ffmpeg without FLAC-to-ALAC conversion.
- The workflow may involve cover art and setlist.txt.
- The app should eventually support live-show naming, cover-art queues, MusicBrainz metadata lookup, optional Picard assisted matching, and Apple Music import prep.

Please propose and then implement the initial skeleton:
- SwiftUI app architecture
- data models
- workflow manifest schema
- script runner service
- folder scanner service
- v1 implementation plan
- safe file-handling rules
```

---

## 31. Strong architectural recommendation

Build a workbench, not a monolith.

Good:

```text
SwiftUI app that catalogs workflows, scans folders, previews actions, runs scripts safely, logs results, and tracks music projects.
```

Bad:

```text
Swift app that tries to know everything, convert everything, tag everything, import everything, replace Picard, replace Apple Music, and replace all prior scripts.
```

The value comes from making the user’s accumulated tooling visible, safe, and repeatable.

---

## 32. One-sentence product definition

**MusicWorkbench is a Mac-native personal operations console that turns scattered music-management scripts into safe, previewable, logged workflows for preparing, tagging, auditing, and tracking music files before import into Apple Music.**
