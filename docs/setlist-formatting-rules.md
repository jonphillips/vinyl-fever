# Setlist Formatting Rules

This document defines how Vinyl Fever should convert raw concert text files,
torrent notes, trading notes, bootleg metadata, and pasted show notes into the
standard `setlist.txt` format used by live-show processing.

The output must be plain, copyable, script-friendly text.

## Standard Output Shape

Every normal live-show setlist should use this structure:

```text
ARTIST: Artist Name
ALBUM: YYYY-MM-DD: City, ST/Province/Country - Venue (Source)
ALBUMARTIST: Album Artist
DATE: YYYY-MM-DD
VENUE: Venue Name
LOCATION: City, ST/Province/Country

Track Title
Track Title
Track Title
```

Rules:

- Tags come first.
- Use exactly one blank line between the final tag and the first track.
- Do not insert blank lines between tracks.
- Do not number tracks in the final output.
- Track lines should be a simple stacked list.
- Do not include disc headers, set headers, encore headers, separator lines,
  comments, lineage, notes, file hashes, shntool output, or other non-track
  metadata in the track list.

## Required Tags

For a normal live show, use:

```text
ARTIST:
ALBUM:
ALBUMARTIST:
DATE:
VENUE:
LOCATION:
```

If a field is unknown:

```text
DATE: Unknown Date
VENUE: Unknown Venue
LOCATION: Unknown Location
```

For the `ALBUM` tag, use:

```text
YYYY-MM-DD: City, ST/Province/Country - Venue (Source)
```

Examples:

```text
ALBUM: 1996-05-21: Northampton, MA - Pearl Street Grill (SBD)
ALBUM: 2009-10-17: Buenos Aires, Argentina - Personal Fest (FM)
ALBUM: Unknown Date: Unknown City - Unknown Venue (unknown)
```

If the show title is important, include it only when it functions as the release
title rather than trading-note decoration.

Example:

```text
ALBUM: Christmas & Fan Club Singles 1988-2011 (Compilation)
```

## Artist And Album Artist

`ARTIST` should reflect the credited live act when meaningful:

```text
ARTIST: John Hiatt & The Goners
ARTIST: Bruce Hornsby and The Range
ARTIST: Jackson Browne & David Lindley
ARTIST: Lyle Lovett & His Small Band
```

`ALBUMARTIST` should usually be the primary catalog artist:

```text
ALBUMARTIST: John Hiatt
ALBUMARTIST: Bruce Hornsby
ALBUMARTIST: Jackson Browne
ALBUMARTIST: Lyle Lovett
```

For bands whose artist identity is already canonical, `ARTIST` and
`ALBUMARTIST` can match:

```text
ARTIST: U2
ALBUMARTIST: U2
```

For special billing, preserve the live billing in `ARTIST` but keep the main
catalog artist in `ALBUMARTIST` when helpful.

Example:

```text
ARTIST: Bruce Springsteen with The Max Weinberg 7 and Friends
ALBUMARTIST: Bruce Springsteen
```

## Date Formatting

The `DATE` tag should always use ISO format:

```text
DATE: 1996-05-21
```

For track-level parenthetical source details in compilations, use readable dates:

```text
Nov. 14, 1971
Mar. 5, 1996
Oct. 25, 2002
```

Use these month abbreviations:

```text
Jan.
Feb.
Mar.
Apr.
May
Jun.
Jul.
Aug.
Sep.
Oct.
Nov.
Dec.
```

## Venue And Location

Use the best available venue and location from the notes.

Examples:

```text
VENUE: The Bottom Line
LOCATION: New York, NY
VENUE: Kulturbolaget
LOCATION: Malmö, Sweden
```

Normalize obvious city/state/country formatting:

- `NYC` -> `New York, NY`
- `N.Y.C.` -> `New York, NY`
- `Va` -> `VA`
- `Holland` may be normalized to `Netherlands`
- Keep non-U.S. city/country as `City, Country` unless a province/state is useful.

## Source In Album Title

Always try to infer the source and include it in parentheses at the end of the
`ALBUM` tag.

Common source labels:

```text
(SBD)
(D-SBD)
(DSBD)
(AUD)
(FM)
(ALD)
(SBD/ALD)
(SBD/AUD)
(Matrix)
(IEM/AUD Matrix)
(Broadcast DAT Clone)
(Radio Broadcast)
(TV/FM Broadcast)
(Pre-FM)
(Ultramatrix SBD)
```

Guidelines:

- `Soundboard`, `SBD`, `sb`, `digital soundboard` -> `(SBD)`
- `D-sbd`, when explicitly styled that way -> `(D-SBD)`
- `DSBD` -> `(DSBD)`
- Audience mic lineage, taper mics, or "excellent audience recording" -> `(AUD)`
- FM broadcast or radio broadcast -> `(FM)`, or `(Radio Broadcast)` if that
  wording matters
- Assistive listening device -> `(ALD)`
- Multiple sources mixed together -> `(Matrix)`
- Soundboard plus audience or ALD uncertainty -> `(SBD/ALD)` or `(SBD/AUD)`
- Unknown source -> `(unknown)`

Do not invent a source beyond what can reasonably be inferred from the notes. If
uncertain, use a conservative combined source or `(unknown)`.

## Track List Extraction

The track list should contain only actual tracks.

Include numbered items even if they are non-song tracks:

```text
intro
talk
banter
band intros
radio intro
radio outro
encore break
stage entrance
tuning, announcements
```

Do not include unnumbered structural labels such as:

```text
Disc One
Disc Two
Set 1
Set 2
Encore
Encore 2
END OF PART 1
END OF PART 2
```

Exception: if `Encore` or `Encore Break` is explicitly numbered as a track,
include it as a track.

Example final track sequence:

```text
encore
Band Intros
Thing Called Love
```

## Numbered Track Rule

If tracks are numbered in the source, each numbered line is a track.

This rule overrides musical segue notation.

Example source:

```text
12. Mandolin Rain > Brokedown Palace
```

Final track:

```text
Mandolin Rain > Brokedown Palace
```

Do not split it into two tracks.

Example source:

```text
01 On the Western Skyline >
02 Not Fade Away
```

Final tracks:

```text
On the Western Skyline >
Not Fade Away
```

Do not join them just because the first line has `>`.

## Segue Notation

Preserve segue notation when present.

Preferred normalized forms:

```text
Song Title >
Song Title > Another Song
Song Title / Other Song
```

Use `>` for continuous segues when supplied by the source.

Use `/` when the source uses slash medleys or title combinations.

Do not split or join tracks unless the source track numbering or formatting
clearly supports doing so.

## Track Title Cleanup

Clean obvious encoding errors and normalize typography lightly.

Examples:

- `We¥ll` -> `We'll`
- `Donít` -> `Don't`
- `Iím` -> `I'm`
- `Canít` -> `Can't`
- `Malmˆ` -> `Malmö`
- `D¸sseldorf` -> `Düsseldorf`

Fix obvious spelling errors when the intended song is clear:

- `Every Lttle Kiss` -> `Every Little Kiss`
- `Loosing` in `Can't Stand Loosing You` -> `Losing`
- `Phildelphia` -> `Philadelphia`

Use consistent capitalization, but do not over-polish into a different catalog
style if the source is specific.

Generally acceptable title style:

```text
The Way It Is
Every Little Kiss
Night on the Town
Have a Little Faith in Me
```

For short non-song tracks, use lowercase unless they are formal titles:

```text
intro
radio intro
talk
banter
band intro
band intros
tuning, announcements
```

## Parenthetical Track Notes

Use parentheses for important track-specific notes that should survive into the
music library.

Examples:

```text
For Her Love (cuts in)
Ball of Kerrymuir (ending cut)
Radio Free Europe (fades out)
Catapult (live debut)
Rainbow's Cadillac > Franklin's Tower (Bruce on accordion)
This Old Porch (with Robert Earl Keen Jr.)
Angel from Montgomery (with Bonnie Raitt)
Paradise (AUD filler; date/location unknown)
```

Include notes for:

- Guest performers.
- Alternate/acoustic/band versions.
- Cuts/fades/incomplete tracks.
- Live debuts.
- Bonus/filler sources.
- Unusually important source details.
- "With" performer notes from footnotes.

Do not include excessive technical notes inside track titles unless they are
musically useful.

## Guest And Footnote Handling

When the source uses footnote symbols such as `*`, `#`, or `^`, convert them into
parenthetical track notes.

Example source:

```text
Night on the Town*
Passing Through*
Defenders of the Flag*
* = with Jimmy Herring
```

Final:

```text
Night on the Town (with Jimmy Herring)
Passing Through (with Jimmy Herring)
Defenders of the Flag (with Jimmy Herring)
```

For multiple footnotes, combine them cleanly:

```text
Cruise Control > (with Jimmy Herring; John Molo)
```

If the note is about who sang a section or whether Sting, Paul Simon, or both
performed it, treat that information like a footnote and include it
parenthetically.

Examples:

```text
The Boxer (Paul Simon)
Every Breath You Take (Sting)
Bridge Over Troubled Water (Sting and Paul Simon)
```

## Covers And Songwriter Notes

If the source identifies covers, include the cover note only when it is useful and
concise.

Examples:

```text
Little Sister (Elvis Presley)
Feels Like Home (Randy Newman cover)
Hot Burrito #1 (Gram Parsons cover)
Jesus Christ (Alex Chilton cover)
```

If cover notes are excessive or repetitive, prefer the clean song title unless
the compilation's purpose depends on identifying covers.

## Missing Tracks

If a source lists missing songs separately as `xx`, include them only when the
user likely wants the setlist to reflect the complete known show.

Example:

```text
Look Out Any Window (missing)
I Will Walk With You (missing)
The Long Race (missing)
```

Do not include random "missing" notes from historical commentary unless they
correspond to known tracks in the set.

## Incomplete Shows And Partial Sources

If the show is explicitly partial or only one set, include that in the `ALBUM`
title when important.

Examples:

```text
ALBUM: 1997-04-08: Torino, Italy - Teatro Colosseo (1st Set) (SBD)
ALBUM: 1990-12-16: Ventura, CA - Ventura Theatre (Early Show) (SBD)
```

Track-level cuts should be noted parenthetically:

```text
Farther On (cuts in near beginning)
Linda Paloma (cuts in near beginning)
```

## Compilations

For compilations, do not force live-show metadata.

Use a compilation-style album title:

```text
ARTIST: R.E.M.
ALBUM: Christmas & Fan Club Singles 1988-2011 (Compilation)
ALBUMARTIST: R.E.M.
```

No `DATE`, `VENUE`, or `LOCATION` is required unless the compilation itself has a
meaningful date/location.

For multi-source live compilations, include track-specific parenthetical source
details.

Example:

```text
Badlands (Rome, Jul. 19, 2009)
Outlaw Pete (Stockholm, Jun. 7, 2009; JW)
Thunder Road (Landgraff, May 30, 2009; with Brandon Flowers)
```

Avoid blank lines between discs even for very large compilations.

## Revisiting The Albums Live Series

For Jackson Browne's "Revisiting the Albums Live" series, use this album format:

```text
ALBUM: Revisiting the Albums Live, Vol N: Album Title
```

Examples:

```text
ALBUM: Revisiting the Albums Live, Vol 1: Jackson Browne
ALBUM: Revisiting the Albums Live, Vol 5: Running on Empty
ALBUM: Revisiting the Albums Live, Vol 12: The Naked Ride Home
```

Track lines should include the location/date source in parentheses.

Example:

```text
Gene Shay Album Interview (WMMR Philadelphia, Nov. 14, 1971)
A Child in These Hills (New Orleans, Mar. 2, 1975)
Intro to Jamaica Say You Will (Bryn Mawr, Aug. 15, 1973)
```

For these compilations:

- Do not number tracks.
- Use parenthetical source details.
- Use readable dates, not ISO dates, inside track names.
- Keep `Intro to...`, `Commentary`, `Album Intro`, `Final comments`, and similar
  spoken segments as tracks.
- Use `silence` if it is explicitly listed as a track.

## Album Title Examples

Normal live show:

```text
ALBUM: 1996-05-19: Philadelphia, PA - Electric Factory (SBD)
```

Festival or event:

```text
ALBUM: 1992-07-04: Austin, TX - Zilker Park (Freedom Fest) (AUD)
```

Uncertain source:

```text
ALBUM: 1991-03-03: Geneva, NY - Smith Opera House (unknown)
```

Special source:

```text
ALBUM: 1993-08-28: Dublin, Ireland - RDS Stadium (Broadcast DAT Clone)
```

Compilation:

```text
ALBUM: Ceoil Deas: Working on a Wrecking Ball (Compilation)
```

Studio/outtakes:

```text
ALBUM: Tape Deck Blastin' (Studio)
```

## Do Not Include

Do not include the following in the final setlist output:

- Lineage.
- Transfer notes.
- Taper notes.
- MD5/FFP fingerprints.
- Shntool output.
- Artwork notes.
- "Do not sell" statements.
- Long review text.
- Technical mastering notes.
- Disc total times.
- File sizes.
- URLs.
- Band personnel unless the user specifically asks for personnel.
- Unnumbered set/disc/encore headers.

## Preservation Bias

When in doubt, preserve useful musical information but remove trading noise.

Preserve:

- Exact show date.
- Venue.
- City/location.
- Source type.
- Track order.
- Numbered non-song tracks.
- Guest performers.
- Track-level cuts/fades.
- Alternate/filler/source notes when musically relevant.

Remove:

- Redundant explanations.
- General comments.
- Repeated source paragraphs.
- Hash blocks.
- Tracker chatter.
- CD burning suggestions.
- Disc/set separators.
- Unnumbered encore labels.

## Core Decision Rules

1. Tags first.
2. One blank line after tags.
3. No blank lines in the track list.
4. No track numbers.
5. If a source track is numbered, preserve it as one track.
6. Do not split a numbered track because of `>`.
7. Do not join separately numbered tracks because of `>`.
8. Include source in the `ALBUM` title.
9. Infer `SBD`, `AUD`, `FM`, `ALD`, `Matrix`, and similar source labels carefully.
10. Convert footnotes into concise parenthetical notes.
11. Include numbered intros, talk, banter, and encore breaks as tracks.
12. Exclude unnumbered structural labels.
13. Use parenthetical details for compilations and bonus/filler tracks.
14. Keep the output plain, copyable, and script-friendly.

## Automation Implications

This document answers part of the live-show reassessment: the app needs a
Setlist Parser/Normalizer that can turn noisy input into a previewable
`setlist.txt`.

### Two artifacts, not one

There are two distinct text shapes, and they must not be conflated:

1. **Raw trading notes** — pasted text, `.txt` files, torrent/bootleg metadata.
   Free-form and wildly inconsistent. This is the *input*.
2. **The normalized `setlist.txt`** — the tagged shape at the top of this
   document. This is the *output*.

The existing `SetlistParser` in `VinylFeverCore` parses shape 2 (it looks for
`ARTIST:`/`ALBUM:` tags and `NN. Title` lines). Run against raw notes it does not
merely under-perform — it emits garbage, treating headers, `Source:` lines, time
totals, and note paragraphs as tracks. The hard, mostly-unbuilt problem is the
transform **raw notes → normalized setlist.txt**. That transform is the
Normalizer this section specifies.

### Resolved design: the normalizer sandwich

Reviewed against a corpus of 18 real raw setlists (2026-07-03). The corpus made
plain that even "find the actual track list" is a semantic judgment (e.g. a
setlist with no track numbers at all; a file carrying both a media track list and
a prose "complete set" that includes songs not on the recording; a single segue
jam spanning three lines; the same `(*)` glyph meaning "processed in Cool Edit"
in one file and "guest performer" in another). Deterministic parsing therefore
cannot *lead*. But it earns its place as two bookends around the model:

```text
raw .txt
   -> [1] Deterministic pre-segment  => cleaned text + region hints
   -> [2] LLM normalize (frontier)   => structured JSON (see contract)
   -> [3] Deterministic validate     => pass | fail(reasons)
   -> [4] Human preview (ALWAYS)      => approve => write setlist.txt
```

**[1] Pre-segment — hints, never decisions.** Normalize CRLF/BOM/stray
whitespace; excise FFP/MD5/shntool hash blocks (mechanical and token-heavy);
label candidate regions (`header` | `tracklist` | `lineage` | `prose`) to hand
the model structure. It annotates; it never decides what is or isn't a track.

**[2] LLM normalize.** The model reads the cleaned text, the region hints, this
rules document, and the controlled source vocabulary, and does all interpretation:
inferring source from prose, attaching footnotes to the right tracks,
distinguishing musical detail from trading noise, fixing spelling when the
intended song is clear. It emits **structured JSON, not finished text**, so the
validator can inspect fields and only step [3]/[4] renders `setlist.txt`.

The call goes through **`LLMClientKit`** — the shared, app-agnostic model boundary
in the `jon-platform` monorepo (`packages/LLMClientKit`), first proven as
Galavant's `GalavantAI` and now also used by Yes Chef. `VinylFeverCore` consumes
it as a path dependency, `.package(path: "../../jon-platform/packages/LLMClientKit")`,
and reads `@Dependency(\.modelClient)`. Vinyl Fever requests the
`.frontier(.anthropic)` tier (per the BYO-key decision below); the boundary
degrades to on-device automatically when no key is configured, so the Normalizer
never branches on key presence.

**Template — mirror `HoursExtractor`.** Galavant's `HoursExtractor`
(`GalavantLibrary/Sources/GalavantPlaces/HoursExtractor.swift`) is the same shape
as this task — pull structured data out of messy free text, *"always extraction,
never invention"* — and is the house pattern to copy: a `Sendable` struct with a
`DependencyKey`; `liveValue` builds a `ModelRequest(system: instructions, prompt:
…)`, calls `modelClient.complete`, and **defensively parses the JSON out of
`response.text`** (slice the outer `{…}`; malformed output degrades to a
low-confidence draft, never a crash); `testValue` returns nothing so the
deterministic path stays the tested default and unit tests use
`StubModelClient`.

Two structured-output strategies, in order of preference:

- **Prompt-and-parse (start here).** Ask for JSON in the system prompt and parse
  `response.text`, exactly as `HoursExtractor` does. Proven, matches the house
  style, trivially testable with `StubModelClient`.
- **Forced tool-use (promote if needed).** `LLMClientKit` already supports
  `ModelTool`/`ModelToolCall`, but no consumer yet uses tools for *structured
  output* (the existing extractors run on-device, where tools are ignored). Our
  contract is nested (`tracks[]`, `dropped[]`) and frontier-only — exactly where a
  forced tool whose `inputSchema` *is* the contract earns its keep. If
  prompt-and-parse proves unreliable on the nested arrays, promote to a tool. That
  promotion is also the right moment to lift a shared structured-output/JSON helper
  into `LLMClientKit` — by then `HoursExtractor`, `EvaluationExtractor`, and this
  Normalizer are three hand-rolled parsers (rule of three), and none of that
  library work blocks shipping the Normalizer first.

**[3] Validate — the guardrails.** Required tags present; `ALBUM` shape; `DATE`
is a real ISO date; `source` drawn only from the controlled vocabulary and never
invented (checked by confirming `sourceEvidence` actually appears in the input);
no `|` inside a Grouping token; track count sane versus the source. A failure
does not auto-fix — it marks the draft low-confidence and forces review.

**[4] Preview.** Every file is previewed before any file/tag change. No
auto-write, even on high confidence. This is a dogfooding tool; trust comes from
seeing what was dropped.

### LLM output contract

The model returns structured JSON so guardrails are checkable and the dropped
material is auditable:

```json
{
  "tags": { "artist": "...", "albumArtist": "...", "date": "1997-07-19",
            "venue": "...", "location": "...", "source": "SBD" },
  "tracks": [ { "title": "Slow Turning", "note": null, "confidence": "high" } ],
  "sourceEvidence": "quoted lineage line the source label was inferred from",
  "confidence": "high | low",
  "dropped": [ "lines the model discarded, for audit" ]
}
```

`sourceEvidence` makes "no invented source" verifiable — the quoted string must
appear in the input. `dropped` makes the preview auditable. Implementing this
contract implies two small model changes in `VinylFeverCore`: `ShowTags` needs an
explicit `source` field (today it is only implied inside `ALBUM`), and
`SetlistTrack` needs an optional `note`.

### Source of truth: the media, not the show

A setlist reflects **what is physically on the recording**, not a reconstructed
complete performance. This resolves the corpus's ugliest ambiguities into a rule
the model can follow and the validator can trust: use the structured
numbered/disc list; treat prose re-lists and "complete set" paragraphs as noise;
drop separately listed "not recorded" songs. When a release physically contains
two sub-sets (e.g. an early and a late show, or a main set plus a later radio
session), both are on the media and both are kept.

### Resolved decisions (2026-07-03 review)

- **Architecture:** the sandwich above (deterministic pre-segment -> LLM ->
  deterministic validate -> preview).
- **Model tier:** any configured frontier provider, resolved via 
  FrontierResolver (.frontierPreferred); degrades to on-device only with no key at all. 
  The prose-inference, dirty-OCR, and multi-line-jam cases lean on reasoning quality 
  the on-device tier cannot yet be assumed to reach. Resolves the tier question in 
  `open-questions.md` toward BYO-required for this feature.
- **Key storage:** reuse `LLMClientKit`'s `APIKeyStore` (`@Dependency(\.apiKeyStore)`)
  — one iCloud-Keychain-synced slot per provider under a shared service
  (`com.jonphillips.llmclientkit.apikeys`). A Claude key entered in Galavant or Yes
  Chef is therefore *already* available to Vinyl Fever (enter once, all apps use
  it). The library ships the store and a `masked()` preview but not the entry
  screen; a small per-app settings screen bound to `apiKeyStore` is the only
  net-new UI, and only needed if the user wants to enter the key inside Vinyl Fever
  rather than rely on the synced one.
- **Review gate:** always preview before write.
- **Source of truth:** what's on the media (above).
- **Independence:** this Normalizer is pure text-in / JSON-out in
  `VinylFeverCore` via `ModelClient`. It does **not** depend on macOS 27 or the
  Music.app import/verify surface, so it is buildable and dogfoodable now,
  independent of the M3 beta-3 pause, with a golden-file test per corpus file.

### Deferred (not blockers)

- **Embedded per-file instructions.** One corpus file contained an instruction
  addressed to the formatter ("format these like ..."). For a personal tool
  operating on the user's own notes, the lean is to *honor* such instructions,
  gated behind the same mandatory preview. It is also the prompt-injection
  surface; decide deliberately when first encountered.
- **Impossible/typo dates** (e.g. a month of `22`): the validator flags them to
  low-confidence review rather than guessing a correction.
