# Effort — A show's album title fills its date, venue, and location

Status: Dispatched
Summary: A setlist whose ALBUM line is already `YYYY-MM-DD: Location - Venue` leaves Date, Venue, and Location as Unknown, and the plan then tags the files `Unknown Date: Unknown City - Unknown Venue (SBD)`. Read the three fields back out of a well-formed album title, both when a setlist is parsed and when Jon types the Album field.

Related: [M1](../../milestones/archive/M1-live-show-plan-preview.md) · [Efforts index](../README.md)

Branch `effort/album-title-fills-show-fields`, from a fresh `main`. One PR. No schema change, no
sync change, and no file changes format.

## Why

On 2026-11-21 Jon opened *Dave Hause - Live from Chicago 2026* in Live Shows. The Album field read
`2026-02-27: Chicago, IL - Sleeping Village`, and Source was SBD. Date, Venue, and Location all
showed Unknown.

The architect traced it in the code:

- **The parser reads only explicit lines.** `SetlistParser.applyTag` fills `date`, `venue`, and
  `location` only from `DATE:`, `VENUE:`, and `LOCATION:` lines. From `ALBUM:` it keeps the whole
  value and recovers only the trailing `(Source)`. Nothing reads the date, location, or venue
  back out of an album title in the format the app itself writes.
- **The plan builds the album from those fields.** `ShowMetadata.albumTitle` (the `.liveShow`
  case) always composes `date: location - venue (source)` and ignores `tags.album`.
  `ShowPlan` uses it for every track's `album` and `sortAlbum`. So for this show the Plan tab, and
  the tags it would write, read `Unknown Date: Unknown City - Unknown Venue (SBD)`.
- **The two titles disagree.** `SetlistText.composedAlbum` keeps an explicit `tags.album`
  verbatim, so the `setlist.txt` it writes would say the right thing while the files are tagged
  wrong.

## Changes

### One pure function recovers the fields

- In VinylFeverCore, add `ShowTags.fillingFieldsFromAlbum() -> ShowTags`. When `album` matches
  `YYYY-MM-DD: Location - Venue`, optionally followed by parenthetical groups, it sets each of
  `date`, `location`, and `venue` **that is `.unknown`** from the title. A field that already has a
  value is never changed. Anything that doesn't match returns the tags unchanged.
- **Parsing rules:**
  - The date is the first 10 characters and must pass `DateField(isoString:)`, followed by `: `.
  - Location runs to the **first** ` - ` after the date. Venue is the rest, so a venue name with a
    dash in it (`Sleeping Village - Back Room`) stays whole.
  - Strip trailing `(…)` groups from the venue before using it: the source and any qualifier, as
    in `Teatro Colosseo (1st Set) (SBD)` → `Teatro Colosseo`. A parenthetical inside the name
    that isn't at the end stays.
  - The placeholders `Unknown Date`, `Unknown City`, and `Unknown Venue` stay `.unknown`. An
    all-unknown title fills nothing.
  - An empty location or venue after trimming fills nothing for that field.
  - A `(Compilation)` title never matches.
- It doesn't touch `source`. The parser's `sourceToken(fromAlbum:)` keeps doing that.

### The parser calls it

- `SetlistParser.parse` calls `fillingFieldsFromAlbum()` on the tags **after** reading every
  line, so a `DATE:`, `VENUE:`, or `LOCATION:` line wins wherever it appears, even after `ALBUM:`.

### The editor calls it when Jon finishes typing the Album

- In `SetlistTagsEditor` (`LiveShowsView.swift`), when the Album field is submitted (Return) or
  loses focus, replace the tags with `tags.fillingFieldsFromAlbum()`. Use `@FocusState`.
- Not on every keystroke: a half-typed `2026-02-27: Chicago, IL - S` would match and lock the
  venue at `S`, since a filled field is never overwritten.

## Decisions

1. **The fields stay the truth; the album is derived from them.** The plan keeps composing its
   album from date, location, venue, and source, so the source picker still sets the suffix. The
   fix is to fill the fields, not to tag files with whatever the Album field says.
2. **Fill only what's unknown.** An explicit line or a value Jon typed always beats the title.
3. **First ` - ` splits location from venue.** City names rarely carry ` - `, and venue names
   sometimes do.

## Done when

- **Core tests** (`SetlistParserTests`, and a new `ShowTagsAlbumFieldsTests` or similar for the
  pure function):
  - `ALBUM: 2026-02-27: Chicago, IL - Sleeping Village` with no other tag lines gives date
    `2026-02-27`, location `Chicago, IL`, and venue `Sleeping Village`;
  - the same with `(SBD)` at the end gives the same three fields, and source `SBD` as today;
  - `… - Teatro Colosseo (1st Set) (SBD)` gives venue `Teatro Colosseo`;
  - `… - Sleeping Village - Back Room` gives venue `Sleeping Village - Back Room`;
  - an explicit `VENUE: The Metro` line, placed after the `ALBUM:` line, keeps venue `The Metro`
    and still fills date and location from the title;
  - `Unknown Date: Unknown City - Unknown Venue (unknown)` fills nothing;
  - `2026-13-40: Chicago, IL - Sleeping Village` fills nothing, because the date is invalid;
  - a `(Compilation)` title and a free-text title (`Dave Hause - Live from Chicago`) fill nothing.
- **Plan test** (`ShowPlanTests`): parsing the Dave Hause `ALBUM:` line with source SBD gives
  every track `album` `2026-02-27: Chicago, IL - Sleeping Village (SBD)`. That equals
  `SetlistText.composedAlbum` once its tags carry the same fields and no explicit album.
- **Golden corpus:** if `SetlistCorpusGoldenTests` output changes because a sample now fills
  fields, update the golden and list each changed sample in the PR.
- No test drives the editor's focus change. Name that in the PR.
- The full set in `docs/verification.md` passes.
- Closeout (ADR-0005 D16) records the gate below.

**The gate.** After the Mac install, open *Dave Hause - Live from Chicago 2026* in Live Shows and
parse its setlist:

1. Date, Venue, and Location show `2026-02-27`, `Sleeping Village`, and `Chicago, IL`.
2. The Plan tab's Album reads `2026-02-27: Chicago, IL - Sleeping Village (SBD)`.
3. Clear Venue, type a different venue into the Album field, and press Return. Venue fills from the
   new Album, and Date and Location don't change.

## Out of scope

- **Keeping a qualifier like `(1st Set)` in the plan's album.** The editor always builds
  `ShowMetadata` with `.liveShow()` and no qualifier, so the plan drops it today. That's a
  separate fix.
- **Reading fields out of a free-text title** such as `Dave Hause - Live from Chicago 2026`. That's
  the Normalizer's job.
