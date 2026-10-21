# Milestone 15 — Artist Identity (one artist key, everywhere)

*Give every artist comparison in Vinyl Fever one shared rule, so a play, an upload, a library
copy, and a catalog song by the same artist all match. S0 runs between M13 S2 and M14 S1, and
S1 between M14 S1 and M13 S3; see Decision 5. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: artist matching keeps getting fixed one slice at a time. `check_tracks`, the listening
log, and the catalog scorer compare artists exactly, while M14's upload routing uses a
whole-word prefix that also matches "Elvis" to "Elvis Costello". A probe of Jon's 87,115-track
library found three kinds of mismatch: band and live suffixes, spelling noise, and true aliases
(John Cougar / John Mellencamp). S0 adds one `ArtistIdentity` that removes the first two by rule
and handles duets, and every artist comparison switches to it. S1 adds a short alias list that
Jon approves in Settings, seeded by a candidate finder. Two slices in two dispatches. S1 adds
one table.

## The milestone in one sentence

"John Cougar / Ain't Even Done With the Night" is in Jon's library, "Paul Simon & Sting" counts
as a Sting show, and "The Eagles" and "Eagles" are one artist, on every surface that compares
artists.

## Why this keeps coming back

Each slice picked the rule its own bug needed:

| Where | Rule today | Since |
| --- | --- | --- |
| `check_tracks`, `annotation`, `artist_profile`, overview counts | exact `SongTextNormalizer.artist` | M12 |
| Catalog scorer (M11 resolve) | exact | M11 |
| Listening log: `top_artists`, track key, overlap collapse | exact (`ListeningTextNormalizer`) | M13 S0 |
| Upload routing, the upload picker, `uploadedAlbums` | whole-word prefix (`LibraryUploadMatcher.artistsMatch`) | M14 S0, Decision 5 |

None of these rules handles all three kinds of mismatch, and the prefix rule has false
positives. The fix is one rule that every comparison uses, so the next variant is either a
cleanup rule or an alias, not a new rule for that slice.

## Evidence (probe, 2026-10-20)

A Python model of the rules below, run over Jon's real snapshot (87,115 tracks, 8,309 artist
keys under today's normalizer). The probe scripts aren't in the repo. S0's tests encode the
cases.

- **Band and live suffixes are most of the volume.** Layers 1–2 (below) merge 293 keys covering
  34,909 tracks into 7,992 keys. The largest merges:
  - `bruce springsteen`: `… and the e street band` (7,565), plain (3,581), `… live` (2,796),
    `… and the e street band live` (1,698), `… and the max weinberg 7 live` (39);
  - `bruce hornsby`: plain, `… and the noisemakers`, `… and the range`, `… solo`,
    `… and his band`;
  - `tom petty and the heartbreakers` / `tom petty`, `prince and the revolution` / `prince`,
    `lyle lovett and his large band` / `lyle lovett`, `jason isbell and the 400 unit` /
    `jason isbell`, `bob dylan and the band` / `bob dylan`;
  - about 150 "The" pairs: `the beatles` / `beatles`, `the clash` (91) / `clash` (25),
    `ramones` (32) / `the ramones` (28), `cure the` / `the cure`, and so on.
- **The prefix rule is wrong in both directions.**
  - False positives: `elvis` (a 24-track Presley set) matches `elvis costello` and
    `elvis costello and the attractions` (108 uploads), and `moby` matches `moby grape`.
  - It also credits a duet to its first-named artist only. `paul simon and sting` (68 uploads)
    matches Paul Simon but not Sting.
  - Of the 54,166 uploads, 1,108 match under the prefix rule but not under layers 1–2. They're
    those false positives plus duets and joint shows, which the credits rule below covers.
- **Duets need a credits rule, and a naive one is wrong.** Splitting `X and Y` and crediting any
  part that's a known artist covers `john hiatt and lyle lovett`, `paul simon and sting`, and
  `neil young and crazy horse`. It also credits band names: `love and rockets` → Love,
  `hue and cry` → Cry, `of monsters and men` → Men, `bruce hornsby and band` → The Band. The
  tightened rule (below) credits 1,334 tracks and none of those.
- **True aliases need a list.** After layers 1–2, a title-overlap finder (two artist keys sharing
  4 or more titles, which is at least half of the smaller artist's titles) leaves **44
  candidates**. Roughly half are real:
  - **Likely the same artist (22):**
    - `john cougar mellencamp` / `john mellencamp`;
    - `elvis` / `elvis presley`;
    - `janet` / `janet jackson`;
    - `liz phair` / `phair liz`, `elton john` / `john elton`, `dennis deyoung` /
      `young dennis de`;
    - `mister reality` / `mr reality`, `danger mouse` / `dj danger mouse`;
    - `on a friday` / `radiohead`;
    - `nils lofgren` / `nils lofgren band`, `matthew good` / `matthew good band`,
      `jackson browne` / `jackson browne acoustic trio`, `bruce hornsby` /
      `bruce hornsby and band`;
    - `jimi hendrix` / `jimi hendrix experience`, `john lennon` /
      `john lennonplastic ono band`;
    - `finn brothers` / `finn brothers neil finn and tim finn`, `louvin brothers` /
      `ira and charlie louvin`;
    - `kimball and jamison` / `jimi jamison and bobby kimball`, `loggins and messina` /
      `kenny loggins and jim messina`;
    - `stan getz and joao gilberto` / `joao gilberto stan getz`, `gerry mulligan and chet
      baker` / `gerry mulligan quartet and chet baker`;
    - `anthology volume one cowboy man` / `lyle lovett` (probably an album name in the artist field).
  - **Jon's call (8):**
    - `buddy holly` / `crickets`;
    - `big boi` / `outkast`;
    - `mavericks` / `mavericks and raul malo`;
    - `dave matthews` / `dave matthews band` / `dave matthews and tim reynolds`;
    - `jason isbell` / `jason isbell and amanda shires`;
    - `richard thompson` / `richard thompson and danny thompson`.
  - **Not aliases (14):**
    - covers and tributes: `martyn joseph` ~ Springsteen, `venus in furs` ~ Radiohead,
      `her mystery not of high heels` ~ Jonathan Richman;
    - producer credits: `phil spector` ~ the Crystals, Darlene Love, the Ronettes, the
      Righteous Brothers;
    - cast recordings and `various`: Alan Menken, Meredith Willson, Robert Preston, Shirley
      Jones, the Carter Family, a cast recording ~ Paul Simon, Trey Parker;
    - `big daddy` ~ Chris Rock.
  - **Corrected 2026-10-20 in the #101 review.** The Swift finder, run on the real snapshot
    with the S1 rules applied as written, finds **34** overlap candidates, not 44. The
    difference is in two pairs above:
    - `john cougar mellencamp` / `john mellencamp` share only 2 counted titles;
    - `on a friday` / `radiohead` share 3.

    The structural shape added to S1, one inner word inserted, finds the Mellencamp pair. No
    rule finds `on a friday`, or `john cougar` (4 remixes, no titles shared with Mellencamp).
    That gap is an open question: a manual Add alias in the sheet.
- **Two false merges in layer 2, accepted:** `martha and the vandellas` / `martha and the
  muffins` (5 tracks) and `eddie and the hot rods` / `eddie and the tide` (4 tracks). Neither
  pair shares a title, so neither merge changes a match. Grouping counts move by a handful.

## The rule

`ArtistIdentity` lives in `VinylFeverListening`, beside `ListeningTextNormalizer`, which
`SongTextNormalizer` already wraps. That's the lowest package, so the macOS 15 poller, the log
reader, and Core all share it.

```swift
public struct ArtistIdentity: Sendable {
  public static let empty: ArtistIdentity                    // layers 1–2 only, no aliases
  public init(aliases: [String: String], knownArtists: Set<String>)
  public static func baseKey(_ raw: String) -> String        // layers 1–2
  public func key(_ raw: String) -> String                   // + layer 3 (aliases)
  public func credits(_ raw: String) -> Set<String>          // key + credited collaborators
  public func matches(request: String, track: String) -> Bool  // credits(track).contains(key(request))
}
```

- **Layer 1, cleanup** (on today's `ListeningTextNormalizer.artist`, which already folds case
  and accents, turns `&` into `and`, and drops `feat.` credits):
  - Apostrophes (`'`, `’`, `‘`, `ʻ`, `` ` ``, `´`) are deleted before punctuation becomes a
    space, so `O'Neal` = `ONeal` and `Kealiʻi` = `Kealii`. `+` becomes `and`.
  - A leading `the ` and a trailing ` the` are dropped, unless that would leave nothing
    (`the the` → `the`).
- **Layer 2, band and live suffixes:** a trailing ` live` or ` solo` is dropped, and so is
  everything from ` and the `, ` and his `, or ` and her `. Repeat until nothing changes.
- **Layer 3, aliases:** `key` maps a `baseKey` through Jon's accepted aliases (S1). Each map is
  one hop: the target is never itself a variant.
- **Credits (matching only, never grouping):** credits come from the raw name, not the key.
  The key has already lost its commas, so it can't be split on them (corrected 2026-10-20 in
  the #95 review; S0 is built this way).
  - **The band-suffix guard comes first.** It checks the normalized name, after `&` and `+`
    become `and`. If that name contains ` and the `, ` and his `, or ` and her `, the artist
    credits only its own key. So `Judah & The Lion` never credits Lion.
  - Otherwise the raw name is split on ` and ` (including `&` and `+`), `, `, ` x `, and
    ` vs `, and each part is reduced to its `key`.

  A part is credited when all of these hold:
  - it's in `knownArtists` (some library track's `key` equals it);
  - it isn't `band`, `friends`, `others`, `family`, `orchestra`, or `guests`;
  - it has two or more words, **or** every part of the name is a known artist.

  So `paul simon and sting` credits Paul Simon and Sting, `zapp and roger` credits both, and
  `love and rockets` credits nobody else.
- **Grouping uses `key`. Matching a request against a track uses `matches`.** A duet stays its
  own artist in `top_artists`, while a request for Sting finds the Simon & Sting show.

**Rejected rules:**
- Flipping `Last, First`: it would split `Earth, Wind & Fire` from `Earth Wind & Fire`. The
  three reversals in Jon's library are alias candidates instead.
- Stripping ` band`, ` trio`, or ` experience`: `Dave Matthews Band` isn't Dave Matthews solo for
  everyone. The finder proposes those as candidates.

## Slices

**Dispatch 1: S0** (Core, pure; no device gate). **Dispatch 2: S1** (core + app; one table; a
device gate).

- [x] **S0 — `ArtistIdentity`, adopted everywhere (Core).**
  - Add `ArtistIdentity` to `VinylFeverListening` as specified above, with `.empty` and
    `knownArtists` taken from the library.
  - **`LibraryIndex`** builds its identity from the snapshot: `knownArtists` is the set of
    every track's `key` (in S0, its `baseKey`, since there are no aliases yet). It switches
    every artist comparison:
    - `bySong` indexes each track under every key it credits, so `check_tracks` and
      `annotation` match through `matches`;
    - `artistProfile` keeps tracks whose artist or album artist credits the requested key;
    - `artistGroups`, the overview's artist count, and its album key group by `key`;
    - upload routing and `uploadedCandidates` use `matches`.
  - **`LibraryUploadMatcher.artistsMatch` is deleted.** Its callers use the index's identity.
    This supersedes M14 Decision 5.
  - **`CatalogMatchScorer`** compares the request's `key` with each candidate through
    `matches`, so "The Eagles" scores as an artist match on catalog "Eagles".
  - **`ListeningLog`** takes an `ArtistIdentity` (default `.empty`). `topArtists` groups by
    `key`, and the track key and overlap collapse use `key` + `libraryTitle`. `vf-mcp` passes the
    index's identity when a snapshot exists, and `.empty` when it doesn't.
  - `ListeningTrackKeyTests`, which pins the listening key to the library key, pins the new
    key.

  **DoD:**
  - `ArtistIdentity` tests from the evidence above. `key` equal:
    - `Bruce Springsteen & The E Street Band (Live)` = `Bruce Springsteen`;
    - `Bruce Hornsby and the Range` = `Bruce Hornsby Solo` = `Bruce Hornsby`;
    - `Lyle Lovett and His Large Band` = `Lyle Lovett`;
    - `The Eagles` = `Eagles`, `Cure, The` = `The Cure`;
    - `Patrice O'Neal` = `Patrice ONeal`, `Kealiʻi Reichel` = `Kealii Reichel`;
    - `Elvis Costello & The Attractions` = `Elvis Costello`;
    - `Earth, Wind & Fire` = `Earth Wind & Fire`.
  - `key` different:
    - `Elvis` ≠ `Elvis Costello`, and `Moby` ≠ `Moby Grape`;
    - `Simon & Garfunkel` stays `simon and garfunkel`;
    - `The The` → `the`.
  - `credits`, with both parts known:
    - `Paul Simon & Sting` credits `paul simon` and `sting`;
    - `Zapp & Roger` credits both.
  - `credits` that must not happen, even with `love`, `cry`, `men`, and `band` known:
    - `Love and Rockets` credits only itself, and so does `Hue and Cry`;
    - `Of Monsters and Men` doesn't credit `men`;
    - `Bruce Hornsby & Band` credits `bruce hornsby` but not `band`.
  - Index tests:
    - `check_tracks` for `Sting` / a title on a `Paul Simon & Sting` upload is `owned`;
    - `The Eagles` / `Hotel California` is `owned` against an `Eagles` track;
    - routing: `Elvis Costello` / `Alison` with an `Elvis`-tagged upload of that title doesn't
      route;
    - M14 S0's router and matcher tests still pass, including
      `Bruce Springsteen & The E Street Band (Live)`.
  - Log tests: `top_artists` for a period groups `Bruce Springsteen (Live)` with
    `Bruce Springsteen`, and a duet stays its own row.
  - Scorer test: `The Eagles` / `Hotel California` picks the catalog `Eagles` song.
  - **Load test:** `LibraryIndex` built from an 87,000-track fixture with realistic artist
    diversity (at least 8,000 distinct artists, a third with suffix variants) finishes within
    1.25× of today's build time on the same fixture. The PR states both times.

- [ ] **S1 — Artist aliases Jon approves (core + app; one table).** Device gate owed.
  - **Candidate finder (Core, pure, over `LibraryIndex`).** It returns pairs of `baseKey`s
    with their most common display spelling, track counts, and up to 3 shared titles as
    evidence. It reads only each track's artist and title, so it takes the snapshot's tracks
    and doesn't need a built index. It has two sources:
    - **Title overlap:** two keys share at least 4 distinct normalized titles (4 or more
      characters), and that's at least half of the smaller key's titles. Each key's title set
      holds only titles that at most 5 keys share, so both counts leave out the standards.
    - **Structure** (J is a known key; K is the candidate):
      - **suffix:** K is J plus `band`, `trio`, `quartet`, `experience`, or `acoustic trio`;
      - **reordered:** K's words are J's words in another order;
      - **joined:** the join falls inside a word. J has 2 or more words and its last word is at
        least 3 characters. K's words, up to some word W, are J's words, and W is J's last word
        plus at least 4 more characters (`john lennon` → `john lennonplastic ono band`).
        A whole-word prefix never qualifies: `elvis` / `elvis costello` is the M14 false
        positive this milestone removes;
      - **inserted (added 2026-10-20, #101 review):** J has 2 or more words, and K is J with
        exactly one word inserted between J's first and last words (`john mellencamp` →
        `john cougar mellencamp`, `daryl hall john oates` → `daryl hall and john oates`).

    The finder drops `various`, `various artists`, `soundtrack`, `cast recording`, and
    `original cast recording` before either source runs. It proposes the key with more tracks
    as canonical, and pairs Jon has decided never come back.
  - **Table `artistAliases`** (SQLiteData, new migration; schema amended in the #101 review
    and approved by Jon on 2026-10-20): `variant TEXT NOT NULL`, `canonical TEXT NOT NULL`,
    `decision TEXT NOT NULL` (`accepted` | `rejected`), `decidedAt`,
    `PRIMARY KEY (variant, canonical)`, plus a unique index on `variant` where
    `decision = 'accepted'`. A variant can have many rejections but only one alias. It isn't
    synced.
    - A rejection inserts its pair and changes no other row.
    - Accepting first removes any row for the same pair (in either direction) and any other
      accepted row for the variant.
    - No chains: accepting A → B while B → C exists stores A → C.
    - Accepting B → C re-points every A → B to A → C, replacing a rejected (A, C) row.
    - An alias to itself is refused.
  - **Export for `vf-mcp`.** On every decision and every snapshot refresh, the app writes
    `artist-aliases.json` atomically beside the snapshot:
    `{"format":"vf-artist-aliases","version":1,"aliases":{"john cougar mellencamp":"john mellencamp",…}}`.
    `LibraryMCPContext` reads it with the snapshot and reloads it when its `modifiedAt` changes.
    A missing file means no aliases, and a newer `version` is a typed error, like the snapshot.
  - **Settings → Library → Artist Aliases…** opens a sheet (an `@Observable`
    `ArtistAliasesModel`):
    - pending candidates, largest first, each showing both spellings, their track counts, and
      the shared titles;
    - **Same artist** (with a swap for which name is canonical) and **Different** buttons;
    - accepted aliases, each with **Undo**.

    It finds candidates off the main actor, once per open or Refresh. A decision or an undo
    re-reads only the decision rows and refilters the cached candidates.
  - The app's own index (preview badges, the picker) uses the accepted aliases too.

  **DoD:**
  - Finder tests:
    - an overlap pair; each of the four structural shapes; the exclusions; the proposed
      direction; decided pairs stay hidden;
    - not candidates: `elvis` / `elvis costello`, `moby` / `moby grape`, `billy joel` /
      `billy joe`, a pair whose shared titles are all held by more than 5 keys, and `various`
      sharing rare titles with an artist.
  - Finder load test on the 87,000-track, 8,000-artist fixture; the PR states the time.
  - Store tests:
    - chain collapse on accept and on re-point; a self-alias is refused; undo removes the row
      and the candidate returns;
    - accepting `elvis` → `elvis presley` and then rejecting (`elvis`, `elvis costello`) keeps
      both rows and the alias;
    - two rejections for one variant both stay hidden.
  - Export: codec round trip; a newer version errors; the file is rewritten on decide, and
    from the database on a snapshot refresh.
  - `vf-mcp` tests with an alias file:
    - `check_tracks` `John Cougar Mellencamp` / `Ain't Even Done With the Night` is `owned`
      against a `John Mellencamp` track;
    - `top_artists` (`all_time`) shows `elvis` and `elvis presley` as one row;
    - with no file, nothing changes.
  - Model tests for the sheet: decide, swap, undo; a decision doesn't re-read the snapshot.
  - The PR is a schema change, so it escalates to Jon (ADR-0005 D9).
  - **Device gate:** Jon works through the candidate list in Settings. On today's library,
    expect about 100: 34 overlap, 22 suffix, 28 reordered, 23 inserted, and 1 joined, with some
    pairs found by more than one shape. Most reordered pairs are one duet credited in both
    orders. Then, in a chat:
    - `check_tracks` for a `John Cougar Mellencamp` song is owned;
    - `top_artists` lists Elvis Presley once.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Suffix markers | ` and the `, ` and his `, ` and her `, ` live`, ` solo` | Measured: covers the top merges with 2 false merges. |
| Generic credit words | band, friends, others, family, orchestra, guests | Measured: `bruce hornsby and band` → The Band. |
| Overlap threshold | ≥ 4 shared titles and ≥ 50% of the smaller key | Measured: 34 candidates in Swift (44 in the Python probe), about half real. |
| Shared-title cap | titles shared by ≤ 5 keys, in both counts | Standards like "White Christmas" otherwise pair everyone. |
| Structural suffixes | band, trio, quartet, experience, acoustic trio | Seen in the candidates; 22 pairs. |
| Joined-word minimums | known key ≥ 2 words, last word ≥ 3 characters, joined-on part ≥ 4 characters | Measured: leaves only `john lennonplastic`; without them, 2,958 candidates (#101). |
| Inserted words | exactly 1, between the known key's first and last words | Measured: 23 pairs, mostly real. |

## Out of scope — with destinations

- **Apple catalog artist IDs as identity.** Jon's 54,166 uploads have none, the listening log
  stores text only, and Music.app's scripting doesn't expose them. → No.
- **Fixing the tags in Music.app** (for example, retagging `The Eagles` as `Eagles`). That's
  metadata-policy work, and catalog spellings like "John Cougar" can't be changed anyway. →
  A candidate after S1, if Jon wants a cleanup pass.
- **Splitting a false merge** (`martha and the vandellas` / `martha and the muffins`). → Only if
  a real request trips on one.
- **Title identity** (remasters, live suffixes in titles, covers across artists). → Taste
  Intelligence's composition level, after its S3.
- **Automatic aliases from title overlap.** About half the candidates are covers, producers, or
  cast recordings. → No: Jon decides each one once.
- **Adding an alias by hand** (`john cougar`, `on a friday`, which no rule finds). → A candidate
  in `open-questions.md`, after S1's gate.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves the
recommendations. It doesn't dispatch anything: M13 S2's completing PR sets `NEXT_UP.md` to
Dispatch 1.

1. **One identity for every artist comparison, replacing the per-slice rules.** That includes
   the catalog scorer, which M14 Decision 5 left exact. It's the only way to stop fixing this
   per slice. The tests pin today's behavior where it was right (Springsteen uploads still
   route).
2. **Keys for grouping, credits for matching.** A duet is its own artist in rankings, but a
   request for either named artist finds it. One key can't do both: merging duets into a
   single artist would be wrong for `top_artists`.
3. **Aliases are Jon's decisions, stored as data.** Title overlap finds them, but half its
   candidates are wrong. A one-time review of about 45 pairs, plus the occasional new one, is
   cheaper than a heuristic that's wrong half the time.
4. **Store decisions in SQLiteData and export a small file for `vf-mcp`,** rather than putting
   them in the snapshot. The snapshot is derived from Music.app and is rebuilt on refresh. The
   aliases are Jon's own data, and changing one shouldn't rewrite 87,000 tracks. This is the
   ADR-0007 pattern: app data in its store, a read-only export for the helper.
5. **Order: M13 S2 → M15 S0 → M14 S1 → M15 S1 → M13 S3.**
   - S0 goes before M14 S1, because S1's `uploadedAlbums` would otherwise extend the prefix
     rule to another tool.
   - S1 waits until after M14 S1. M14 S1 doesn't need aliases, and S1's gate is Jon's review
     session, so it shouldn't hold up the chat's uploads.
   - M13 S2 and M15 S0 both touch `LibraryMCPServer` and `ListeningLog`, so they run one after
     the other.
6. **Accept the two measured false merges.** Avoiding them would make layer 2 depend on the
   library (strip a suffix only from known one-word artists). Then the poller and Settings,
   which have no library, would build different keys from `vf-mcp`.
