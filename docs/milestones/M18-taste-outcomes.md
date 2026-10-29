# Milestone 18 — Taste outcomes (what Jon keeps, by source)

*Measure what happens to the songs Jon is shown: which ones he keeps, from which source, and how
new they were. It builds on [M17](M17-taste-intelligence.md), whose shared rules still apply, and
on the design in [../taste-intelligence.md](../taste-intelligence.md). Where this doc and the
design conflict, this doc's Decisions win. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply.*

Summary: Seven slices are dispatched, and an eighth is decided at S2's gate.
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
- **S5** asks for a role whenever a playlist has none: a banner in the app, and Vinyl Fever's own
  playlists labeled automatically. An unlabeled playlist silently counts as "Jon knows these
  songs" and never as kept.
- **S6** puts the open questions where the chat already looks, in `list_playlists`, because at
  S4's gate the chat never asked one until Jon prompted it. It also stops the chat from staging a
  batch a second time to fix a year. Added 2026-10-28; it runs after S5.
- **S7** labels a staged batch's playlist `vinyl-fever` the moment Vinyl Fever creates it,
  instead of after iCloud syncs it back and the library snapshot is refreshed. Added 2026-10-29
  from S5's gate; it runs after S6.
- **S8** makes the tools enforce what S6 only asked for. `stage_playlist` requires a year on every
  song, and `check_tracks` also returns the open questions. At S6's gate the chat skipped both
  the years and the question. Added 2026-10-29; it runs after S7.

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
advances `NEXT_UP.md` to S4. **Dispatch 4: S5** (app; Jon's gate; added 2026-10-25). S4's
completing PR advances `NEXT_UP.md` to S5. **Dispatch 5: S6** (`vf-mcp`; Jon's gate; added
2026-10-28). S5's completing PR advances `NEXT_UP.md` to S6. **Dispatch 6: S7** (app + Core;
Jon's gate; added 2026-10-29). S6's completing PR advances `NEXT_UP.md` to S7. **Dispatch 7: S8**
(`vf-mcp`; Jon's gate; added 2026-10-29). S7's completing PR advances `NEXT_UP.md` to S8. S8's
completing PR advances `NEXT_UP.md` to [M20](M20-music-feedback-intent.md) · S0.

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
    - **Passed 2026-10-26.** The first real line is "2024 Selections: 15 New Discoveries",
      staged from ChatGPT.app's Codex at 00:15Z, on the build installed at 19:34 on 10-25 (after
      #132 merged), with the chat on the refreshed 14-tool list.
      - **All 15 songs are unfamiliar, and 7 have `artistKnown`.** The architect checked every
        song against the snapshot and the log:
        - none is owned or heard;
        - `artistKnown` matches library tracks or log plays for all 15;
        - Little Simz's "Gorilla" is only in "222.2022", a `followed` subscription playlist, so
          leaving it unfamiliar is right.
      - **`check_tracks`:** in the chat (Jon), and again through the installed helper (the
        architect), batch songs show `recommended: {count: 1}` at 00:15Z, and a song outside
        the batch shows none.
      - **The batch has no years.** That's why S2 now asks the chat for them (Decision 11).

- [x] **S2 — Outcomes by source and release age, the chat's New Music picks, the chat's
  reasoning, and the stick-rate fix (Core + `vf-mcp`).** *Amended 2026-10-25, before dispatch,
  from S1's first real batch: release years, the chat's reasoning (Decision 10), and coverage
  per batch (Decision 12).*
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
  - **Release years, always** (Decision 11). S1's first real batch ("2024 Selections: 15 New
    Discoveries") came with no `year` on any song, so its whole band would be `unknown`.
    - **Instructions:** when staging discoveries, give every song its original release year.
    - **`stage_playlist`'s result** lists the songs that came without a year (`missingYear`), so
      the chat can fix them and stage again.
    - **No catalog lookup.** `vf-mcp` has no Apple Music API access, so a missing year stays
      `unknown`.
  - **The chat's reasoning, recorded and checked** (Decision 10). `stage_playlist` gains optional
    fields that go only into the ledger, never into the `.vfplaylist`. The paste contract and
    `PlaylistContract.trackRules` don't change.
    - **On the batch:** `request`, Jon's ask as the chat received it, word for word (at most 500
      characters).
    - **On each song:**
      - `why`, the chat's one-sentence reason (at most 300 characters);
      - `like`, at most 3 songs it's explained against, each an `artist` and `title`, plus an
        optional `from` (the playlist name it cites).
    - **References are checked at staging.** Each `like` is recorded with `found`:
      - `playlist` when `from` names a playlist that contains the song;
      - `library` when the song is in the library, but not in the cited playlist, or there's
        no `from`;
      - `none` otherwise.

      A wrong reference is recorded, never refused: a ledger problem never fails staging.
    - **Longer text is truncated,** and the result says so.
    - **`stage_playlist`'s result** lists `unverifiedReferences`: every `like` whose `found`
      isn't what was claimed. Then the chat can correct its explanation to Jon right away.
    - **Outcomes:** `recommendation_outcomes` shows each song's `why` and `like` beside its
      class, so the chat can see which kinds of reasons led to keeps. `check_tracks`'s
      `recommended` shows the latest `why`.
    - **Instructions:** when staging discoveries, pass Jon's request as `request`, and for each
      song a one-sentence `why` and the songs it's `like`. Cite only songs you've read from a
      Vinyl Fever tool in this conversation, and name the playlist you read them from.
  - **Coverage on every batch** (Decision 12; it resolves the question deferred from the #132
    review). Each new batch records what S1's familiarity check could read:
    `"coverage":{"listening":true,"notes":true,"snapshotAt":"…"}`. In `recommendation_outcomes`,
    a batch staged without listening evidence is listed, but it's left out of every ratio,
    marked `notScored: "no listening evidence at staging"`. Batches from before this field
    count as covered.
  - **The ledger stays `vf-recommendation-batch` v1.** Every new field is optional, so S1's lines
    and older readers keep working.
  - **`check_tracks`'s `recommended`** gains the latest outcome.

  **DoD:**
  - **Core tests:**
    - the shared classifier gives S2's existing answers, plus ledger batches with familiar songs
      not counted;
    - each band boundary, and `unknown`;
    - the small-cell rule (counts and no ratio);
    - picks validation, `heardBeforePick` left out, and the picked-versus-rest counts on a fixture
      week;
    - the stick-rate exclusion on a fixture curation log with a late add;
    - reference checking: `found` is `playlist`, `library`, and `none`, including a `from` that
      names a playlist that doesn't contain the song;
    - truncation of `request` and `why`;
    - a batch without listening coverage is listed but not scored;
    - S1's v1 lines, with none of the new fields, read unchanged.
  - **`vf-mcp` tests:**
    - golden JSON for both tools, with no IDs or paths;
    - `stage_playlist` with `request`, `why`, and `like` writes them to the ledger and not to the
      `.vfplaylist`;
    - its result lists `missingYear` and `unverifiedReferences`.
  - **Executor's laptop check:** `recommendation_outcomes` against the real data shows Jon's S1
    gate batch ("2024 Selections: 15 New Discoveries"), pending or classified, banded
    `unknown`, with no reasoning. Report it.
  - **Jon's gate (owed until two weeks finish):** for two New Music weeks, ask the chat on the
    Friday to pick the songs he'll keep before listening. After each week's 14 days, read
    `taste_baselines`, and say whether the picked-versus-rest result matches what happened. That
    result decides S3.
    - Also, stage one discovery batch: the ledger line carries `request`, a `why` per song, and
      `like` references, and every year. If any reference comes back unverified, the chat said
      so when it staged.
      - **Staging part passed 2026-10-28, except one year.** "2023 Selections: 15 New
        Discoveries" was staged at 19:42:02Z from ChatGPT on the iPad. The build was installed
        at 08:52 local, after #144 merged, and the connector's `vf-mcp` started at 08:52:52.
        - **What the ledger line carries:**
          - `request`, word for word;
          - a `why` on all 15 songs;
          - two `like` references each, all `found: library`. The chat sent no `from`, so no
            reference names a playlist, and none came back unverified;
          - a year on 14 of 15. Fickle Friends' "Swim" has none.
        - **The missing year went unmentioned.** The result listed "Swim" in `missingYear`, but
          the chat neither fixed it nor told Jon. Its reply showed no years or reasons at all,
          although both were staged.
        - **All 15 songs were new to Jon,** and Jon confirms it. Each is recorded unfamiliar
          with no reasons. The architect also checked each song:
          - none was in the 12:54Z snapshot (87,091 tracks) or the 2024 batch;
          - none was played before staging. The first plays are in the mini's 20:02Z fetch.
        - **The S2 brief's "fix them and stage again" is a trap.** A second staging marks every
          song `recommended`, so none of them would count as an outcome. S6 changes the
          instructions (Decision 15).

- [ ] **S3 — Apple's candidates for new releases (decided at S2's gate; not dispatched).**
  - **If the chat's picks beat the rest of the week** over about four finished weeks: give the
    chat Apple's recent releases to judge, as candidates. S0 found that the similar-artists view
    of artists Jon keeps returns 10 per page and makes sense. New releases by those artists would
    need a `latest-release` view, which is unverified, so the architect probes it first. The
    chat ranks and explains, and the ledger records `source: "apple-similar-artists"`.
  - **If not:** the chat stays on catalog depth, and New Music stays Apple's job, unfiltered.
  - Either way, the result is recorded here before anything is built.

- [x] **S4 — The chat's questions (Core + `vf-mcp`).** *Added 2026-10-25 from plan PR #127,
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
    - **First run, 2026-10-28: step 1 passed; steps 2 and 3 move to S6's gate.** It ran on the
      same build and conversation surface as S2's staging check above.
      - **Step 1 passed.** While staging the 2023 batch, the chat recorded two questions at
        19:41Z. Each has `about` and cites a contrast in Jon's evidence:
        - pop-punk in his 2023 Selections: a main lane, or an accent?
        - soft, hazy vocals: enjoyed, or tolerated? It set NewDad and Soft Science against Jon's
          own Music Feedback on Pixey's "Million Dollar Baby" that morning.
      - **Step 2: the chat didn't ask until Jon prompted it.** It never saw the questions:
        `openQuestions` comes back only from `taste_notes`, and the instructions start a taste
        conversation with `list_playlists`. Once prompted, it asked both. Jon's two answers
        were recorded at 20:28Z, word for word and each linked to its question, and
        `openQuestions` is now empty.
      - **Step 3 wasn't run.** Jon answered both questions, so none was left to skip.
      - S6 fixes step 2, and its gate re-runs steps 2 and 3.

- [x] **S5 — Every playlist gets a role (app + Core).** Done in `m18/s5-playlist-roles`. *Added 2026-10-25. Vinyl Fever Keepers sat
  unlabeled for a day after Jon made it, so nothing filed there counted as kept. The only signal
  was a count in Settings → Taste. See Decision 13.*
  - **The banner.** After every snapshot load or refresh in the `.live` app, check for playlists
    with no role, of any kind: user, smart, or subscription. An unlabeled subscription playlist
    counts as familiarity just as a user playlist does.
    - If there are any, the main window shows a banner above its content: "1 playlist has no
      role: Vinyl Fever Keepers". With more than 3, name the newest 3 and add "and N more".
    - **Label…** opens Settings → Taste → Playlist Roles…, filtered to Unlabeled, with
      suggestions already filled in for unlabeled rows. Nothing is saved until Jon saves.
    - **Not now** hides the banner until a playlist that wasn't unlabeled at that moment
      appears. The dismissed set is kept per Mac (`UserDefaults`, through a dependency).
    - Never a modal alert, and never at launch before the snapshot has loaded.
  - **Vinyl Fever's own playlists label themselves.** At the same check, an unlabeled playlist
    whose suggestion is `vinyl-fever` gets the `vinyl-fever` role, saved through
    `PlaylistRolesStore`. Today `PlaylistRoleSuggestion` only suggests it, for a name that
    matches an archived `PlaylistInbox/Processed` request.
    - Also count as Vinyl Fever's a playlist whose name matches a batch's `playlist` in the
      recommendation ledger, so a playlist created on the other Mac is recognized too.
    - Only `vinyl-fever` is applied automatically. Every other suggestion waits for Jon.
    - Never change a playlist that already has a role.
    - Report each automatic label once, in the banner's place: "Labeled 1 Vinyl Fever playlist
      `vinyl-fever`: 2024 Selections: 15 New Discoveries".
  - **The Settings → Taste summary line stays.**

  **DoD:**
  - **Core tests:** the unlabeled check covers every kind; the automatic labels apply only to
    `vinyl-fever` suggestions (from the archive and from the ledger), never overwrite a role, and
    write once.
  - **App tests:**
    - the banner model's states: none, some, more than 3, dismissed, and a new unlabeled
      playlist after a dismissal;
    - **Label…** opens the sheet filtered to Unlabeled;
    - nothing runs, and nothing is written, outside `.live` (in-memory stores in tests).
  - **Jon's gate (after install, owed until done):**
    1. Create a playlist from a staged batch. After the next refresh, it has the `vinyl-fever`
       role, with no action from Jon, and the one-time note says so.
    2. Make an ordinary playlist in Music. After a refresh, the banner names it. **Not now**
       hides the banner, and **Label…** opens the sheet filtered to Unlabeled.
  - **Gate record.** Passed on 2026-10-29: step 1 in the morning, step 2 in the afternoon.
    - **Step 1.** The chat staged "Sam Fender — Manchester 2027 Catch-Up", and Jon created it
      from the inbox at 09:53 EDT. It reached Music on the laptop only after iCloud synced it.
      After a manual Refresh Library Snapshot, the green note appeared. The roles file
      (`updatedAt` 15:42:43Z) has the playlist's Music ID, `13BDBBB374564174`, with
      `vinyl-fever`.
    - **What it showed.** Waiting for iCloud and then refreshing, just to label a playlist
      Vinyl Fever had made a minute earlier, is awkward. S7 labels it at creation instead.

- [x] **S6 — The chat finds its open questions (`vf-mcp`).** Done in `m18/s6-open-questions`. *Added 2026-10-28 from S4's and
  S2's gates. See Decisions 14 and 15.*
  - **`list_playlists` carries `openQuestions`.**
    - The entries are the same as `taste_notes`' (`id`, text, `about`, and age), from
      `TasteNotesCodec.openQuestions`: at most 3.
    - The key is left out when there are none.
    - When the notes can't be read, it's left out with no error, as `check_tracks` does, and the
      playlists still come back.
    - Read the notes once per call.
  - **Instructions.** In the taste paragraph:
    - Replace S4's question sentence with: `list_playlists` returns `openQuestions` when there
      are any. In a taste conversation, ask at most one without waiting to be asked, and only
      when it bears on what Jon is doing. Record his reply word for word as `note` with the
      question's id in `answers`. Record "skip" or "not now" the same way, with `skipped: true`.
    - Add: when you stage, show Jon each song's year and why. If the result lists `missingYear`
      or `unverifiedReferences`, tell Jon which songs. Don't stage the same batch again: a
      second staging marks every song as recommended before (Decision 15).

    The first 512 characters must still stand alone. Update the instructions snapshot test.
  - **`stage_playlist`'s description** says not to stage a batch again to fix a year.
  - **Nothing else changes.** The note format, the question rules, and `taste_notes` stay as S4
    shipped them.

  **DoD:**
  - **`vf-mcp` tests:**
    - golden JSON for `list_playlists` with one open question; with none (the key is left out,
      and the rest of the output is unchanged); and with unreadable notes (no key and no
      error);
    - an answered or skipped question isn't in `list_playlists`' `openQuestions`;
    - the instructions snapshot has the new sentences, and the head still stands alone;
    - `stage_playlist`'s description has the warning against staging again.
  - **Executor's laptop check** (read-only, against a copy of Jon's live notes):
    `list_playlists` shows no `openQuestions`, because both of S4's questions are answered.
  - **Jon's gate (after install, owed until done).** It replaces S4's steps 2 and 3:
    1. While building a list, the chat records up to two questions.
    2. In a new conversation, Jon makes an ordinary taste request about the same area. The chat
       asks one question without being prompted. Jon answers, and `taste_notes` shows his words
       word for word.
    3. In another new conversation, the chat asks the other question, and Jon says "not now".
       In a third new conversation, the chat doesn't ask it, and `taste_notes` shows it
       skipped.
    4. When the chat stages a batch, its reply shows each song's year and why. If the result
       lists a missing year, the chat names the song.
  - **Gate record, 2026-10-29.** Step 1 passed, steps 2 and 4 failed, and step 3 wasn't run.
    Steps 2–4 move to S8's gate. The connector served build `2258e44`, which matches `main` at
    `0f8d7a0`, from 13:15 EDT.
    - **Step 4 failed.** The chat staged "Soft Vocals: Where's the Edge?" at 17:26Z: 12 songs,
      each with a why and none with a year. The result listed all 12 under `missingYear`, and
      the chat didn't tell Jon. Asked why, it pointed to the track rules: "album and year are
      optional hints". `stage_playlist`'s schema also leaves `year` optional and undescribed.
      Those outweighed the taste paragraph's "Give every discovery its original release year".
      The batch was never created, and per Decision 15 it isn't staged again.
    - **Step 1 passed.** At 17:38Z, when Jon asked, the chat recorded two questions about the
      Soft Vocals batch: what makes a soft vocal a warning sign, and what lets one work. The
      chat recorded nothing on its own while building the list. Recording on request is
      allowed here, because this step doesn't test whether the chat asks.
    - **Step 2 failed.** In a new conversation, Jon asked "Can you give me a few more soft vocal
      tracks". The chat gave six songs with years and reasons, but it didn't ask either
      question.
      - The installed `vf-mcp`, probed read-only, returned both questions from
        `list_playlists`, and its instructions had S6's sentences.
      - The chat's reply cited only `check_tracks` evidence. Most likely it never called
        `list_playlists`, because the request didn't read as a taste question.
    - **Step 3 wasn't run.** Both questions stay open for S8's gate. They expire on
      2026-11-19.

- [x] **S7 — Vinyl Fever labels its playlists when it creates them (app + Core).** Done in
  `m18/s7-label-at-create`. *Added
  2026-10-29 from S5's gate. See Decision 17.*
  - **At Create.** When Create succeeds for a playlist opened from the inbox, Vinyl Fever adds
    a `vinyl-fever` entry to the roles file at once, through `PlaylistRolesStore`.
    - **The entry is keyed by name.** The Apple Music API's ID isn't the ID Music.app uses on
      the Mac. `PlaylistRoleMatcher.resolve` already matches by name when the name is unique in
      the library, and `vf-mcp` uses the same matcher. So the playlist arrives labeled whenever
      it syncs, on either Mac.
    - **The entry gains an optional `pendingSince` (ISO 8601).** It's still `vf-playlist-roles`
      v1: the key is additive, and older builds ignore it. `persistentID` holds the
      `CreatedPlaylistRef` ID until the playlist is adopted.
    - **The note is shown on Create:** "Created and labeled `vinyl-fever`." It appears in the
      Playlists view's post-create status, not the banner.
    - **If the roles write fails,** the playlist is still created. Show "Playlist created, but
      its role couldn't be saved: <error>. It will be labeled when it syncs." S5's automatic
      label still covers it, because the inbox item is in `Processed`.
    - **A playlist built from pasted text gets no entry,** as today. S7 changes *when* Vinyl
      Fever's playlists are labeled, not *which* playlists.
  - **Adoption.** At S5's snapshot check, a pending entry adopts a snapshot playlist with the same
    name only when exactly one matching playlist has a `persistentID` no other role entry holds.
    The pending entry's `pendingSince` is removed. Adoption is silent: it's not a new label, so
    S5's note doesn't appear. Write once, and only when something changed. With two unheld
    playlists of the same name, the entry stays pending. Process entries in order and reserve each
    adopted ID so two pending entries cannot adopt one playlist.
  - **Settings → Playlist Roles.** Under the Missing filter, a pending entry reads "Waiting for
    sync since <date>" instead of "Missing". Nothing expires it, and Jon can remove it as he
    would a missing one.
  - **S5's automatic labeling stays** as the fallback for playlists created on the other Mac or
    before S7.

  **DoD:**
  - **Core tests:**
    - the codec round-trips `pendingSince` and decodes a file without it;
    - before adoption, `resolve` gives the synced playlist `vinyl-fever` by name;
    - adoption with a unique unheld name sets the Music ID and removes `pendingSince`; a held
      playlist, two unheld same-name playlists, or no pending entries changes nothing and reports
      no write; with two pending entries and one matching playlist, exactly one adopts;
    - `missing` leaves out pending entries, and a new `pending` lists them.
  - **App tests** (in-memory stores):
    - Create from an inbox item writes one pending `vinyl-fever` entry, with `pendingSince` set
      to the injected now, and shows the note;
    - Create from pasted text writes nothing;
    - a failed roles write leaves the playlist created and shows the message;
    - a snapshot containing the playlist adopts it once, with no S5 note and no banner.
  - **Jon's gate (after install, owed until done):**
    1. Stage a batch and create it. The note says it's labeled at once, and Playlist Roles shows
       it as waiting for sync.
    2. After it syncs and the snapshot refreshes, it's listed with `vinyl-fever`, with no
       banner and no S5 note. The roles file has its Music ID and no `pendingSince`.

- [x] **S8 — The tools enforce the year and carry the questions (`vf-mcp`).** *Added 2026-10-29
  from S6's gate. See Decision 18.*
  - **`stage_playlist` requires a year.**
    - In the input schema, `year` is in each track's `required` list, with type
      `["integer", "null"]`. Its description reads: "The song's original release year, not a
      reissue's or compilation's. Use null only when you can't verify it."
    - **Refuse before writing anything.** If any track has no `year` key, return a tool error
      naming every such song. Write no inbox file and no ledger batch. Because nothing was
      recorded, sending the list again with years isn't a second staging (Decision 15).
    - `null` is accepted. The song is staged with no year, and `missingYear` lists it as today.
    - **The paste path doesn't change.** A list pasted into the app still treats `year` as
      optional. The requirement is in `stage_playlist`'s handling, not in
      `PlaylistContract`'s decoder.
  - **`check_tracks` carries `openQuestions`,** exactly as `list_playlists` does since S6: the
    same projection, at most 3, left out when there are none or the notes can't be read, and the
    notes read once per call. The instructions require `check_tracks` before every list, so the
    chat sees the questions on any music request, however it's worded.
  - **Wording.**
    - In the track rules (`PlaylistContract.trackRules`), replace "album and year are optional
      hints, and year means the original release year" with: "album is an optional hint. year
      is the original release year: `stage_playlist` requires it on every track, with null
      when you can't verify it."
    - In the taste paragraph, "`list_playlists` returns `openQuestions` when there are any"
      becomes "`list_playlists` and `check_tracks` return `openQuestions` when there are any".
    - The first 512 characters must still stand alone. Update the instructions snapshot test.
  - **Nothing else changes.** The ledger format, `missingYear`, and the question rules stay as
    they are.

  **DoD:**
  - **`vf-mcp` tests:**
    - A track without `year` is refused, the error names it, and the inbox and the
      recommendation folder stay empty.
    - A track with `year: null` is staged and listed in `missingYear`.
    - The schema lists `year` as required, with type `["integer", "null"]`.
    - Golden JSON for `check_tracks`: with one open question; with none (the key is left out and
      the rest of the output is unchanged); and with unreadable notes (no key and no error).
    - The instructions snapshot and the track rules have the new wording.
    - A pasted list without years still decodes, as an existing test or a new one.
  - **Executor's laptop check** (read-only, against copies of Jon's live notes and snapshot):
    `check_tracks` on any song shows the two open soft-vocal questions.
  - **Jon's gate (after install, owed until done).** It replaces S6's steps 2–4:
    1. With the two soft-vocal questions still open, start a new conversation with an ordinary
       music request. The chat asks one question without being prompted. Jon answers, and
       `taste_notes` shows his words verbatim.
    2. In another new conversation, the chat asks the other question, and Jon says "not now".
       In a third new conversation, it doesn't ask it, and `taste_notes` shows it skipped.
    3. When the chat stages a batch, every song in the ledger has a year, or the chat named the
       songs it couldn't verify.

## Prerequisites (Jon, not the executor's)

- [x] **Before Friday 2026-10-30:** rebuild the VF Listening Poller from `main` and install it on
  the mini. *Done 2026-10-25. Its first run saved the week of 2026-10-23 (25 songs, all 2026, each
  with a catalog ID) to `exposure/Jon_s_Mac_mini__2_.jsonl`.* ([poller setup](../listening/POLLER-SETUP.md)). `main` has M17 S2's New Music saving
  and S3's fix to the poller's build. Until then, no week is saved, and S2's gate can't start.
- [x] **Install Vinyl Fever on the laptop from `main`** (`scripts/install-vinyl-fever`). *Done
  2026-10-25 at 19:34. The refresh at 23:30Z recorded the Selections adds and Vinyl Fever
  Keepers in the curation log.* The
  running build is from 2026-10-23, before M17 S2 and S3. Then refresh the snapshot once, so
  the curation log records the 10 Selections adds and Vinyl Fever Keepers.
- [x] **Label "Vinyl Fever Keepers" `keepers`** in Settings → Taste → Playlist Roles… (Decision 6).
  *Done 2026-10-26T00:25Z. The only unlabeled playlist left is the staged "2025 Selections: 15
  New Discoveries".*
- [x] **After S1 merges: nothing to copy** (corrected 2026-10-25). The taste guidance reaches the
  chat through `vf-mcp`'s server instructions (jon-platform ADR-0007 D6). Settings' Project
  instructions are only the paste-format fallback, and S1 didn't change them. Install from
  `main`, then refresh the Vinyl Fever tools in the chat.
- [ ] M17 S3's gate is still owed: a Music Feedback note (the VF Note shortcut, renamed) in the
  car, read back word for word, then a playlist note.
- [ ] **Stop Music Feedback writing empty lines** (Decision 16). In the shortcut, after the
  dictation, stop without writing when the text is empty or is "Cancel". The reader already
  skips lines with no text: there were 3 by 2026-10-28, one of them that day. A "Cancel" line
  shows up as a note.

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

Added 2026-10-25 to S2, before dispatch. Merging that plan PR approves them.

10. **Record the chat's reasoning word for word, and check its references** (Jon, 2026-10-25).
    - The reason the chat gives for a song is the hypothesis, and the outcome tests it. Without
      the reason, S2 can say which songs Jon kept, but not which kinds of reasons hold up.
    - The 2025 batch showed the risk: the chat explained its picks against Selections it
      couldn't read (M17 S1, Correction). Checking each cited song at staging catches that
      while Jon is still in the conversation.
    - It's the chat's text, stored like Jon's notes. Vinyl Fever still makes no model calls and
      stores no scores.
11. **The chat sends the year. Vinyl Fever doesn't look it up.** `vf-mcp` has no catalog access.
    A result that names the missing years makes the chat fix them while it can.
12. **Each batch records its coverage, and an uncovered batch isn't scored.** A song recorded as
    new only because the listening log couldn't be read would be a false discovery,
    permanently. Listing such a batch without scoring it keeps the record honest.
13. **A playlist with no role asks for one, and Vinyl Fever labels its own** (S5, Jon,
    2026-10-25).
    - **Why it matters:** an unlabeled playlist isn't neutral. Its songs count as familiar
      (`playlist:unlabeled`), and nothing in it counts as kept.
    - **A banner, not a pop-up:** a modal at every launch gets dismissed without being read.
    - **Only `vinyl-fever` is applied automatically,** because only that one is certain: Vinyl
      Fever made the playlist. Every other role is Jon's judgment.

Added 2026-10-28 with S6. Merging that plan PR approves them.

14. **Open questions travel with `list_playlists`,** not with an extra call. The instructions
    already start every taste conversation there. At S4's gate, the chat never called
    `taste_notes` on its own, so it never saw a question until Jon asked for one. Telling it to
    call `taste_notes` first would cost a call and up to 50 notes on every conversation, and it
    would still depend on the chat remembering to make the call.
15. **A batch is staged once. A missing year stays `unknown`.** This corrects S2's "so the chat
    can fix them and stage again":
    - a second staging is a second ledger batch, and S1's familiarity then marks every song
      `recommended`, so none of them counts as an outcome;
    - a single `unknown` year costs one song's band, which is far cheaper;
    - the chat names a missing year to Jon instead.

    Decision 11 still stands: the chat sends the year, and Vinyl Fever doesn't look it up.
16. **The note files aren't edited by hand.** The fix for empty lines belongs in the Music
    Feedback shortcut.
    - **The files are live.** `notes.jsonl` is appended to from Jon's iPhone and iPad. An edit
      from the Mac while a device writes can leave a conflict copy or lose a line.
    - **Empty lines are already harmless.** The reader skips them, and coverage only counts
      them.
    - **Two setup-day lines from 2026-10-22 stay:** "Cancel" and "This is just a test". The
      alternative is to remove them once, after a backup, with no device writing; Jon decides
      at merge.

Added 2026-10-29 with S7. Merging that plan PR approves it.

17. **Vinyl Fever labels a playlist when it creates it, keyed by name until the playlist syncs**
    (S7, Jon, 2026-10-29).
    - **Why:** at S5's gate, a playlist Vinyl Fever had just made needed an iCloud sync and a
      manual refresh before it got its role. Vinyl Fever knew both facts, that the playlist is
      its own and what it's called, at Create.
    - **Name is the bridge.** The API's ID can't be matched to Music.app's, and name matching
      already exists for exactly this reason. Adoption then stores the real ID, so a later
      rename keeps the role.
    - **Same scope as S5.** Only playlists created from the inbox. A playlist built from pasted
      text is Jon's own list and keeps waiting for his role.

Added 2026-10-29 with S8. Merging that plan PR approves it.

18. **What must happen is enforced by a tool, and what the chat must see comes back from the
    calls it already makes** (S8, Jon, 2026-10-29).
    - **Why:** at S6's gate, the chat followed the looser of two conflicting rules about the
      year, and it ignored `missingYear` in the result. It also skipped `list_playlists` for a
      request that didn't read as a taste question. Sentences in the instructions aren't
      reliable enough on their own.
    - **The year is refused, not just reported.** A refusal writes nothing, so the chat can
      resend the list with years without making a second batch. Decision 15 still applies to a
      batch that was recorded.
    - **`check_tracks` is the call the chat can't skip.** The instructions require it before
      every list. Up to three questions add little to each result, so this keeps Decision 14's
      reasoning: the questions travel with a call the chat is already making.
