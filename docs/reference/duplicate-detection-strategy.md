# Duplicate Detection Strategy (per import path)

Short reference for **how well Vinyl Fever can tell, before importing, that a
track is already in the Apple Music library** — and why the answer differs
sharply between the two ways songs enter the library.

The governing fact: our only view into Music is ScriptingBridge, and the live
client deliberately pushes a `whose album CONTAINS[cd] …` predicate down into
Music so it materializes **one album's** tracks, never the whole library
(`VinylFever/Clients/MusicAppClient+Live.swift`). That single choice is why the
two paths diverge. Available per-track fields: `persistentID`, `title`, `album`,
`albumArtist`, `trackNumber`, `duration`, `location` (file URL).

## The two import paths

1. **Registered collection import** — a structured `ConversionPlan` for a known
   album. We know the target `AlbumIdentity` (album + album artist) *before*
   touching Music. Small, well-defined search space.
2. **Generic metadata-driven import** — files dropped into Music to "land
   wherever their metadata says." No known target coordinates; the whole library
   is the search space.

## Case 1 — Registered collections: crisp, ahead of time ✅

This is fully answerable and largely already built.

- Because we know the album coordinates, we do a **cheap scoped read** of just
  that album (`readAlbumTracks(albumTitle:)`), fast and well under the read
  timeout.
- `MusicLibraryMatcher.resolve` matches each produced file against the album's
  Music tracks by, in order:
  1. **exact file location** (the file URL) — a hard "this exact file is already
     imported",
  2. **album + track number + title**,
  3. leaving anything with >1 hit **unresolved / ambiguous**.
- A resolved match is exactly the `.alreadyPresent` verdict the executor applies
  on import (`VinylFeverCore/…/Apply/LibraryImportExecutor.swift`).

**This verdict is trustworthy because the collection defines the coordinates we
match against.** It is surfaced pre-import in the "Read Music" preview
(`LibraryReadStatus` / `LibraryTrackResolutionRow` in `LiveShowsView.swift`) as a
per-track "Already in Music — import will skip" / "New — will import" line plus a
summary count (`N already in Music · M new`).

## Case 2 — Generic metadata-driven import: only "probably" ⚠️

Not answerable with certainty ahead of time, and the reason is **structural**,
not a lack of effort:

- **No known target coordinates.** The point is the track sorts itself by its own
  tags, so we can't do a cheap scoped read. Being sure would require searching
  the *whole* library — and materializing tens of thousands of `fileTrack`s per
  import batch via ScriptingBridge is slow and brushes the timeout. It does not
  scale to a massive library.
- **"Duplicate" is fuzzy.** The same recording appears as *feat.* vs
  *featuring*, remaster-year variants, punctuation drift, different
  formats/bitrates, or a different file path. Without a canonical key there is no
  crisp yes/no — only a confidence score.

So for the generic bucket the honest product promise is a **"probable duplicate"
warning, not a certain one.**

## If Case 2 ever needs to scale

The right move is **not** a bigger live per-import Music scan — it's a **local
index we own** (SQLiteData, already the house stack). Refresh it periodically
from Music, storing per track: `persistentID`, normalized `location`, and a
normalized dedupe key `(artist, title, album, duration-bucket)`. Pre-import
dedupe then becomes an instant offline lookup that also catches cross-tag
variance because we control the normalization.

Tiers of certainty, cheapest first:

| Signal | Catches | Cost |
| --- | --- | --- |
| Exact file location | "this exact file already imported" (perfect, if files aren't moved) | free |
| Normalized `(artist, title, duration)` key | "same song, different tags/format" | cheap with a local index |
| Acoustic fingerprint (Chromaprint / AcoustID) | "same recording, any tags" — gold standard | heavy, per-file decode |

## Bottom line

Build crisp pre-import dedupe **only on the collection path** — it's largely
there, and its `.alreadyPresent` verdict is now surfaced in the import preview.
For the generic bucket, set expectations to a probable-duplicate warning; if it
becomes a real pain point, add a local SQLiteData mirror of the library rather
than scaling the live scan.
