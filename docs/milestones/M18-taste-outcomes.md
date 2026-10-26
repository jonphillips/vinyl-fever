# Milestone 18 — Taste outcomes (what Jon keeps, by source)

*Measure what happens to the songs Jon is shown: which ones he keeps, from which source, and how
new they were. It builds on [M17](M17-taste-intelligence.md), whose shared rules still apply, and
on the design in [../taste-intelligence.md](../taste-intelligence.md). Where this doc and the
design conflict, this doc's Decisions win. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply.*

Summary: Three slices are dispatched, and a fourth is decided at S2's gate.
- **S1** starts the recommendation ledger now. Every `stage_playlist` records which songs were
  new to Jon, and `check_tracks` reports "recommended before". It's a log that can't be rebuilt
  later, so it goes first.
- **S2** reads the ledger: outcomes by source and by how recently each song was released, the
  chat's blind picks from each New Music week (the fair test of the chat on new releases), and
  a fix to the Selections stick rate for Jon's new filing habit.
- **S3**, which adds Apple's candidates for new releases, is built only if S2 shows the chat is a
  good judge of them.
- **S4** lets the chat ask Jon what it wonders about. Questions and answers are taste notes, at
  most 3 open at a time, and a skip is final. It comes from plan PR #127 (never merged), and it
  runs after S2.

Vinyl Fever still makes no model calls and stores no scores. [M19](M19-backups.md)'s backup
slice runs between S1 and S2 (M19 Decision 7).

## The milestone in one sentence

For every song Vinyl Fever puts in front of Jon, it can say where the song came from, whether it
was new to him, how recent it was, and whether he kept it. It compares sources only within the
same kind of song.

## Why the comparison changed (Jon, 2026-10-25)

The design's north star measured success as the chat's discoveries being "kept more often than
Apple's New Music picks". Jon pointed out that the two aren't the same contest:
- New Music is this month's releases.
- The chat's first batch of 15 reached back almost 20 years: release years 2006 to 2024, none
  from 2025 or 2026.
- A chat model knows little about releases newer than its training data, so it's weakest exactly
  where New Music lives.

So there's no head-to-head between the two sources (Decision 1). Outcomes are reported by source
within release-age bands. The chat is tested on new releases the fair way, by picking from New
Music's own 25 songs before Jon hears them (S2).

## What's true today (architect, read-only, 2026-10-25)

- **The first batch is archived.** `PlaylistInbox/Processed/20261024T134238Z-2025-selections-15-new-discoveries.vfplaylist`
  holds the 15 songs and their release years. Jon kept 11; all 15 were new to him, and he knew an
  artist or two (M17 S1's gate).
- **Where Jon put the keepers** (AppleScript against Music.app):
  - All 11 are in a new user playlist, **"Vinyl Fever Keepers"**, which has no role yet.
  - Ten of them he also filed into **the Selections playlist of their release year**:
    - 2020 (Dagny, GUV, Red Rum Club). The 2020 playlist was empty at S0.
    - 2021 (Lawrence).
    - 2022 (Gang of Youths, The Beths, Hatchie).
    - 2023 (Maisie Peters, The Beths again).
    - 2024 (The Lemon Twigs).
  - The two keepers from before 2020 (The Night Game 2017, The Wild Feathers 2013) are only in
    Vinyl Fever Keepers, since there's no Selections playlist that early.
  - The 4 he didn't keep are still in the staged playlist "2025 Selections: 15 New Discoveries".
- **Selections now gains songs years later.** None of the 15 were in any Selections playlist in
  the 2026-10-23 snapshot, so every add above happened after the songs were recommended. Selections N
  now means "released in year N and chosen", whenever Jon heard the song. That breaks M17's stick
  rate, which assumes Selections N was filled during year N (S2 fixes it).
- **The next snapshot refresh will record those adds.** `SnapshotCurationDiff` compares against
  the previous snapshot, which is already v2 (2026-10-23 19:21Z). It isn't a fresh baseline.
- **Nothing from M17 S2 or S3 is running yet.** The installed app and the running process date
  from 2026-10-23, and there's no `Taste Intelligence/exposure/` folder. See *Prerequisites*.
- **The listening log began 2026-10-20**, so anything that needs months of history waits (*Out of
  scope*).

## Shared rules (every slice)

- **M17's shared rules hold:**
  - the song is the unit;
  - evidence is reported by role;
  - Jon's words are verbatim;
  - taste files live in `Taste Intelligence/`, read with `NSFileCoordinator`, with whole-line
    appends;
  - M12's tool rules apply (no IDs and no paths in results, capped lists, coverage);
  - never judge by genre.
- **Only unfamiliar songs are outcomes.** A familiar song in a staged playlist is recorded, but it
  never counts as a keep or a pass.
- **Never a single cross-source number.** Outcomes come by source and by release-age band, with
  counts. A cell with fewer decided songs than the minimum (see *Constants*) shows counts and no
  ratio.
- **A ledger failure never fails staging.** Staging is Jon's action, and the ledger is a record
  of it.
- **Per-host files and host names:**
  - `ListeningStore.liveHostName()`, injected through `LibraryMCPServer.make(hostName:)` as in
    M17 S3;
  - tests use temp roots and never the live `Taste Intelligence/` folder.
- **Every chat gate starts the same way** (added 2026-10-25, after M17 S1's gate ran on an old
  build). Install from `main`, refresh the Vinyl Fever tools in the chat (or start a new
  thread), and confirm the chat lists the expected tools. Once M16 S4 ships, it should also name
  the build the installer printed. The architect checks the install time before recording a
  gate.

## Slices

**Dispatch 1: S1** (Core + `vf-mcp`; Jon's gate). **Dispatch 2: S2** (Core + `vf-mcp`; Jon's gate
needs New Music weeks). **Dispatch 3: S4** (Core + `vf-mcp`; Jon's gate). **S3** is decided at
S2's gate. Every slice edits `vf-mcp`, so they run one after another. S2's completing PR
advances `NEXT_UP.md` to S4.

- [x] **S1 — The recommendation ledger (Core + `vf-mcp`).** Done in `m18/s1-recommendation-ledger`.
  - **Ledger file:** `Taste Intelligence/recommendations/<host>.jsonl`, one line per batch:
    ```json
    {"format":"vf-recommendation-batch","version":1,"kind":"staged-playlist","source":"chat",
     "recordedAt":"2026-10-24T13:42:38Z","host":"Jon MBP","playlist":"2025 Selections: 15 New Discoveries",
     "tracks":[{"artist":"The Beths","title":"Expert in a Dying Field","year":2022,
                "familiar":false,"reasons":[],"artistKnown":false}]}
    ```
    - `kind` is `staged-playlist` in S1, and S2 adds `new-music-picks`. `source` is `chat` for now.
    - Tracks are in staged order. `album` and `year` are written when given.
    - The reader skips blank lines and a partial last line, and tolerates no final newline. A newer
      version or unknown format is counted as skipped in coverage.
  - **Writing:** after `stage_playlist` stages the request, append one batch with the tracks that
    survived `PlaylistContract` (dropped tracks aren't recommendations).
    - If the append fails, staging still succeeds, and the result carries
      `ledgerRecorded: false` with a short reason and no path.
    - Every staged playlist is logged; there's no intent flag (Decision 3).
  - **Familiarity** (Core, pure; computed at `recordedAt` from the evidence `check_tracks`
    already has). `reasons` lists every one that applies:
    - `owned`: a library recording matches;
    - `heard`: a listening-log start before `recordedAt`;
    - `playlist:<role>`: a member of any playlist except `ignore` and `followed`. An unlabeled
      playlist counts too, as `playlist:unlabeled`;
    - `noted`: a taste note exists for the song;
    - `recommended`: an earlier ledger batch had the song.

    `familiar` is true when `reasons` isn't empty. `artistKnown` is true when the artist's
    `ArtistIdentity` key has any library track or any log start. It's recorded alone and never
    makes a song familiar (Decision 4).
  - **`check_tracks` and `playlist_tracks` evidence** gain `recommended`: the number of batches in
    which the song was unfamiliar, and the latest `recordedAt`.
    - Leave it out when the count is 0.
    - Leave it out, with no error, when the ledger can't be read, as M17 S3 does for notes.
    - Read the ledger once per call, not per row.
  - **Instructions:** in the taste paragraph, say:
    - stage discoveries with `stage_playlist`, because Vinyl Fever records which songs were new
      to Jon;
    - drop songs recommended before, unless Jon asks for them again.

    The first 512 characters must still stand alone. Update the instructions snapshot test.

  **DoD:**
  - **Core tests:**
    - each familiarity reason alone, an unlabeled playlist, `ignore` and `followed` not counting,
      and `artistKnown` true for a familiar artist with an unknown song;
    - the ledger round-trips, and the reader's tolerance cases;
    - `recommended` counts only unfamiliar entries.
  - **`vf-mcp` tests:**
    - `stage_playlist` writes one batch to a temp root, without dropped tracks;
    - an unwritable ledger root still stages and returns `ledgerRecorded: false`;
    - `check_tracks` then reports `recommended`;
    - golden JSON with no IDs or paths.
  - **Executor's laptop check** (read-only against live data; writes only to temp roots):
    - Compute familiarity for the 15 archived songs at `recordedAt` 2026-10-24T13:42:38Z, against
      Jon's real snapshot and listening log, and report each song's reasons and `artistKnown`.
    - Expected while the snapshot is still 2026-10-23's: all 15 unfamiliar, and `artistKnown`
      for one or two.
    - If Jon has refreshed by then, the playlist reasons will show his keeps instead. Report
      that, too.
  - **Jon's gate (after install, owed until done):** ask the chat for a new batch on any theme
    and stage it. The ledger gains a line. Then ask the chat to check a few of those songs:
    `check_tracks` shows them as recommended once.

- [ ] **S2 — Outcomes by source and release age, the chat's New Music picks, and the stick-rate
  fix (Core + `vf-mcp`).**
  - **One classifier.** Generalize `TasteIntelligence.keptAndPassed` into one function over a
    batch (a date and songs), used for New Music weeks and ledger batches alike. Its rules stay
    M17's: kept is in a `keepers` playlist now; passed is heard within 14 days and not kept, with
    the snapshot past the window; unheard; pending. S2's existing tests must pass unchanged.
  - **Release-age band** for each song, relative to the batch's year Y:
    - `new`: released in Y or Y−1;
    - `recent`: Y−5 through Y−2;
    - `catalog`: earlier than that;
    - `unknown`.

    The ledger uses `year`, and New Music uses `releaseDate`.
  - **`recommendation_outcomes`** (`vf-mcp`, read; input `batches`, default 10):
    - each ledger batch, newest first, with its unfamiliar songs classified and banded, and
      counts;
    - familiar songs listed as `notCounted`;
    - coverage: ledger skipped lines, listening coverage, and snapshot age.
  - **`taste_baselines` by source and band:**
    - a table of kept and passed counts, plus a ratio where a cell meets the minimum;
    - sources are `apple-new-music` and `chat`, crossed with the four bands;
    - the overall New Music yield stays, labeled as New Music's own;
    - no field compares the two sources (Decision 1).
  - **The chat's blind picks from New Music: the fair test of the chat on new releases.**
    - **`record_new_music_picks`** (`vf-mcp`, write, `destructiveHint: false`; input `songs`, a
      list of artist and title):
      - Every song must be in the latest saved New Music week. Otherwise it's an error naming
        the song.
      - It appends a ledger batch with `kind: "new-music-picks"`, `source: "chat"`, and the
        week's `lastModifiedDate`.
      - A song Jon had already heard before `recordedAt` is recorded with `heardBeforePick:
        true`, and it's left out of scoring.
    - **Scoring**, in `recommendation_outcomes` and `taste_baselines`: for each finished week,
      the songs Jon hadn't heard at pick time, split into picked and not picked, with each
      group's kept and passed counts. This compares like with like: the same week, the same
      songs, the same listener.
    - **Instructions:** when Jon asks which New Music songs he'll keep, the chat reads the week
      through `kept_and_passed`, picks, and calls `record_new_music_picks` before he listens.
  - **Stick-rate fix:** a song whose add to "N: Jon's Selections" the curation log first observed
    after the end of year N+1 is left out of N's stick rate. Adds from before the log began count
    as before. Each year reports `excludedLateAdds`.
  - **`check_tracks`'s `recommended`** gains the latest outcome.

  **DoD:**
  - **Core tests:**
    - the shared classifier gives S2's existing answers, plus ledger batches with familiar songs
      not counted;
    - each band boundary, and `unknown`;
    - the small-cell rule (counts and no ratio);
    - picks validation, `heardBeforePick` left out, and the picked-versus-rest counts on a fixture
      week;
    - the stick-rate exclusion on a fixture curation log with a late add.
  - **`vf-mcp` tests:** golden JSON for both tools, with no IDs or paths.
  - **Executor's laptop check:** `recommendation_outcomes` against the real data shows Jon's S1
    gate batch, pending or classified. Report it.
  - **Jon's gate (owed until two weeks finish):** for two New Music weeks, ask the chat on the
    Friday to pick the songs he'll keep before listening. After each week's 14 days, read
    `taste_baselines`, and say whether the picked-versus-rest result matches what happened. That
    result decides S3.

- [ ] **S3 — Apple's candidates for new releases (decided at S2's gate; not dispatched).**
  - **If the chat's picks beat the rest of the week** over about four finished weeks: give the
    chat Apple's recent releases to judge, as candidates. S0 found that the similar-artists view
    of artists Jon keeps returns 10 per page and makes sense. New releases by those artists would
    need a `latest-release` view, which is unverified, so the architect probes it first. The
    chat ranks and explains, and the ledger records `source: "apple-similar-artists"`.
  - **If not:** the chat stays on catalog depth, and New Music stays Apple's job, unfiltered.
  - Either way, the result is recorded here before anything is built.

- [ ] **S4 — The chat's questions (Core + `vf-mcp`).** *Added 2026-10-25 from plan PR #127,
  which was never merged; see Decision 8. M17 S3 (#129) built the notes it extends.*
  - **A question and its answer are taste notes.** They use the same files (`notes-chat-<host>.jsonl`)
    and the same reader. These optional keys are added to `vf-taste-note` v1; a line without
    them is an ordinary note, which covers every Music Feedback shortcut line:
    - `kind`: `note` (the default when it's missing), `question`, or `answer`;
    - `id`: a UUID on every line `record_taste_note` writes. It's the handle the chat uses to
      answer a question. It names no library item, so results may include it;
    - `answers`: on an answer, the question's `id`;
    - `skipped: true`: on an answer, meaning Jon declined. A skipped question never comes back;
    - `about`: on a question, the songs (`artist`, `title`) or playlist names it's about.
  - **Deduplicating:** a line with an `id` is unique by its `id`. Lines without one keep M17
    S3's key (`notedAt`, title, artist). A conflict copy must never show a question twice.
  - **A question's state is derived on read, never stored:**
    - **answered** or **skipped** when an answer line names it, from any host's file;
    - **expired** 21 days after `notedAt`;
    - **superseded** when 3 newer questions are still open. Only the 3 newest open questions
      stay open, so a new question pushes out the oldest;
    - **open** otherwise.
  - **`record_taste_note`** gains `kind` (`note` by default, or `question`), `answers` (with
    `skipped`), and `about`, and it returns the line's `id`.
    - It refuses an answer whose `answers` doesn't name a known question, and a question with
      empty text.
    - Its description says: ask only when the answer would change what you recommend next, and
      cite the contrast in Jon's evidence that prompted the question.
  - **`taste_notes`** returns `openQuestions` before the notes: at most 3, each with its `id`,
    text, `about`, and age. An answered question is returned like any other note, with its
    answer beside it.
  - **Instructions:** one paragraph in the taste section:
    - when Jon starts a taste conversation, ask at most one open question, and only if it bears
      on what he's doing;
    - record his answer verbatim with `answers`. "Skip" or "not now" is recorded as `skipped`;
    - record a new question whenever a choice or contrast in his evidence leaves you unsure,
      even if he isn't there to answer it;
    - never ask what the tools can already tell you.

    The first 512 characters must still stand alone. Update the instructions snapshot test.
  - **The shortcut's new name.** Jon renamed VF Note to **Music Feedback** (2026-10-25), because
    Siri heard "VF Note" as a request to the Notes app. Rename it in the user-facing strings:
    `record_taste_note`'s description, and the `setup-mac` check label ("VF Note file"). The
    file (`notes.jsonl`), the format, and `source` values don't change. Test names can stay.

  **DoD:**
  - **Core tests:**
    - a recorded question shows in `openQuestions` with its `id`, and an answer closes it,
      including an answer in another host's file;
    - a skip closes it for good;
    - it expires at 21 days;
    - a fourth open question supersedes the oldest;
    - a conflict copy of a question line doesn't duplicate it;
    - shortcut notes, with no `kind` or `id`, still read as notes, unchanged.
  - **`vf-mcp` tests:**
    - an answer naming an unknown `id` is refused, and so is an empty question;
    - golden JSON for `taste_notes` with `openQuestions`, with no paths or persistent IDs;
    - `record_taste_note` writes to a temp root only;
    - no tool description or `setup-mac` label says "VF Note".
  - **Executor's laptop check** (read-only against a copy of Jon's live notes): every existing
    Music Feedback line reads exactly as before, and `openQuestions` is empty.
  - **Jon's gate (after install, owed until done):**
    1. While building a list, the chat records a question about a contrast in his evidence.
    2. In a new taste conversation, the chat asks it. Jon answers, and `taste_notes` shows the
       question answered, with his words verbatim.
    3. Jon skips a second question, and it doesn't come back.

## Prerequisites (Jon, not the executor's)

- [ ] **Before Friday 2026-10-30:** rebuild the VF Listening Poller from `main` and install it on
  the mini ([poller setup](../listening/POLLER-SETUP.md)). `main` has M17 S2's New Music saving
  and S3's fix to the poller's build. Until then, no week is saved, and S2's gate can't start.
- [ ] **Install Vinyl Fever on the laptop from `main`** (`scripts/install-vinyl-fever`). The
  running build is from 2026-10-23, before M17 S2 and S3. Then refresh the snapshot once, so
  the curation log records the 10 Selections adds and Vinyl Fever Keepers.
- [ ] **Label "Vinyl Fever Keepers" `keepers`** in Settings → Taste → Playlist Roles… (Decision 6).
- [x] **After S1 merges: nothing to copy** (corrected 2026-10-25). The taste guidance reaches the
  chat through `vf-mcp`'s server instructions (jon-platform ADR-0007 D6). Settings' Project
  instructions are only the paste-format fallback, and S1 didn't change them. Install from
  `main`, then refresh the Vinyl Fever tools in the chat.
- [ ] M17 S3's gate is still owed: a Music Feedback note (the VF Note shortcut, renamed) in the
  car, read back word for word, then a playlist note.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Ledger folder | `Taste Intelligence/recommendations/` | Next to the other taste logs (M17 Decision 1). |
| Pass window | 14 days, M17's | One rule for every source. |
| Release-age bands | `new` Y and Y−1; `recent` Y−5 to Y−2; `catalog` older | New Music is almost all `new`; the first chat batch was all `recent` and `catalog`. |
| Minimum decided songs for a ratio | 10 per cell | With batches of about 15, a smaller cell's ratio is noise. |
| `recommendation_outcomes` default | 10 batches, at most 50 | Capped like every M12 result. |
| Weeks of picks before S3 is decided | about 4 finished weeks | Enough for the picked group to pass the minimum. |
| Open questions at most | 3 | Enough for the chat to wonder; few enough that nothing piles up. |
| Question expiry | 21 days | A question about this month's listening goes stale after a few weeks. |

## Out of scope — with destinations

- **`neglected_keepers`** (keepers missing from recent listening). → After about three months
  of listening log. The log began 2026-10-20.
- **`taste_evidence`**, one call combining every evidence source. → Only if the chat struggles to
  combine `check_tracks`, `taste_notes`, and `recommendation_outcomes`.
- **Backfilling the archived staged playlists.** → No (Decision 5). The first batch's result is
  recorded in M17's ledger.
- **Apple's recommendation groups** (albums, playlists, stations). → S3's decision. They aren't
  songs, so they'd be sources, not evidence.
- **Reading ratings through the API.** → When Favorite and Suggest Less are in regular use.
- **Matching by catalog ID.** → Still only if song-key misses show up (M17 Decision 4).
- **A "VF Questions" shortcut** that reads an open question aloud and takes a dictated answer,
  like Music Feedback. → After S4's gate, if the questions prove worth answering.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves them and sets
`NEXT_UP.md` to Dispatch 1.

1. **No head-to-head with New Music.**
   - The chat and New Music draw from different eras, and a chat model is weakest on recent
     releases (Jon, 2026-10-25). Outcomes are reported by source within release-age bands.
   - The chat is tested on new releases only through blind picks from New Music's own weeks.
   - This replaces the design's success sentence and its "baseline to beat". New Music's yield
     stays, as New Music's own number.
2. **The ledger is its own iCloud log, not the `PlaylistInbox/Processed` archive** the design
   named.
   - The archive is local to one Mac's Application Support.
   - Not every staged playlist is a discovery.
   - The taste logs live together, readable by `vf-mcp` without the app.
3. **Every staged playlist is logged, and familiarity decides what counts.** The Power Pop
   playlist of 2026-10-18 mixed 10 familiar songs with 5 finds. A per-song familiarity check
   handles that with nothing for the chat to remember.
4. **Familiarity is per song.** Knowing an artist doesn't make a song known (Jon, 2026-10-25,
   about the 15). `artistKnown` is recorded so the chat and the outcomes can tell the two apart.
5. **No backfill of the five archived staged playlists.** Familiarity at their staging time
   can't be reconstructed reliably, because the snapshot is overwritten at each refresh. The
   ledger starts with S1.
6. **"Vinyl Fever Keepers" is a `keepers` playlist.** It's where Jon put every keeper from the
   first batch, including the two with no Selections year. Kept means in any `keepers` playlist,
   which covers release-year Selections and Vinyl Fever Keepers.
7. **S3 is decided by S2's gate, not now.**

Added 2026-10-25 with S4. Merging that plan PR approves them.

8. **The chat can ask Jon what it wonders about (S4).** This is #127's Decision 8. #127 was
   superseded: its proposal outcomes became S1 and S2 here, and its notes shipped as M17 S3.
   - **The problem:** questions come up while the chat builds a list or reads outcomes, often
     when Jon isn't there, and nothing carries them to the next conversation.
   - **A question and its answer are notes**, kept verbatim like everything else Jon says, and a
     question's state is derived on read. There's no new file and no new store, and Vinyl Fever
     still makes no model calls.
   - **Limits keep it from becoming a chore:** at most 3 open questions, gone after 21 days, one
     asked per conversation, and a skip is final.
   - **The test for a question:** would the answer change what the chat recommends next? The
     useful questions come from contrasts in Jon's evidence ("you kept X but passed Y. Was it
     the vocals or the tempo?"), not survey questions.
   - **After S2,** because S2's gate depends on the calendar (picks before Jon hears each New
     Music week), and S4's doesn't.
9. **Kept stays "in a `keepers` playlist", not #127's wider rule.** #127 also counted songs
   filed in a `curated` or `situational` playlist. Every keeper from the first batch went into
   Vinyl Fever Keepers, and widening the rule would change New Music's existing numbers (S2
   keeps M17's classifier unchanged). Revisit only if Jon files finds straight into curated
   playlists.
