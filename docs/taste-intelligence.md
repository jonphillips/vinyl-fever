# Taste Intelligence — design (v1)

*The design behind [M17](milestones/M17-taste-intelligence.md), which holds the build order and
the decisions that amend this doc. It builds on M11, M12, and M13. Written 2026-10-20 from a
conversation between Jon and the architect, starting from a Codex brief. Every number below was
measured from Jon's library that day unless it carries another date.*

Summary: Vinyl Fever learns Jon's taste from evidence he already produces: his yearly
**Jon's Selections** playlists, his other playlists, **Replay**, the weekly **New Music** mix he
grades in full, the M13 listening log, and his own spoken reasons. It keeps that evidence
deterministic and explainable, and lets the chat model do the reasoning: it proposes songs Jon
probably doesn't know, explains each one against named examples, and Vinyl Fever measures which
ones he keeps. No scores, no embeddings, no Vinyl Fever-side model calls, and no iPhone app to
start: keeps and passes come from what Jon already does, and one shortcut captures his reasons
on the move. *Amended 2026-10-27 (Jon): the iPhone companion is approved, and Music Feedback
moves from the shortcut into an App Intent that writes the same notes format (see
[Open Questions](open-questions.md) *Now-playing album brief*).*

## The north star

"Find me 15 songs I probably don't know but am unusually likely to love. Explain what you've
learned about my taste that makes each one a good bet, and learn from which ones actually become
favorites." Success means Vinyl Fever's discoveries are **kept more often than Apple's New Music
picks** (see *Baselines*). *Amended by [M18](milestones/M18-taste-outcomes.md) Decision 1
(2026-10-25): the two sources draw from different eras, so there's no head-to-head. Outcomes are
compared within release-age bands, and the chat is tested on new releases by picking from New
Music's own weeks.*

## Evidence (measured 2026-10-20)

Read-only AppleScript against Music.app on the laptop:

- **Explicit signals are almost unused:** 19 favorites, 4 dislikes, and 70 star ratings across
  87,114 tracks. Jon will start using Favorite and Suggest Less now that they feed this (Jon,
  2026-10-20), but the design can't depend on them.
- **74 user playlists** (8 smart, the rest regular) and **about 75 subscription playlists**
  (followed editorial and third-party lists, Apple's personal mixes, and Replay). Music's
  scripting splits them into two classes, `user playlist` and `subscription playlist`, so a
  reader has to ask for both.
- **Jon's Selections 2021–2026** (2020 is empty): 518 recordings, 512 songs, about 60–130 a
  year. 511 are streamed catalog songs, and only 4 songs repeat across years. **What it is (Jon):**
  through the year, when he hears a song from the current year that he likes, he adds it. It's
  the strongest curation signal there is: a live, dated list of discoveries he chose to keep.
- **Other hand-curated playlists:** 1,837 songs by 1,190 artists; 255 songs are in two or more.
  Their names are taste statements in themselves ("Country, but defensible", "Pop Songs in Rock
  Clothes", "Innocuous pop", "Power Pop 1977–82: Familiar Hooks & Five Finds").
- **Collection: '70s–'00s:** 6,957 matched or uploaded tracks. A record of ownership, not
  affinity.
- **Replay 2015–2026 and Replay All Time** are in the library (Jon added them 2026-10-20; they
  appeared within minutes), about 100 songs each, ranked by cross-device plays.
- **New Music** (25 songs) is Jon's personal New Music Mix. Apple puts it in his library
  automatically and replaces it every week. **Jon listens to all of it** and adds what he likes
  to Selections, so a song he heard and didn't add is a real verdict.
- **No dates on playlists or playlist entries.** Music's scripting gives none: not when a
  playlist was made, and not when a track joined it. Membership history exists only from the
  moment Vinyl Fever starts taking snapshots of it.
- **Reading every regular playlist's members** took 49 s with a crude AppleScript that builds
  text. The snapshot's bulk raw-event reader should be much faster; S0 measures it.
- **Shortcuts can see what's playing, but not on a first hearing** (Jon's phone, 2026-10-20):
  - **Get Current Song** returned the title, artist, and play count for "Skateaway" (Dire
    Straits).
  - It came back **blank for a song Jon was hearing for the first time.** The title appeared
    only after he moved on to the next track and came back.
  - **Likely cause:** iOS writes a streamed song's full record only when the queue moves past
    it, at about the moment it enters recently played. Until then Shortcuts sees an empty
    placeholder.
  - **Not yet confirmed:** whether skipping after 10 seconds is enough, or whether the song has
    to play longer (S0).

  That's exactly the New Music audition, so the feedback design can't depend on Get Current
  Song (see *Architecture*).

From the web, unverified against Jon's account:

- Apple documents a "get the user's replay data" endpoint for the **latest eligible year only**.
  Earlier years are reachable through the library playlists above instead.
- `/v1/me/recommendations` (Apple's "For You" groups) returns playlists, albums, and stations,
  not single songs. A catalog similar-artists view probably exists. Station and autoplay queues
  can't be read; their songs still reach the M13 log as starts.

## Data rules

- **The 2018 cutoff.** Before 2018 the family shared one Apple Music account. Use Replay 2018
  onward; ignore Replay 2015–2017 and Replay All Time. Mac lifetime play counts and date added
  for tracks added before 2018 are unreliable unless the song has been chosen since (it's in
  Selections, a curated playlist, or a Replay year from 2018 on).
- **Count choices, not recordings.** The unit of taste is the **song**, the existing
  `SongTextNormalizer` artist + title key that `check_tracks` and the listening log already use.
  Recordings (persistent ID, library ID, or catalog ID) stay the unit of evidence. Owning 2,437
  Springsteen archive tracks is a collection fact. Choosing 62 Springsteen songs for curated
  playlists is a taste fact. A composition level across artists (covers) is deferred.
- **Auditioned vs background.** In an auditioned playlist (New Music), not keeping a song Jon
  heard is a real negative. Anywhere else, not keeping or not playing a song means almost
  nothing.
- **Plays are starts** (M13 *Fidelity*). Repeats on separate days count; raw totals don't.
- **Never store an interpretation as a fact.** Jon's words are kept verbatim. Synthesis happens
  in the chat, at the moment it's needed.

## Playlist roles

A small file Jon edits once (about 150 playlists, ten minutes): playlist → role. A new
playlist starts unlabeled, and the app asks. Roles:

| Role | Example | What membership means |
| --- | --- | --- |
| `keepers` | 2021–2026: Jon's Selections | New this year and chosen. The strongest signal. |
| `replay` | Replay 2018–2026 | Ranked cross-device plays for that year. |
| `curated` | Power Pop, Pop Songs in Rock Clothes | Chosen for a style or mood. |
| `situational` | Dinner Party 2024, Working | Fits a context. |
| `auditioned` | New Music | Exposure: heard in full and graded. |
| `discovery-inbox` | My Shazam Tracks | Curiosity, not endorsement. |
| `followed` | Jangle Pop Essentials, New Music Daily | Following it is the signal; its tracks aren't. |
| `apple-mix` | Heavy Rotation, Get Up! | Apple's own view of Jon. |
| `collection` | Collection: '80s | Ownership. |
| `vinyl-fever` | playlists Vinyl Fever created | Exposure. Jon pruning or keeping songs is the feedback. |
| `ignore` | Comedy, Music Videos, Replay 2015–2017 | Nothing. |

Correlated playlists aren't independent endorsements: evidence is reported **by role**, never by
counting playlists.

## Architecture

The M12 and M13 patterns, extended: a rebuildable snapshot, append-only logs for history that
can't be rebuilt, and narrow MCP tools. Vinyl Fever stays deterministic. **The chat client is
the only model**: it reads evidence, generates candidates from its own knowledge of music, and
explains its choices. Vinyl Fever checks novelty, keeps history, and measures outcomes.

```
Music.app ──snapshot v2 (laptop)──▶ tracks + every playlist's members + disliked   (derived)
                │ diff vs previous snapshot
                ▼
   iCloud Drive / Vinyl Fever /
     Listening/   (M13 log: starts, every device)
     Curation/    playlist adds/removals, favorite/dislike changes      (append-only)
     Exposure/    weekly New Music contents, saved by the mini via API  (append-only)
     Feedback/    VF Note shortcut + chat notes: Jon's reasons, verbatim (append-only)
     playlist-roles.json  (Jon-authored)
                ▼
   vf-mcp ──▶ chat (ChatGPT, Claude Code, Codex): evidence in, candidates out
                ▼
   stage_playlist ──▶ PlaylistInbox/Processed (+ familiarity at staging) = recommendation ledger
```

- **Snapshot v2 (derived):** adds every playlist of both scripting classes (persistent ID, name,
  folder, class, smart flag, ordered member IDs) and the `disliked` track property. Order is
  kept because Replay's order is its rank.
- **Curation log:** each refresh appends what changed since the previous snapshot. Refreshes are
  irregular (when the laptop app runs), which is fine for something that changes slowly. A song
  added and removed between refreshes is missed.
- **Exposure log:** New Music is replaced weekly and the laptop runs too irregularly to catch
  every week, so the mini saves its contents weekly through the Apple Music API, next to the
  listening poller. Joined with the listening log (heard) and the curation log (kept), it gives
  **kept vs passed from the same week**. That contrast, shown to the chat, is what teaches it
  what separates a keeper from a pass.
- **Feedback: two verdicts need no tap, and one shortcut covers the third.**
  - **Keep is native.** Adding the song to Selections, in the Music app or by asking Siri ("add
    this to my 2026 Selections"), works on a first hearing, and the curation log already sees
    the add. No shortcut.
  - **Pass is inferred.** Jon hears New Music in full, so a song he heard (listening log) and
    didn't add (curation log) within two weeks is a pass. No shortcut.
  - **VF Note** (renamed **Music Feedback** on 2026-10-25, because Siri heard "VF Note" as a
    request to the Notes app; see [the feedback guide](feedback-guide.md)) captures the reason,
    the best feedback Jon gives and the one that disappears
    today. It runs from Siri (including CarPlay), the Action button, Control Center, or the Lock
    Screen. It tries three ways to identify the song:
    1. `Get Current Song`. It works for songs the phone has a record of, but not on a first
       hearing (see *Evidence*).
    2. If the title comes back empty, Shazam's `Recognize Music`, which identifies whatever is
       audible through the microphone. It takes about 5–10 seconds and works on a first hearing.
    3. If both fail (a noisy car), it keeps only the time. On the Mac, Vinyl Fever suggests the
       likely song from that week's New Music list and the listening log, and Jon confirms.

    Then `Dictate Text` takes the reason, and `Dictionary` → `Append to Text File` writes one
    JSON line: the title, artist, and album (the song key), how the song was identified
    (`now-playing`, `shazam`, or `time-only`), the time, and the reason.

  A small iOS app with App Intents can replace the shortcut later and write the same format, so
  the Mac side wouldn't change.
- **Taste notes from the chat:** an MCP tool records Jon's words into the same Feedback log
  (the melodic-rock playlist critique is the first example). It writes Vinyl Fever's own file,
  never Apple Music.
- **Recommendation ledger:** `PlaylistInbox/Processed/` already archives every staged playlist.
  The addition: each track's familiarity when it was staged (in library, in a playlist, heard in
  the log, recommended before), so outcomes measure discoveries only.

### MCP tools (first set)

The M12 rules apply: compact JSON, no IDs or paths, capped results, coverage on log-backed
results.

| Tool | Returns |
| --- | --- |
| `list_playlists` | name, role, folder, size; filter by role |
| `playlist_tracks` | one playlist's songs in order (Replay's rank), with stats |
| `check_tracks` (extended) | adds playlist roles each song is in, heard in the log, recommended before and the outcome, passed in New Music |
| `taste_evidence` | for an artist or song: the evidence by role and source, with dates; no score |
| `taste_notes` / `record_taste_note` | Jon's words, verbatim, with the song or playlist they're about |
| `kept_and_passed` | New Music weeks: kept vs passed, with coverage |
| `keepers`, `neglected_keepers` | the example set, and keepers missing from recent listening (needs months of log) |

### How the north-star question runs

1. The chat reads roles, notes, and examples (Selections, recent Replay, kept vs passed).
2. It proposes about 40 candidates from its own knowledge, plus Apple's (see below).
3. `check_tracks` drops anything owned, heard, recommended before, or rejected.
4. It picks 15 and explains each against named examples ("like X and Y in your 2024 Selections;
   not like the chugging-guitar AOR you passed on").
5. `stage_playlist`; the ledger records familiarity.
6. Weeks later: which songs Jon added to Selections or other playlists, replayed on separate
   days, kept or pruned from the Vinyl Fever playlist, or commented on through VF Note.

## Apple's data

Apple has what Vinyl Fever can't build: listening data from millions of people. Vinyl Fever
doesn't imitate it; it **collects what Apple's recommenders produce**:

- **As candidates:** New Music, the other personal mixes, "For You", and similar artists. Apple's
  picks come from what similar listeners play; the chat's come from what it knows about music.
  Jon's evidence decides and explains.
- **As the baseline:** New Music is Apple's recommender aimed straight at Jon, graded in full
  every week. Its keep rate is Apple's discovery yield. *Since M18, it's reported as New Music's
  own number, not a bar for the chat to beat.*

## Baselines (measurable before any recommendation)

- **Apple's yield:** the share of New Music songs Jon keeps, week by week (needs the exposure
  log).
- **Jon's own stick rate:** the share of year N's Selections that appear in Replay N or N+1,
  computed back to 2021 from data already in the library. It says how many of his own finds
  became songs he returned to.
- **Vinyl Fever's yield:** the share of unfamiliar recommended songs that become keepers. With
  about 15 songs a playlist this stays noisy for a long time: report it, don't optimize against
  it.

## Phasing (candidate)

*Planned as [M17](milestones/M17-taste-intelligence.md) on 2026-10-23. M17 runs exposure and
curation before feedback, and lets the chat resolve time-only notes instead of a Mac screen; its
Decisions list every change. This section is kept as the candidate it was.*

**Now, no code (Jon):** keep doing Selections; use Favorite and Suggest Less; Replay is already
added.

1. **S0 — Probes (architect).** *Done 2026-10-23. Started 2026-10-22 (Jon chose Taste Intelligence next). The
   architect runs the API and snapshot probes on the laptop; Jon runs the Shortcuts probes on
   the iPhone. The results go into this doc and decide the M17 brief for S1.*
   - Does `/v1/me/library/playlists` show New Music, and does its ID survive the weekly refresh?
   - What do `/v1/me/recommendations` and a catalog similar-artists view return?
   - Can `/v1/me/ratings/songs` read hearts and dislikes on catalog songs outside the library?
   - How long does the snapshot read take with both playlist classes' members?
   - Shortcuts:
     - Does `Get Current Song` fill in after a 10-second skip and a return, or only after a
       longer play?
     - Does `Recognize Music` identify New Music songs reliably, at home and in the car?
     - Which iCloud Drive folders can `Append to Text File` write to?
     - Do Siri in CarPlay and the Action button run VF Note while the phone is locked?
     - Does Siri's "add this to my 2026 Selections" work on a first hearing?
2. **S1 — Playlists in the snapshot.** Snapshot v2, `playlist-roles.json` and its Settings
   editor, the 2018 rule, `list_playlists`, `playlist_tracks`, and extended `check_tracks`.
   The chat can then use Selections and Replay as examples. Gate: Jon asks for 15 songs "in the
   spirit of my 2025 Selections" and judges them.
3. **S2 — Feedback.** The VF Note shortcut (exported into the repo, with setup steps), the Mac's
   confirmation of time-only notes, `record_taste_note`, and `taste_notes`.
4. **S3 — Exposure and curation logs.** The mini's weekly New Music save, snapshot diffs,
   `kept_and_passed`, and both baselines.
5. **Later milestone — outcomes.** The ledger's familiarity field, discovery yield, Apple's
   candidates, `taste_evidence`, `neglected_keepers`. An iOS app only if Shortcuts run out.

S1 and S2 both edit `vf-mcp`, so they run one after the other. M13 finished before M17 began.

### S0 results: API and snapshot (architect, 2026-10-22)

Probed with a scratch build of Vinyl Fever (`--probe-get`, the app's own MusicKit authorization)
and AppleScript against Music.app.

- **New Music is reachable, and its ID is stable.**
  - The library playlist `p.5pvKi0GQXD` has existed since 2019-02-22, so the ID survives every
    weekly refresh. Its library `lastModifiedDate` never changes, though.
  - The catalog form, `GET /v1/catalog/us/playlists/pl.pm-20e9f373919da0805771c118dd5266b7?include=tracks`
    (`playlistType: personal-mix`, curator "Apple Music for Jon"), carries the real
    `lastModifiedDate` (2026-10-16T10:04Z, a Friday) and all 25 songs, with catalog IDs and
    release dates.
  - **The weekly save uses the catalog route, keyed by that date.**
- **New Music songs never enter the library; keeps are separate copies.**
  - Members found in the library snapshot: New Music 0 of 25, Replay 2025 96 of 100, Replay
    2018 61 of 98, 2025 Selections 130 of 130.
  - So snapshot v2 stores artist, title, and album text for members that aren't library tracks.
  - Kept-versus-passed matches on **catalog ID**: 97 of 99 songs in 2026 Selections carry
    `playParams.catalogId`. `ArtistIdentity` + title text is the fallback.
  - **The catalog-ID link is confirmed (2026-10-22).** Jon kept "White Knight" (Cats in Space)
    from New Music. It's catalog `6815778888` in the personal mix, and its 2026 Selections copy
    (`i.vg51ZSZaW83`) carries `playParams.catalogId` `6815778888`.
- **Reading playlist members is cheap.** AppleScript reads the persistent IDs of every member
  of 65 user playlists and 77 subscription playlists (about 20,090 entries) in **2 s**.
- **Ratings are readable for songs outside the library, by ID only.**
  - `GET /v1/me/ratings/songs?ids=…` returned `value: 1` for two favorites found through
    catalog search. `/v1/me/ratings/library-songs` works the same way.
  - There's no list endpoint, so Vinyl Fever asks about known IDs: each week's 25 New Music
    songs, and Selections.
  - A heart belongs to one catalog release. "Painkillers" (a favorite) showed no rating on any
    of its three search results.
- **Apple's recommendations are broad; similar artists is useful.**
  - `/v1/me/recommendations` returns 20 groups of albums, playlists, and stations, and no
    songs. The groups range widely (Americana, Power Pop, Hair Metal, 2000s Country, and "More
    Like Sunday Best" with Justin Bieber and Jason Derulo).
  - **Don't judge a group by its genre.** The architect first called the pop row noise. Jon
    corrected that: he likes some of that music, and his taste isn't only Americana. Whether a
    group is a good source is for the outcomes (kept versus passed) to show, not for Vinyl Fever
    to assume. Groups are album- and playlist-level, so they're candidate sources, not evidence.
  - The catalog artist view `?views=similar-artists,top-songs` returns 10 per page, with more,
    and the results make sense: John Prine → Guy Clark, Todd Snider, Townes Van Zandt, Steve
    Earle. It's a candidate source for the outcomes milestone too.
- **More playlists exist than the doc listed.** Selections exists for **2020–2026**, not
  2021–2026. Replay 2015–2017 and Replay All Time exist too, and the 2018 rule excludes them.

### S0 results: VF Note (Jon and the architect, 2026-10-22)

*The shortcut is now named Music Feedback (2026-10-25). These results are kept as recorded.*

Jon built **VF Note** in Shortcuts. It writes one JSON object per line to
`iCloud Drive/Vinyl Fever/Taste Intelligence/notes.jsonl`, next to `Listening/`.

**Format `vf-taste-note` v1** (one line; key order isn't fixed):

```json
{"format":"vf-taste-note","version":1,"notedAt":"2026-10-22T10:30:35-04:00","title":"White Knight","artist":"Cats in Space","album":"White Knight - Single","playCount":0,"releaseDate":"2026-10-16T08:00:00-04:00","duration":"4:42","note":"Has a rock opera vibe","source":"current-song","device":"Jon’s iPhone 17 Pro"}
```

| Key | Meaning |
| --- | --- |
| `notedAt` | When Jon made the note (ISO 8601 with offset). It orders notes and matches a note to a play window. |
| `title`, `artist`, `album` | Current Song's text. Notes match songs by `ArtistIdentity` + title, and `album` picks the release. |
| `playCount` | The count when the note was made. 0 means a first hearing: the count only rises after a song finishes. |
| `releaseDate` | Full ISO date-time from Shortcuts; readers use the date part. |
| `duration` | `m:ss` text, as Shortcuts displays it. |
| `note` | Jon's spoken or typed reason ("Ask for Input"). May be empty. |
| `source` | `current-song`, or `shazam` once the Recognize Music fallback exists. |
| `device` | Shortcuts' device name. |

**Shortcuts details the S2 brief must respect** (worked out 2026-10-22):
- **The shortcut:** Dictionary → **Get text from Dictionary** → **Append to Text File**
  (`notes.jsonl` in the Taste Intelligence folder, "Make New Line" on).
- **`notes.jsonl` must already exist.** Shortcuts doesn't know the `.jsonl` extension. When
  Append has to *create* the file and the text looks like JSON, it saves `notes.jsonl.json`
  instead. The next run can't find `notes.jsonl` either, so it saves `notes.jsonl-2.json`, and so
  on, one file per note. Once `notes.jsonl` exists, Append adds to it. Setup must create the file:
  an empty file is fine, since the reader skips blank lines. S2's setup steps, and `setup-mac`'s
  chat role, create it if it's missing.
- A Text action that holds only the Dictionary variable passes the dictionary through
  unchanged. Use Get Text from Input instead.
- Shortcuts writes dates as ISO 8601 in a Dictionary on its own. Format Date isn't needed.
- "Make New Line" puts the newline *before* each appended entry, so the file has no trailing
  newline. As with the listening log, the reader tolerates a missing final newline, skips blank
  lines, and ignores a partial last line.
- Verified 2026-10-22: a note recorded on the iPhone appended as the third line of a
  Mac-created `notes.jsonl` (Shack, "Natalie's Party", `playCount` 1).
- Jon switched the reason prompt from Ask for Input to **Dictate Text**. VF Note runs from
  CarPlay Siri by name (2026-10-23) and from the Action button while locked (2026-10-22).
- iCloud can make conflict copies (`notes 2.jsonl`) when two devices append offline. The reader
  reads every `notes*.jsonl` in the folder and de-duplicates on (`notedAt`, `title`, `artist`).
- Device names use a curly apostrophe (`Jon’s`), so readers must handle UTF-8.

**The Shortcuts probes' answers (Jon, 2026-10-22 and 2026-10-23).** S0 is complete.
- Siri's "add this to my 2026 Selections" works on a first hearing, so Keep needs no shortcut.
- The Action button runs VF Note while the phone is locked.
- VF Note runs from CarPlay through Siri, by the shortcut's name.
- Recognize Music identifies songs on normal playlists.
- On Discovery Station, Current Song stays blank until Jon skips forward and back. That's his
  habit now, so nothing is built around it.

## Out of scope — with destinations

- **Scores** (affinity, confidence, current interest). → No: examples and evidence instead.
- **Embeddings, vector search, ranking models.** → Only for a specific need that examples can't
  meet.
- **Audio analysis.** The Apple Music API has no tempo, energy, or mood data, and Jon's feedback
  ("chugging guitars, generic keyboards, weak hooks") is judgment the chat model makes better
  from its own knowledge. → No.
- **A stored taste profile written by a model.** → Only if writing it fresh in each chat costs
  too much or drifts.
- **A player, or a triage app.** → Shortcuts first; an App Intents app only if they run out.
- **Composition identity across artists** (covers). → After S3, if the evidence asks for it.
- **Filtering short plays.** → Stays parked (`open-questions.md`, *Listening analytics*).
- **Pre-2018 data.** → Never (shared family account).

## Decisions (architect's recommendation first)

1. **No model calls inside Vinyl Fever.** The chat is the interpreter; Vinyl Fever serves
   evidence. That keeps interpretation out of stored data by construction.
2. **Examples and evidence, not scores.**
3. **One shortcut before an app, and taps only for reasons.** Keep is Jon's native add to
   Selections, and Pass is inferred from New Music heard and not added, so the only shortcut is
   VF Note. It covers CarPlay, Siri, and the Action button with nothing to build or maintain,
   and it never writes to Apple Music, so Vinyl Fever's "propose, never write" rule is
   untouched.
4. **Append-only JSONL in the iCloud Drive Vinyl Fever folder** for the curation, exposure, and
   feedback logs, as for listening (M13 Decision 1): `vf-mcp` reads them with no app running.
   `playlist-roles.json` lives there too, so the mini and `vf-mcp` can read it.
5. **The mini saves New Music weekly** through the API rather than relying on laptop snapshots.
6. **The 2018 cutoff** as stated in *Data rules*.
