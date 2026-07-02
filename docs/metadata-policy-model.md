# Metadata Policy Model

## Core Concept: Collection Policy

A Collection Policy defines why a track belongs in a specific playlist, crate,
smart playlist, or collection, and what metadata/artwork policy applies because
of that membership.

The playlist is the visible destination or view. The Collection Policy is the
app-owned definition of what that destination means and what rules apply.

In human terms:

A playlist answers, "Where should this song show up?"

A Collection Policy answers, "Because this song belongs there, what should we do
to its metadata, artwork, lookup behavior, and import checklist?"

## Collection Policy Fields

A policy should define:

- Name.
- Description.
- Target playlist or smart playlist rule.
- Required `Grouping` token or tokens.
- Genre policy.
- Album policy.
- Album Artist policy.
- Artist policy.
- Compilation policy.
- Comments policy.
- Sort field policy.
- Artwork policy.
- MusicBrainz lookup policy.
- Confidence threshold policy.
- Whether manual review is required.

## Grouping As Collection Carrier

Apple Music's most reliable durable field for collection membership is
`Grouping`.

Collection Policy membership should therefore be represented in Apple Music by
one or more Grouping tokens. Avoid using `Comments`, `Album Artist`, or visible
song titles as collection-policy plumbing.

Working format for multiple collection memberships:

```text
Grouping: Yacht Rock :: Remixes | Great Covers | Power Pop :: Covers
```

Rules:

- Use ` | ` as the delimiter between Grouping tokens.
- Treat ` | ` as the v1 delimiter unless Apple Music behavior proves otherwise.
- Trim whitespace around tokens when reading.
- Do not allow `|` inside a token name.
- Preserve existing unknown tokens unless the user explicitly removes them.
- Smart Playlists should match on a specific token contained in `Grouping`.
- The app may keep richer Collection Policy state in SQLiteData, but the Apple
  Music/file-tag representation should be Grouping-based.

Grouping uses a two-level grammar: `::` is intra-token hierarchy
(`Yacht Rock :: Remixes`) and ` | ` separates whole tokens
(`Yacht Rock :: Remixes | Great Covers`). When generating a Smart Playlist for a
specific token, match the full token string (`Power Pop :: Covers`), not a bare
leaf, because Apple Music "contains" matching is a substring test: a rule for
`Covers` would also catch `Yacht Rock :: Covers`. Match a bare leaf only when
that union is intended.

Simple v1 policy matching:

- A track belongs to a Collection Policy when `Grouping` contains the policy's
  token.
- A policy may optionally narrow membership by artist name.
- A policy can be applied to a selected Finder folder or set of folders by adding
  the policy token to the contained songs' `Grouping` field.

## Compilation-Album (Append) Policy

A **Compilation Album** is a curated album Jon manufactures in Apple Music to
hold a set of otherwise-unrelated songs — "Great Covers", "Rare Hits from the
80s" — so that a crowd of one-hit-wonder artists does not pollute the Artists
list. It is the "intentionally quarantined small custom crate" case named in the
field defaults below, and it is a concrete *flavor* of Collection Policy where
the **album identity** (Album, Album Artist, artwork) is the payload, not just a
Grouping token.

This policy is deliberately narrow: **these albums already exist in Apple Music.**
Jon builds and maintains each album by hand, including the cover-art hack (a
single 2-second silent "carrier" track that is the album's *only numbered track*
and carries the collection cover so Apple Music renders it). Vinyl Fever does not
create albums, generate the carrier track, or manage artwork on the album as a
whole. Its one job is to make **adding new tracks** to an existing curated album
painless.

### Album Artist as owner identity

This policy intentionally overrides the "avoid using `Album Artist` as
collection-policy plumbing" rule under *Grouping As Collection Carrier*. The
distinction that keeps the two consistent:

- Using Album Artist as **membership** plumbing (which songs belong to a theme)
  is still forbidden — that stays in `Grouping`.
- Using Album Artist as the **album's owner identity** (`Album Artist =
  Jon Phillips`) is exactly what the field is for, and it is the lever that keeps
  a various-artists album grouped as one album and off the Artists list.

So a Compilation Album sets `Album Artist` deliberately, and `Grouping` may still
carry the collection token independently.

### The Registry

Vinyl Fever keeps a **small registry of only the curated albums this feature
manages** — on the order of 10–20 entries — in SQLiteData. This is not a mirror
of the (out-of-control) Apple Music library; browsing the whole library is the
pain this feature exists to avoid, so this policy barely touches the Music.app
read surface.

Seed the registry from **folders, not from the library**:

- Drop **one album's folder** → VF reads the contained files' existing tags →
  proposes an entry (Album, Album Artist, a thumbnail lifted from the folder's
  embedded art) → Jon confirms.
- Drop a **parent folder of album subfolders** → VF discovers each subfolder and
  presents the list to check off. That checkable discovered-folder list *is* the
  "skim a short list" gesture — short and relevant, not thousands of albums.

A registry entry holds:

- **Display**: name + image, used only to find the album in the workspace. The
  image is a workspace locator; it is **not** embedded into files by VF and is
  **not** the carrier-track art (Jon owns that).
- **Identity** (the merge key): the exact `Album` and `Album Artist` strings,
  read from the seeding folder's file tags.
- **Ruleset**:
  - Strip all track/disc numbers — **default ON**. These are unrelated one-off
    songs; inherited track/disc numbers make album display and playback chaotic.
    Per-album toggle.
  - `Compilation` flag — **default OFF**, per-album override. Album Artist is the
    grouping lever; the Compilation flag (which routes into Apple Music's
    Compilations bucket) is opt-in only.
  - Grouping token(s) to add, if any.
  - Artwork: **keep each song's original embedded art; apply the collection cover
    only as a fallback for songs that have none.** The keep-vs-fallback branch
    reads `AudioTags.hasEmbeddedArtwork` per file.

### Append Flow

1. Pick a target entry from the short registry.
2. Point VF at the folder of new songs to add.
3. VF stamps each new song with the entry's identity (`Album`, `Album Artist`)
   and applies the ruleset (strip track/disc, compilation flag, grouping,
   artwork keep-else-fallback).
4. Show the preview diff required by *Preview Requirements* below; Jon confirms.
5. Write tags → import into Apple Music → certify.

VF only ever touches the new-songs folder, so the existing carrier track and its
number are never at risk.

### Identity drift and certification

The merge key comes from **file tags**, but Apple Music is a lossy display layer
that may have mutated the album's title or artist on its way in. If the registry
says `Great Covers` and Apple Music actually stored `Great Covers ` (trailing
space) or `The Beatles` vs `Beatles`, an append does not merge — it silently
spawns a duplicate album (`Great Covers 2`).

Certification is therefore the whole ballgame for this policy, and it reuses the
existing verification step:

- On **first append** to an entry (and on demand), run a lightweight check: does
  an album with this exact `Album` / `Album Artist` already exist in Apple Music,
  and after import did that album's track count increase (rather than a second
  album appearing)?
- Certify-not-enumerate also governs the Album Artist cleanup: VF writes the one
  canonical Apple Music album-artist field and certifies it reads back correctly.
  It does **not** attempt to enumerate and delete every album-artist-shaped tag
  variant across formats; it strips a variant only if certification shows Apple
  Music is confused by it.

## Apple Music Field Defaults

Follow [reference/apple_music_library_strategy.md](reference/apple_music_library_strategy.md).

Default principles:

- Use `Grouping` as the durable custom collection field.
- Use `Comments` only for notes and maintenance annotations.
- Use Smart Playlists for automatic membership.
- Use manual playlists when order matters.
- Use `Compilation` only for true various-artist releases or intentionally
  quarantined small custom crates.
- Use Sort fields to control browsing without mangling visible titles.
- Use Genre for musical identity, not temporary themes.

## Canonical Metadata vs Personal Metadata

Keep these distinct.

Canonical metadata answers:

- What recording is this?
- Who performed it?
- What release did it originally or canonically appear on?
- What date/country/label/barcode/tracklist belongs to that release?
- What cover art is associated with that release?

Personal metadata answers:

- Why is this file in Jon's library?
- Which policy/playlist/collection does it belong to?
- What Grouping value should it carry?
- Should visible Album be preserved or changed?
- Should collection artwork replace canonical artwork?
- Has this item been imported and verified?

Vinyl Fever should use canonical sources as evidence, not as automatic truth
for every field.

## Source Of Truth And Storage Ownership

This is a settled decision. Vinyl Fever does not maintain a shadow catalog of
shows that it keeps in sync with Apple Music. But "Apple Music is the source of
truth" is split deliberately, because Apple Music is a lossy, mutable display
layer, not a database.

There are three stores, with different jobs:

1. **Local audio files and their embedded tags** — the canonical *write target*
   and the durable asset. Truth is written into the FLAC/ALAC/MP3/M4A tags first;
   Apple Music ingests it downstream. The files are portable and survive Apple
   Music doing something unexpected.
2. **Apple Music library** — the source of truth for *presence and display*:
   whether a show exists in the collection, how it appears, and what plays. It is
   authoritative for "what do I have / what is missing," but it is a projection,
   and it can mutate or drop data (iCloud Music Library may match, replace, strip
   embedded artwork, or rewrite metadata when Sync Library is on).
3. **SQLiteData (optionally iCloud)** — two distinct jobs:
   - a **rebuildable cache/index** of the Apple Music scan, so the live-show
     library view can browse and query quickly. This is disposable; a rescan
     repopulates it. It is never a rival source of truth for presence.
   - the **app-owned fields Apple Music cannot represent**, plus operational
     state. These are not "helper data"; for these fields SQLiteData is the only
     home.

One-line statement of the rule:

- Apple Music is the source of truth for *whether a show exists and how it
  appears*.
- The files are the source of truth for *what the show actually is*.
- SQLiteData holds *everything Apple Music cannot carry, plus a throwaway cache
  of the scan*.

### Consequences

- The live-show library view is a projection of an Apple Music scan, not a
  hand-maintained table. Do not add a `LiveShow` record that claims to be the
  authoritative master.
- Folder scans and the live-show index in SQLiteData are caches with a
  timestamp. Every view must tolerate "this is stale, rescan."
- The verification step exists precisely because writing tags to files does not
  guarantee Apple Music reflected them. Write to files, import, then verify the
  library shows the expected album and track count.
- "If it is not in Apple Music it is as good as missing" is true for the
  *presence* question only. It is not a storage rule: it must never be used to
  justify discarding app-owned fields, because Apple Music cannot store them.

### Fields Apple Music Cannot Hold

Several fields in the live-show model from [App Areas](app-areas.md) have no
native home in Apple Music and therefore live only in SQLiteData:

- Tour.
- Recording quality grade.
- Lineage. (The [Setlist Formatting Rules](setlist-formatting-rules.md)
  explicitly forbid putting lineage into tags.)
- Source-file provenance and original paths.
- Import status and verification status (correctly app/operational state).

Fields Apple Music *can* carry (artist, album title encoding date/venue/source,
track titles as the setlist, artwork, disc/track structure, sort album) are
written into the file tags and verified in the library as above.

## MusicBrainz Lookup Policy

MusicBrainz lookup should not blindly accept the first high-scoring release.

For song-level collection prep, prefer the original or canonical album/single
source over arbitrary various-artist compilations unless the Collection Policy
explicitly wants a compilation/container identity.

Ranking should consider:

- Performer and title match.
- Recording match.
- Track artist credit.
- Release artist credit.
- Release group type: album, single, EP, soundtrack, compilation.
- Whether release is various artists.
- Whether track appears on an official release.
- Date plausibility.
- Country/label preference if configured.
- Track count and track position.
- Cover art availability.

Default ranking posture:

- Prefer release by the actual performer.
- Prefer official album/single/EP over generic VA compilation.
- Penalize huge generic compilations.
- Penalize "various artists" when trying to recover original source.
- Allow a Collection Policy to override this when the compilation itself is the
  desired identity.

## Artwork Policy

Artwork policy should be role-specific.

Possible policies:

- Preserve existing artwork.
- Use canonical release artwork.
- Use original album artwork.
- Use single artwork if it better represents the track.
- Use custom collection artwork.
- Use live-show series artwork.
- Require manual artwork review.
- Do not change artwork.

For covers/remixes/playlist roles, the app should show why it recommends an
image. It should not silently swap artwork based on a weak lookup.

## Preview Requirements

Before writing tags, show:

- Current file path.
- Current title/artist/album/album artist.
- Current Grouping, Genre, Compilation, Comments, Sort fields.
- Current artwork status.
- Proposed metadata.
- Proposed artwork source.
- Why MusicBrainz candidate was chosen.
- Fields that will be preserved.
- Fields that require manual review.

The user should be able to reject or edit proposed changes before writing.
