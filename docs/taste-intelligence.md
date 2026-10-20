# Taste Intelligence — candidate design (v1)

*A candidate, not a milestone. Nothing here is dispatchable until a plan PR moves it into a
milestone and sets `docs/NEXT_UP.md`. It follows M13 and M14 and builds on M11, M12, and M13.
Written 2026-10-20 from a conversation between Jon and the architect, starting from a Codex
brief. Every number below was measured from Jon's library that day.*

Summary: Vinyl Fever learns Jon's taste from evidence he already produces: his yearly
**Jon's Selections** playlists, his other playlists, **Replay**, the weekly **New Music** mix he
grades in full, the M13 listening log, and his own spoken reasons. It keeps that evidence
deterministic and explainable, and lets the chat model do the reasoning: it proposes songs Jon
probably doesn't know, explains each one against named examples, and Vinyl Fever measures which
ones he keeps. No scores, no embeddings, no Vinyl Fever-side model calls, and no iPhone app to
start: Shortcuts capture feedback on the move.

## The north star

"Find me 15 songs I probably don't know but am unusually likely to love. Explain what you've
learned about my taste that makes each one a good bet, and learn from which ones actually become
favorites." Success means Vinyl Fever's discoveries are **kept more often than Apple's New Music
picks** (see *Baselines*).

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
- **Shortcuts can see what's playing** (Jon's phone, 2026-10-20): **Get Current Song** returned
  the title, artist, and play count of a streamed catalog song ("Skateaway", Dire Straits,
  0 plays).

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
     Feedback/    Shortcuts: note / keep / pass on the playing song     (append-only)
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
- **Feedback log, written by Shortcuts** (no app): `Get Current Song`, `Dictate Text`, and for
  Keep, `Add to Playlist` → the current Selections; then `Dictionary` → `Append to Text File`
  writes one JSON line. They run from Siri (including CarPlay), the Action button, Control
  Center, or the Lock Screen:
  - **VF Note:** the song plus Jon's dictated reason. Reasons are the best feedback Jon gives,
    and they disappear today.
  - **VF Keep:** adds the song to Selections and logs it.
  - **VF Pass:** logs an explicit pass.

  The line identifies the song by title, artist, and album (the song key), plus the time and
  which shortcut wrote it. A small iOS app with App Intents can replace the shortcuts later and
  write the same format, so the Mac side wouldn't change.
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
   days, kept or pruned from the Vinyl Fever playlist, or tagged through a shortcut.

## Apple's data

Apple has what Vinyl Fever can't build: listening data from millions of people. Vinyl Fever
doesn't imitate it; it **collects what Apple's recommenders produce**:

- **As candidates:** New Music, the other personal mixes, "For You", and similar artists. Apple's
  picks come from what similar listeners play; the chat's come from what it knows about music.
  Jon's evidence decides and explains.
- **As the baseline:** New Music is Apple's recommender aimed straight at Jon, graded in full
  every week. Its keep rate is Apple's discovery yield.

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

**Now, no code (Jon):** keep doing Selections; use Favorite and Suggest Less; Replay is already
added.

1. **S0 — Probes (architect).**
   - Does `/v1/me/library/playlists` show New Music, and does its ID survive the weekly refresh?
   - What do `/v1/me/recommendations` and a catalog similar-artists view return?
   - Can `/v1/me/ratings/songs` read hearts and dislikes on catalog songs outside the library?
   - How long does the snapshot read take with both playlist classes' members?
   - Shortcuts: which iCloud Drive folders `Append to Text File` can write; do Siri in CarPlay
     and the Action button run it while the phone is locked; does `Add to Playlist` take a
     catalog song that isn't in the library?
2. **S1 — Playlists in the snapshot.** Snapshot v2, `playlist-roles.json` and its Settings
   editor, the 2018 rule, `list_playlists`, `playlist_tracks`, and extended `check_tracks`.
   The chat can then use Selections and Replay as examples. Gate: Jon asks for 15 songs "in the
   spirit of my 2025 Selections" and judges them.
3. **S2 — Feedback.** The shortcuts (exported into the repo, with setup steps),
   `record_taste_note`, `taste_notes`.
4. **S3 — Exposure and curation logs.** The mini's weekly New Music save, snapshot diffs,
   `kept_and_passed`, and both baselines.
5. **Later milestone — outcomes.** The ledger's familiarity field, discovery yield, Apple's
   candidates, `taste_evidence`, `neglected_keepers`. An iOS app only if Shortcuts run out.

S1 and S2 both edit `vf-mcp`, so they run one after the other. Where M13 S3 falls relative to
this is Jon's call.

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
3. **Shortcuts before an app.** They cover CarPlay, Siri, and the Action button with nothing to
   build or maintain. The Keep shortcut adds to Selections through Apple's own action, by Jon's
   hand, so Vinyl Fever's "propose, never write" rule is untouched.
4. **Append-only JSONL in the iCloud Drive Vinyl Fever folder** for the curation, exposure, and
   feedback logs, as for listening (M13 Decision 1): `vf-mcp` reads them with no app running.
   `playlist-roles.json` lives there too, so the mini and `vf-mcp` can read it.
5. **The mini saves New Music weekly** through the API rather than relying on laptop snapshots.
6. **The 2018 cutoff** as stated in *Data rules*.
