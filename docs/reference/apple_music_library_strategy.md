# Apple Music Library Strategy

## Purpose

This document defines a durable, low-chaos strategy for organizing a personally owned Apple Music library that includes:

- canonical albums
- live recordings
- covers
- remixes
- curated crates such as Yacht Rock, Power Pop, Synthpop, Jangle, and Melodic Rock
- decade pools such as 70s, 80s, and 90s
- personal projects built from real files, not just streaming references

The governing principle is simple:

**Use metadata for what a track _is_. Use playlists for what you want to _do_ with it.**

A second principle matters just as much:

**The durable asset is the library item and local file. A playlist is an organizational lens, not fake ownership.**

---

## Core Philosophy

### 1. Separate identity from organization

Every song has several different identities:

- release identity: what album or release it belongs to
- performance identity: studio, live, remix, cover, acoustic, demo, edit, alternate take
- collection identity: Yacht Rock, Power Pop, 90s Hits, Summer Driving, etc.
- playback identity: hand-sequenced mixtape, smart auto-updating bucket, album listening

Trying to force one field to do all of these jobs creates chaos.

### 2. Favor stable fields over improvisation

For custom collections, use a consistent taxonomy in fields that are meant to organize the library.

Primary durable fields:

- Artist
- Album Artist
- Album
- Genre
- Grouping
- custom Sort fields where needed
- Year / Date
- Track number / disc number

Secondary note fields:

- Comments

### 3. Avoid fake metadata unless it buys something substantial

There are times when a fake umbrella album is useful, but it is a hack, not truth. Use it only when containment matters more than canonical browsing.

---

## The Main Decision Tree

### A. Is this a real canonical release?

Examples:
- a normal studio album
- a real soundtrack album
- a legitimate official compilation
- a real bootleg release that is being preserved as a release

If yes:
- keep Artist and Album Artist honest
- keep Album honest
- use Compilation only when it is truly a various-artists release or similar umbrella release
- avoid cramming project labels into Album Artist

### B. Is this a custom listening crate or project?

Examples:
- Yacht Rock Remixes
- Power Pop Essentials
- 90s Female Vocal Tracks
- Best Live Bruce Hornsby

If yes:
- keep the track’s musical identity as honest as practical
- use **Grouping** as the durable crate tag
- use a **Smart Playlist** to gather the crate automatically
- use a **manual playlist** when hand sequencing matters

### C. Is containment more important than canonical artist browsing?

Examples:
- a private 200-song Yacht Rock file bundle you do not want smeared all over the library
- a custom party set treated as one project object

If yes, a controlled fake umbrella-release model can be acceptable:
- Album = custom umbrella title
- Album Artist = umbrella label such as `Yacht Rock Collection` or `Various Artists`
- Artist = actual track artist
- Compilation = on, if you want it treated more like a multi-artist container

Use this sparingly.

---

## Recommended Field Strategy

## 1. Artist

Use for the actual performer on the track.

Examples:
- Christopher Cross
- Toto
- Hall & Oates
- Roxy Music

Rules:
- For covers, Artist is the performer of the version you own, not the original writer.
- For live recordings, Artist remains the performer.
- For remixes, Artist is still the primary performer unless the release clearly credits the remixer as primary artist.

---

## 2. Album Artist

Use for the album-level artist identity.

Normal rule:
- for normal artist albums, Album Artist = artist

Use umbrella Album Artist only when:
- the album is a genuine various-artists compilation
- or you are intentionally creating a contained project object

Preferred umbrella values:
- Various Artists
- Yacht Rock Collection
- 90s Hits Collection
- Jon’s Yacht Rock

Avoid using your own name as Album Artist unless you genuinely want the set to behave like a release by you.

---

## 3. Album

Use for the release title.

Normal rule:
- keep the real album title

Custom-container exception:
- use a fake umbrella album name only when the set is intentionally being modeled as one contained object

Examples:
- Yacht Rock
- Yacht Rock Remixes
- Power Pop 1978–1984

This is a conscious tradeoff, not a truth claim.

---

## 4. Compilation

What it is good for:
- true various-artists albums
- soundtracks
- tribute albums
- custom contained crates where you actively want the songs grouped together instead of behaving like normal artist albums

What it is bad for:
- giant general-purpose decade pools that should really be playlists
- normal artist albums
- situations where artist browsing matters more than containment

Recommendation:
- **On** for small, intentional, quarantined project crates when containment matters
- **Off** for the canonical library and for large era buckets like a general 90s collection

Rule of thumb:
- 200-song Yacht Rock project: compilation can be defensible
- 2,000-song 90s library slice: compilation is usually the wrong architecture

---

## 5. Grouping

This is the most important custom organizational field.

Use Grouping for durable crate identity.

Examples:
- Yacht Rock
- Yacht Rock Remixes
- Power Pop Core
- Jangle Essentials
- Synthpop Driving
- 90s Unified
- Bruce Hornsby Live
- Covers
- Acoustic Versions

Why Grouping matters:
- it is durable metadata on the track itself
- it is appropriate for Smart Playlist rules
- it is cleaner than abusing Comments
- it gives you a permanent collection tag without lying too hard about Album or Album Artist

Recommendation:
- Use Grouping as the primary field for personal collection taxonomies.

### Grouping style rules

Choose one of these models and stick to it.

#### Model A: Flat labels
- Yacht Rock
- Yacht Rock Remixes
- Power Pop
- Covers
- Live

#### Model B: Hierarchical-ish labels
- crate/Yacht Rock
- crate/Yacht Rock Remixes
- crate/Power Pop
- format/Live
- format/Cover
- format/Remix
- era/90s Unified

#### Model C: Human-readable structured labels

- Yacht Rock :: Core
- Yacht Rock :: Remixes
- Power Pop :: Tier 1
- Live :: Bruce Hornsby
- Covers :: Power Pop

This is the preferred model for a sophisticated personal library.

---

## 6. Comments

Use Comments for notes, not primary taxonomy.

Good uses:
- source: Soulseek batch 3
- replace with better mastering
- from deluxe edition
- need artwork cleanup
- duplicate candidate
- alternate intro

Bad uses:
- repeating the same collection label already stored in Grouping

Recommendation:
- do **not** put `Yacht Rock Remixes` in both Grouping and Comments unless Comments is serving a second purpose

If you want structured comments, use a note format such as:
- source: local files
- status: keeper
- quality: strong
- artwork: custom

---

## 7. Sort Fields / Sort As Strategy

There are really **two separate Sort As problems** in this library:

1. **Sort Album** — how releases, boxes, bootlegs, sessions, remix discs, and live shows line up in artist view
2. **Sort Song** — how alternate song versions line up within a release or across browse views

The older recommendation was stronger on the first problem than the later draft, so this structure keeps that emphasis.

## 7A. Sort Album as the primary release-order tool

For this library, **Sort Album** should do the heavy lifting for non-canonical material.

The goal is to make artist discographies browse in a stable, intentional order such as:
- normal studio albums first
- then compilations / boxes / soundtracks if desired
- then singles / remix sets / EPs
- then sessions / demos / rarities
- and live in a sensible location without requiring massive retrofit work

That is a much better fit for show-based material than trying to solve everything with Sort Song.

### Core buckets (recommended)

There are two viable philosophies here.

#### Philosophy 1: Full explicit bucketing

This is the maximal-control approach where every non-canonical format gets an explicit numeric Sort Album prefix.

- `0100 Studio` (usually implicit; often leave canonical studio albums alone unless needed)
- `1000 Compilation`
- `1100 Box Set`
- `1200 Soundtrack`
- `1300 Tribute / Various Artists`
- `2000 Single/EP/Remix`
- `2100 EP`
- `2200 B-Sides / Rarities`
- `3000 Radio / Sessions`
- `4000 Demos / Outtakes`
- `5000 Rehearsals / Soundchecks`
- `9000 Live`

This gives the most deterministic browse order, but it is labor-intensive if you already have a large live archive named in a consistent date-led way.

#### Philosophy 2: Minimal-intervention bucketing (recommended)

This is the better fit when you already have many live shows named consistently like:
- `2012-08-15: Boston, MA - Fenway Park`

Under this model, **live recordings are left unprefixed** and use their existing chronological show naming. Only the categories that actually need help are prefixed.

Recommended working set:
- studio albums: leave normal
- live shows: leave normal if already date-led and consistent
- `1000 Compilation`
- `1100 Box Set`
- `1200 Soundtrack`
- `1300 Tribute / Various Artists` (optional)
- `2000 Single/EP/Remix`
- `2100 EP` (optional)
- `2200 B-Sides / Rarities`
- `3000 Radio / Sessions`
- `4000 Demos / Outtakes`
- `5000 Rehearsals / Soundchecks`

This has a major practical advantage:
- you do **not** have to retrofit thousands of existing live-show Sort Album values just to make the theory look cleaner

The tradeoff is that live will no longer be forced to the absolute bottom via `9000 Live`. Instead, live shows will sit in natural chronological order wherever your broader sort behavior places them. In practice, this is often acceptable and far less tedious.

### Current recommendation

For this library, the recommended model is **minimal-intervention bucketing**:
- leave standard studio albums alone
- leave existing live-show names alone when they already follow a clean `YYYY-MM-DD: City, ST - Venue` pattern
- use numeric Sort Album buckets only for the non-canonical release types that actually need browse control

In other words:

- **prefix the exceptions, not the whole universe**

### Format templates

#### Compilations
- Sort Album = `1000 Compilation - Collected Classics Vol. 1`
- Album = `Collected Classics Vol. 1`

#### 12-inch singles / remix releases
- Sort Album = `2000 Remix - 1987 - Midnight Blue (Germany 12")`
- Album = `Midnight Blue (Germany 12")`

#### Sessions
- Sort Album = `3000 Session - 1991-04-28: Mountain Stage (NPR) - Charleston, WV`
- Album = `1991-04-28: Mountain Stage - Charleston, WV (NPR FM)`

#### Live (two options)

##### Option A: full explicit bucketing
- Sort Album = `9000 Live - 2006-10-24: Upper Darby, PA - Tower Theater (FM)`
- Album = `2006-10-24: Upper Darby, PA - Tower Theater (FM)`

##### Option B: minimal-intervention live naming (recommended)
- Sort Album = `2006-10-24: Upper Darby, PA - Tower Theater (FM)`
- Album = `2006-10-24: Upper Darby, PA - Tower Theater (FM)`

Option B preserves the existing live-show naming strategy and avoids a huge retrofit.

This gives the browsing flow:
- studio
- compilations / boxes / soundtracks
- singles / remixes / EPs
- sessions / demos / rehearsal material
- and then either live last **if you use explicit 9000 bucketing**, or live in natural chronological show order **if you use the minimal-intervention model**

## 7B. Re-evaluation of the bucket scheme

This older scheme was fundamentally good. The overall architecture still works, but full `9000 Live` retrofitting is not the best recommendation for an existing library with a large date-led live archive.

### Keep
- `3000 Radio / Sessions`
- `4000 Demos / Outtakes`
- `5000 Rehearsals / Soundchecks`
- `2000 Single/EP/Remix` for the 12-inch world

### Slightly refine

`1000 Compilation` and `1300 Tribute / Various Artists` overlap a bit.

Current preference:
- use `1000 Compilation` for best-ofs, label comps, curated comps, and most umbrella collections
- use `1300 Tribute / Various Artists` only if you genuinely want a distinct browse zone for tribute albums and VA material

If not, collapse `1300` into `1000` and simplify.

Likewise, `2000 Single/EP/Remix` and `2100 EP` can either remain separate or be merged depending on how much you care about EP distinction. If you browse EPs as a meaningful format, keep both. If not, merge them.

## 7C. Studio albums

The old note was correct: usually do **not** force Sort Album prefixes onto normal studio albums.

That keeps the canonical discography cleaner.

Default rule:
- leave standard studio albums with honest Album / Sort Album unless there is a specific problem to solve

Only apply `0100 Studio` if you need explicit bucket ordering against a lot of custom material for a specific artist.

## 7D. Sort Song for song-centric variants

Sort Song is still valuable, but it is the **secondary** layer.

Use it for alternate versions of the same song:
- `Africa`
- `Africa 10 Live`
- `Africa 20 Remix`
- `Africa 30 Acoustic`
- `Africa 40 Cover`
- `Africa 50 Demo`

This is good for:
- song-centric variants
- different versions of the same underlying composition
- keeping live/remix/acoustic versions adjacent

This is **not** the primary tool for show archives.

## 7E. Show-centric live recordings

This was the main source of confusion.

If the material is really a **show object**, chronology belongs in **Album / Sort Album**, not in a song-variant Sort Song convention.

Recommended default for bootlegs, audience recordings, FM broadcasts, and soundboards:
- Album = `YYYY-MM-DD: City, ST - Venue`
- Sort Album = the same date-led show string, unless you have a specific reason to normalize punctuation
- Name = actual track title
- Sort Song = normal song-title sort, only if needed

This is the preferred default for this library.

### Why this works
- the show already sorts chronologically
- it preserves the existing naming investment
- song titles remain usable as songs
- you do not have to retrofit a `9000 Live -` prefix across the archive

### When to use explicit live bucketing anyway

Use `9000 Live - ...` only if one of these is true:
- you are doing a fresh import and can standardize cheaply
- you deeply care that live must always appear after all canonical releases in artist browse order
- the artist has enough mixed-format archival material that a hard live bucket materially improves browsing

Otherwise, leave live shows unprefixed.

## 7F. If you insist on date-led titles in Name

If you keep the visible **Name** itself as a date-led show string, then Sort Song should mirror chronology, not variant grouping.

Example:
- Name = `2012-08-15: Boston, MA - Fenway Park`
- Sort Song = `2012-08-15 Fenway Park Boston MA`

But this is second-best. Prefer putting show identity in Album instead.

## 7G. Practical recommendation

### Use Sort Album buckets for:
- compilations
- box sets
- soundtracks
- singles / remix sets / EPs
- sessions
- demos / outtakes
- rehearsals / soundchecks
- live shows only when explicit live-last ordering is worth the editing effort

### Use Sort Song for:
- live versions of a song
- remixes
- acoustic versions
- covers
- demos
- edits / instrumentals / extended versions

### Do not force one scheme onto both problems

The right split is:
- **release / show order -> Sort Album**
- **version adjacency -> Sort Song**

## 8. Genre

Genre should be used sparingly and intentionally.

Avoid dozens of micro-genres unless you enjoy taxonomy maintenance as a hobby.

Recommended broad genre set:
- Rock
- Pop
- Power Pop
- New Wave
- Synthpop
- Jangle Pop
- Yacht Rock
- Melodic Rock
- Soul / R&B
- Alternative
- Singer-Songwriter
- Soundtrack
- Holiday

For this library, Genre can do real work if used with discipline.

### Recommendation

Use Genre for real musical identity, not collection identity.

Good:
- Power Pop
- Yacht Rock
- Synthpop

Bad:
- Jon’s Good Stuff
- Summer Dinner Music
- Poolside

Those belong in Grouping or playlists.

---

## 9. Year / Date

Use actual year whenever possible.

For remasters and reissues, decide which year matters for browsing:
- original song/release year
- or release-package year

Recommendation:
- for listening and decade sorting, prefer the **original release year** unless you are preserving release-history precision for collector reasons

This makes decade playlists much saner.

---

## 10. Track Number / Disc Number

Use honestly for real albums.

For fake umbrella albums or custom containers, track number can be used deliberately to impose sequence.

This is most useful when:
- you intentionally modeled a crate as an album
- you want a stable default play order

Do not depend on track numbers alone for Smart Playlist listening behavior. If sequence matters a lot, use a manual playlist.

---

## Playlist Architecture

## 1. Standard Playlists

Use for:
- hand-curated listening sets
- exact playback order
- party mixes
- road trip sequences
- “best of” personal tapes

Strengths:
- manual control
- easy reordering
- emotionally satisfying and concrete

Weaknesses:
- membership must be maintained by hand

## 2. Smart Playlists

Use for:
- automatically gathering all tracks with a certain Grouping
- decade rules
- quality filters
- favorite subsets
- maintenance views

Examples:
- Grouping is `Yacht Rock :: Remixes`
- Grouping contains `Power Pop`
- Genre is `Synthpop` and Year is in the range `1980` to `1989`
- Comments contains `duplicate candidate`

Strengths:
- automatic
- durable
- scalable

Weaknesses:
- not ideal for carefully hand-authored sequencing

## 3. Playlist Folders

Use to create a visible architecture.

Recommended top-level folders:
- Crates
- Decades
- Projects
- Maintenance
- Artist Series
- Moods / Situations

---

## Recommended Library Architecture

## A. Canonical library

This is the default home for music that should behave normally.

Rules:
- Artist honest
- Album Artist honest
- Album honest
- Compilation only when true
- Genre disciplined
- original year preferred

## B. Crates

Examples:
- Yacht Rock
- Yacht Rock Remixes
- Power Pop Core
- Jangle Essentials
- Synthpop Driving
- Melodic Rock Arena

Rules:
- Grouping carries the crate tag
- Smart Playlist gathers the crate automatically
- manual playlist optional for sequence

## C. Decades

Examples:
- 70s Unified
- 80s Unified
- 90s Unified

Recommendation:
- these should usually be playlists or Smart Playlists, not fake albums

Possible rule:
- Year 1990 through 1999

Optional additional rule:
- Grouping contains `90s Unified`

## D. Format / version buckets

Examples:
- Covers
- Live
- Acoustic
- Remixes
- Demos

Recommendation:
- tag these through Grouping and/or Sort Song logic
- optionally build Smart Playlists from them

---

## Suggested Taxonomy Examples

## Yacht Rock system

Track fields:
- Artist = actual artist
- Album Artist = actual album artist, unless intentionally contained as a project release
- Genre = Yacht Rock or related main genre
- Grouping = `Yacht Rock :: Core` or `Yacht Rock :: Remixes`
- Sort Song = base title plus version ordering if needed

Playlists:
- Smart Playlist: `Yacht Rock :: Core`
- Smart Playlist: `Yacht Rock :: Remixes`
- Manual Playlist: `Yacht Rock Party Sequence`

## Power Pop system

Track fields:
- Genre = Power Pop
- Grouping = `Power Pop :: Tier 1` or `Power Pop :: Tier 2`
- Comments optional for source or keeper notes

Playlists:
- Smart Playlist: `Power Pop :: Tier 1`
- Manual Playlist: `Power Pop All-Timers`

## Live recordings system

Track fields:
- Artist = performer
- Album = real live album or honest release title if possible
- Grouping = `Live :: Artist Name` or `Live :: General`

Recommended split:

### Official or song-centric live releases
- Name = song title
- Sort Song = base title plus `10 Live` if version adjacency matters

### Bootlegs / audience recordings / show-centric archives
- Album = `YYYY-MM-DD: City, ST - Venue`
- Sort Album = normalized or identical chronological show label
- Name = actual song title whenever possible
- Grouping = `Live :: Artist Name`

This is the cleaner answer to the date-title problem. Put chronology in Album / Sort Album rather than corrupting song-level sort logic.

Playlists:
- Smart Playlist: `Live :: Bruce Hornsby`
- Smart Playlist: `Live Tracks`

## Covers system

Track fields:
- Artist = performer of the cover
- Comments optional for original artist or song provenance
- Grouping = `Covers :: [theme or source]`
- Sort Song = base title plus `40 Cover` if useful

Playlists:
- Smart Playlist: `Covers`
- Smart Playlist: `Covers :: Power Pop`

---

## Concrete Recommendations

## Default rules

1. Use **Grouping** as the durable custom collection field.
2. Use **Comments** only for notes and maintenance annotations.
3. Use **Smart Playlists** for automatic membership.
4. Use **manual playlists** when order matters.
5. Use **Compilation** only for true various-artists releases or intentionally quarantined small project crates.
6. Use **Sort fields** to keep alternate versions adjacent without mangling visible titles.
7. Use **Genre** for musical identity, not temporary listening themes.
8. Use **playlist folders** to make the architecture feel permanent and intentional.

## Specific recommendations

### For Yacht Rock Remixes
- Grouping = `Yacht Rock :: Remixes`
- Comments = blank unless you need a real note
- Smart Playlist = Grouping is `Yacht Rock :: Remixes`
- manual playlist only if you want sequence control

### For live show collections with date-led naming
- prefer putting the show identity in Album, not Name
- visible Album = `YYYY-MM-DD: City, ST - Venue`
- default Sort Album = the same date-led show string
- optionally normalize Sort Album only if punctuation is causing a real browse problem
- keep Name as the actual track title
- reserve song-level Sort Song tricks like `10 Live` and `20 Remix` for song-centric material, not show-centric entries
- do **not** feel compelled to add `9000 Live -` retroactively unless the browse benefit is clearly worth the labor

### For giant decade bins
- do not fake them as albums unless there is a very specific containment reason
- use Smart Playlists driven by Year and optional Grouping

### For small quarantined private sets
- if containment matters more than canonical browse behavior, a fake umbrella Album + Album Artist + possibly Compilation can be acceptable
- but still consider adding a Grouping tag, because it gives you a cleaner exit path later

---

## Operational Workflow

When importing or cleaning tracks, process in this order:

1. Fix core identity
   - song title
   - artist
   - album artist
   - album
   - year
   - track number

2. Fix musical classification
   - genre
   - media kind if relevant

3. Apply durable personal organization
   - grouping
   - sort fields

4. Add maintenance notes only if needed
   - comments

5. Add to playlists
   - smart playlists auto-populate
   - manual playlists for presentation and sequence

---

## What Not To Do

- Do not use Comments as your main organizational field.
- Do not use Album Artist as a junk drawer for every custom project.
- Do not fake giant decade collections into albums unless you really mean it.
- Do not duplicate the same label in Grouping and Comments without a reason.
- Do not mutilate visible song titles just to force sorting behavior; use Sort fields.
- Do not assume playlist means fragile. The playlist is a view; the file and library item are the asset.

---

## Preferred Final System

### Permanent metadata layer
- honest Artist / Album Artist / Album wherever practical
- Genre disciplined
- Grouping as the durable crate tag
- Sort fields used for alternate versions and browse control
- Comments only for actual notes

### Library views layer
- Smart Playlists for automatic collection buckets
- manual playlists for hand-authored listening sequences
- playlist folders for visible structure and permanence

### Limited hack layer
- fake umbrella albums only for selected contained private projects where that presentation is genuinely worth the distortion

---

## Short Version

If this had to be reduced to five rules:

1. **Grouping is your permanent crate tag.**
2. **Comments is for notes, not taxonomy.**
3. **Smart Playlists gather; manual playlists perform.**
4. **Sort Album handles release/show ordering; Sort Song handles version adjacency.**
5. **Compilation is a niche containment tool, not the backbone of the library.**

---

## Future Refinements

Possible next steps:
- define an exact controlled vocabulary for Grouping values
- define a controlled vocabulary for Comments notes
- define an exact Sort Song numbering convention
- create a recommended folder and playlist structure for the entire library
- create an import checklist for new files
- create specific rules for artwork, live-show dating, bootlegs, and custom cover images
