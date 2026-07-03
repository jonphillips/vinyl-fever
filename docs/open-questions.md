# Open Questions

These are intentionally unresolved. They are prompts for Jon's review.

## V1 Scope

- Which existing script is most important after `music_pipeline.sh`?
- Which remaining steps truly need shell/Python rather than Swift?

## Live Show Prep

- Are the default live-show album title rules in `setlist-formatting-rules.md`
  complete?
- Are the source labels in `setlist-formatting-rules.md` complete, or should
  additional defaults such as `WEB`, `MTX`, or others be added?
- Resolved: see "Verified" in [App Areas](app-areas.md) and Source Of Truth And
  Storage Ownership in [Metadata Policy Model](metadata-policy-model.md). A show
  is verified when its album appears in the Apple Music scan with a matching
  album title and a track count equal to the setlist, with an optional duration
  spot check.
- What Apple Music fields/data should identify an imported album as a live show
  for the chronological artist view?
- What should the local-model live-show label audit flag as "probably mislabeled"?
- Resolved (2026-07-03 review): see *Automation Implications* in
  [Setlist Formatting Rules](setlist-formatting-rules.md). The Normalizer is a
  sandwich — deterministic pre-segment (clean + region hints, no decisions) ->
  frontier LLM via `ModelClient` (all semantic judgment, emits structured JSON)
  -> deterministic validate (tags, ALBUM/DATE shape, controlled source vocab, no
  invented source, track-count sanity) -> mandatory human preview. Source of
  truth is what's on the media, not a reconstructed show. Buildable now,
  independent of the M3 beta-3 pause.
- Resolved: the interactive review session ran 2026-07-03 against a 18-file raw
  corpus; outcomes folded into *Automation Implications*. The rules body remains
  open to revision, but the automation boundary is settled.

## Collection Policies

- What are the first Collection Policies to model?
- Should a policy target an Apple Music playlist, a Smart Playlist rule, or both?
- Is ` | ` the final delimiter for multiple Grouping tokens?
- What should happen when imported files already have Grouping values?
- What should the first folder-application workflow do when a folder contains
  mixed artists or already-tagged songs?
- Which fields can a policy change automatically?
- Which fields always require review?

### Compilation-Album (Append) Policy

- Resolved direction: see *Compilation-Album (Append) Policy* in
  [Metadata Policy Model](metadata-policy-model.md). VF appends tracks to
  curated albums that already exist in Apple Music; it never creates albums or
  the silent cover-carrier track. A small SQLiteData registry (~10–20 entries),
  seeded by folder-drop / parent-folder discovery, is the workspace — not a
  library mirror. Album Artist is the owner identity; track/disc strip defaults
  on (per-album toggle); Compilation flag defaults off (per-album override);
  artwork keeps original embedded art and falls back to the collection cover
  only when a song has none.
- Identity drift is the main open risk: the merge key (`Album` / `Album Artist`)
  is read from file tags, but Apple Music may have mutated it on import, which
  silently spawns a duplicate album instead of merging. First-append
  certification checks the exact album exists and its track count went up. Open:
  how forgiving should the match be — exact string only, or trim/normalize
  whitespace and leading articles before comparing? And what should VF offer when
  the check finds no matching album (block, warn-and-proceed, or open a
  reconcile step to re-point the entry at the real album)?
- Open: when seeding an entry from a folder whose files disagree on `Album` or
  `Album Artist`, which value wins — most common, first, or prompt?

## Metadata Management

- What exactly belongs in Metadata Management versus Collection Management?
- Is Apple Music remediation part of Metadata Management, or should it become its
  own app area later?
- Which first metadata-repair workflow would make this area concrete?

## MusicBrainz and Artwork

- For song-level lookup, what release types should be preferred by default?
- How strongly should various-artist compilations be penalized?
- Are there cases where VA compilation artwork is desired?
- Should cover art be fetched only from MusicBrainz-linked sources, or can the app
  use other sources later?
- Should lookup decisions be cached permanently?

## Apple Music Remediation

- Resolved direction: the read/verification surface is decided early, not later.
  Default to AppleScript/ScriptingBridge as the primary read surface with
  `Library.xml` as a fallback; see Verification Surface in
  [Technical Architecture](technical-architecture.md).
- Should the app ever automate deletion from Music.app, or only prepare manual
  reimport packages?
- What fields does Music.app most often fail to refresh?
- What is the safest manual reimport checklist?

## File Safety

- Should every source file get SHA-256 checksummed before a run?
- Should checksums be required only for destructive or source-mutating workflows?
- Should the app maintain an archive folder for replaced files?
- For failed or unapproved live-show runs, how long should generated `Working/`
  folders be kept before cleanup?

## iPad Companion

- Which screens would be useful away from the Mac?
- Should work queues and metadata policies sync through CloudKit eventually?

## Shared Components

- Extraction trigger: when Vinyl Fever starts consuming model access (Phase 5),
  lift Galavant's `GalavantAI` into a neutrally-named shared package both apps
  depend on, per `jon-platform/docs/adr/0001-extract-model-layer.md`. Confirm the
  path: depend on the extracted shared package (intended), copy/vendor for now, or
  defer AI until after extraction. Recommendation: rename-and-move at Phase 5; do
  not pre-extract and do not copy.
- Resolved (2026-07-03 review): setlist normalization targets the frontier /
  BYO-key tier. The prose-inference, dirty-OCR, and multi-line-jam cases in the
  raw corpus lean on reasoning quality the on-device/Apple-cloud tier cannot yet
  be assumed to reach, so the feature is BYO-required. See *Automation
  Implications* in [Setlist Formatting Rules](setlist-formatting-rules.md). A
  tiered on-device-then-escalate approach remains a possible later optimization.
- Does AcoustID fingerprint lookup ever enter scope? If so, it is the only
  non-model credential; decide whether it reuses the shared Keychain key store.
