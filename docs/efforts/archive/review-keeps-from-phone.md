# Effort — Reviews count the keeps Jon saw

**Status:** Dispatched
**Summary:** The chat's playlist review read keeps from the Mac's library snapshot, which was two
days stale, and told Jon he kept nothing from *Pop with Bite* when he had. Record the phone's
live outcomes in the `finished` line, merge them with the Mac's in `playlist_reviews`, and let
Jon ask for a fresh review from the phone. Also lead the `vf-mcp` instructions with the
taste-statement rule, which a Work chat could quote but didn't act on (M23 S1's gate), and have
the chat study recent outcomes before it chooses songs. And let Jon react to a whole playlist,
in his own words, from the phone.
**Related:** [M23](../../milestones/archive/M23-done-listening.md) (S1, S2, S3 gate results) · [Efforts index](../README.md)

Branch `effort/review-keeps-from-phone`, from a fresh `main`. One PR. No schema change and no
sync change. The log format keeps `version: 1` (Decision 1).

## Why

M23's gates ran on 2026-11-02, and every step worked:
- Jon tapped Done listening on *Pop with Bite* (15:57).
- The line reached the Mac through iCloud (16:03).
- ChatGPT's 15-minute Work-chat monitor reviewed it and recorded the review (16:09).
- The review showed on the phone.

The review was still wrong. It said "12 of 12 passed and no keepers", but Jon had kept songs.

- `playlist_reviews` and `record_playlist_review` work out keeps from the Mac's library
  snapshot (`PlaylistRoleMatcher` over `library-snapshot.json`).
- That snapshot was written on 2026-10-31 at 09:07. The Mac app refreshes it only at launch,
  when it's stale, or from **Refresh Library Snapshot**, and the app wasn't running.
- The phone reads keeper playlists live through MusicKit, so its bar showed the keeps.

The monitor runs whether or not the Mac app is open, so most reviews would miss keeps from the
same day. At the moment Jon taps Done listening, the phone holds the outcomes he has just seen.
That's the evidence to record.

**M23 S1's gate failed the same afternoon.**
- In a new Work chat, Jon wrote two unprompted reactions: Mimi Webb's "Red Flags" and Foxes'
  "Sister Ray". The chat answered them, but never called `record_taste_note`, and nothing was
  saved.
- Asked to quote Vinyl Fever's instructions on taste statements, it quoted the S1 rule exactly,
  then saved both reactions. So the rule reaches the model through Codex.
- The rule sits mid-way through a roughly 400-word paragraph, after the playlist and staging
  rules. It asks for an unprompted call with a side effect, which a model skips unless the
  trigger is prominent.

## Changes

- **The `finished` line carries the phone's outcomes** (`VinylFeverNotes`).
  - `PlaylistReviewEntry` gains optional `songs`. Each item has:
    - `index`: the song's position in the batch, which is the last part of the shelf song id;
    - `title` and `artist`, for people;
    - `status`: `kept`, `passed`, or `unheard`;
    - `keptIn`: the keeper playlist names, when kept.
  - It also gains the optional `heard`, `kept`, `passed`, and `unheard` counts that `review` lines
    already have.
  - Only `finished` lines from the phone carry them. `isValid` accepts a `finished` line with or
    without them.
- **The phone writes them** (`PlaylistReviewsModel.finish`).
  - It takes the playlist's `PlaylistProgressResult` from `PlaylistProgressModel.results`, as
    shown on the detail page at the tap.
  - Without a result (no Music access, or the listening log unreadable), it writes the line
    without them, as today.
- **`playlist_reviews` and `record_playlist_review` merge the two sources** (`vf-mcp`).
  - A song's status is the stronger of the phone's at finish and the Mac's now:
    `kept` > `passed` > `unheard`.
  - So a stale snapshot can't hide a keep, and a keep made after finishing still counts.
  - Counts come from the merged statuses, and `record_playlist_review` stores those.
  - Each candidate adds `outcomeSource` (`phone and mac`, or `mac` when the line has no `songs`)
    and `snapshotTakenAt`.
- **A finish after a review asks for a new one.**
  - A playlist is waiting when its latest Jon line is `finished` and no review is newer than that
    line. Today it's "no review at all". Apply this in `playlist_reviews` and in the phone's
    waiting state.
  - On the detail page, **Not done** also shows under an existing review. **Done listening**
    returns after a reopen, as it does today.
  - That gives Jon a way to ask for a fresh review from the phone. Readers already show the latest
    review.
- **Instructions:** when `outcomeSource` is `mac` and `snapshotTakenAt` is older than the
  playlist's finish, say in the review that keeps since the snapshot may be missing.

- **Lead with the taste-statement rule** (`LibraryMCPServer`).
  - Move it out of the long paragraph into `instructionHead`, as its second sentence:
    "Whenever Jon reacts to a song, artist, or playlist, states a preference, or explains a keep
    or a pass, call `record_taste_note` with his words word for word before you reply, then say
    briefly that it's saved so he can say 'don't'."
  - The don't-record list (the chat's own words or a paraphrase, a playlist request, small talk,
    the same words twice) stays, right after it.
  - Begin `record_taste_note`'s description with the trigger: "Call this whenever Jon reacts to
    a song, artist, or playlist, states a preference, or explains a keep or a pass: record his
    words verbatim, …". Keep the rest of the description.
  - Update the S1 assertions in `LibraryMCPServerTests` and the strings `scripts/mcp-smoke`
    checks to the new wording.

- **Study outcomes before choosing songs** (`LibraryMCPServer.instructions`).
  - Today only New Music picks point the chat at outcomes. Playlist building sees a past
    outcome only when `check_tracks` happens to meet a song recommended before.
  - Add, right after "For taste questions, start with list_playlists.": "Before choosing songs
    for a new playlist, read `recommendation_outcomes` and `taste_notes`, and learn from what
    Jon passed as well as what he kept, and from his notes on both."

- **Jon's reaction to a playlist, from the phone** (`VinylFeverMobile`).
  - **Why:** the monitor writes reviews while Jon is away, so he first reads them on the phone.
    The phone saves notes on individual songs only, so there's nowhere to react to a playlist
    as a whole.
  - **The control:** a labeled **Your reaction** button on the playlist detail, under the chat's
    review, or under "Done · waiting for the chat's review" when no review exists yet. Place it
    per `ui-and-platforms.md` § Controls. It opens the same note sheet as a song note.
  - **The note:** make it with `MusicFeedback.makeNote(_:selected: nil, source: "playlist", …)`,
    then set `playlist` to the batch's playlist name and `about.playlists` to `[name]`. Save it
    through the existing feedback-note client, to `notes-feedback-<device>.jsonl`. No format
    change: `TasteNote` already carries both fields.
  - **Showing it:** the detail page lists the playlist's notes (no title, `playlist` matching)
    under **Your reaction**, in Jon's type (M22 S1: serif italic with a leading rule), apart
    from the review's type. Song rows don't show them, and they don't change any song's
    passed-with-feedback status.
  - **Where it's read:** `playlist_reviews`' `jonNotes` (already matches `playlist`),
    `taste_notes` with `playlist`, and the new before-choosing rule. The chat's review stays the
    chat's words (M22 S4).

## Decisions

1. **`version` stays 1.** The new fields are optional, and current readers ignore keys they don't
   know (`JSONDecoder`). A version bump would make the installed phone and helper skip every
   new `finished` line, so a finished playlist would read as not finished.
2. **Merge; don't replace.** The phone's outcomes are a record of the tap, and the Mac's are
   current. Taking the stronger status per song is right whichever one is stale.
3. **The phone's words aren't the chat's.** The new fields are Jon's evidence, with
   `source: jon`. The review text stays the chat's (M22 S4).

## Done when

- **`VinylFeverNotes` tests:**
  - a `finished` line with `songs` and counts round-trips;
  - a `finished` line without them still decodes;
  - a `finished` line with `songs` passes `isValid`.
- **Phone model tests** (injected folder and clock):
  - finishing with a progress result writes each song's status and the counts;
  - finishing without one writes the line without them;
  - after a review, reopening then finishing shows the waiting state again;
  - saving a playlist reaction writes a note with no title, with `playlist` and `about.playlists`
    set to the playlist's name and `source: "playlist"`, and it appears under **Your reaction**,
    not on any song.
- **MCP tests** (fixture folder):
  - the snapshot has no keeper, but the `finished` line has the song `kept`: the candidate shows
    it `kept`, with `kept: 1` and `outcomeSource: "phone and mac"`;
  - the `finished` line has no `songs`: the candidate falls back to the Mac, with
    `snapshotTakenAt`;
  - a `finished` newer than the latest review is waiting again;
  - `record_playlist_review` stores the merged counts;
  - a playlist-level feedback note appears in that playlist's `jonNotes`, and `taste_notes` with
    `playlist` returns it.
- **Instruction test:**
  - `instructionHead` contains the taste-statement rule;
  - `record_taste_note`'s description begins with "Call this whenever Jon reacts";
  - `instructions` contains the "Before choosing songs for a new playlist" rule;
  - `scripts/mcp-smoke` passes against the built helper.
- Closeout (ADR-0005 D16) records two gates.

  **The keeps.** Jon:
  - keeps a song from a staged playlist on the phone;
  - taps Done listening without opening Vinyl Fever on the Mac;
  - sees the monitor's review count that keep.

  Then, on *Pop with Bite*, he taps **Not done**, then **Done listening**, and the new review
  counts his keeps. Under that review he taps **Your reaction** and saves a sentence. It shows
  under **Your reaction** on the phone, and a new chat finds it with `taste_notes` for *Pop
  with Bite*.

  **Unprompted saves, replacing M23 S1's gate.** After the install, Jon quits and reopens
  ChatGPT, then makes two unprompted taste statements in a new Work chat. Both land word for word
  in `notes-chat-<host>.jsonl`, and the chat says each is saved, without being asked.

## Out of scope

- **The Mac snapshot's own staleness** for `kept_and_passed`, `recommendation_outcomes`, and
  `list_playlists`. Those tools report the snapshot's age through `library_overview`. A
  scheduled refresh is a Mac-app change; plan it if the chat's other answers show the same gap.
- **The monitor's 15-minute polling cost.** Jon sets the interval on the monitor in ChatGPT; no
  code is needed.
