# Effort — Say you've finished this week's New Music

Status: Ready
Summary: Jon tells the chat he's finished a New Music week, and it's recorded through the existing `playlist-reviews` log. Unkept songs then count as passed as soon as a library snapshot newer than that statement exists, the Mac app refreshes one on request, and the 14-day rule stays for weeks nobody finishes.

Related: [M18](../milestones/M18-taste-outcomes.md) ·
[M23](../milestones/archive/M23-done-listening.md) ·
[review-keeps-from-phone](archive/review-keeps-from-phone.md) · [Efforts index](README.md)

Branch `effort/finish-new-music-week`, from a fresh `main`. One PR. No schema change and no sync
change. The log stays `vf-playlist-review` `version: 1` (Decision 1).

## Why

On 2026-11-06 Jon finished all 25 songs, kept 5, and told the chat. Vinyl Fever reported 5 kept
and 20 pending, and it would have kept saying so until 2026-11-20:

```swift
guard !keepKeys.contains(key) else { return .kept }
guard now >= windowEnd && snapshot.generatedAt >= windowEnd else { return .pending }
return heardKeys.contains(key) ? .passed : .unheard
```

The 14 days exist to absorb late listens and a stale snapshot (M17). They're right when nobody
has said anything. When Jon says he's done, there's nothing left to wait for except the snapshot.

**The snapshot is the real constraint.** The Mac app refreshes it at launch when it's over six hours
old, or from **Refresh Library Snapshot**. `vf-mcp` can't: reading Music takes the app's Automation
access. A rule that waits for a newer snapshot would wait indefinitely on an app already running,
so this effort has to ask the app for one.

**Scoring needs no new evaluator.** `recommendation_outcomes` already splits picked and not-picked
songs into kept and passed, which gives all four outcomes once passes exist.

## Changes

- **The record** (`VinylFeverNotes`, no type changes). A week's finish is a `PlaylistReviewEntry`:
  - `source: .jon`, `kind: .finished`; undoing it is `kind: .reopened`. Latest Jon line wins, as
    today;
  - `device: "chat"`, which is the provenance: Jon said it, the chat wrote it;
  - `playlistID: "new-music-week|<lastModifiedDate, ISO 8601 UTC, whole seconds>"`, from a new
    public helper `PlaylistReviewsCodec.newMusicWeekID(_:)`;
  - `host`: the week's `host`. `recordedAt`: the week's `lastModifiedDate`. `playlist`:
    `"New Music, <yyyy-MM-dd>"`. `at`: the real time of the call, never backdated;
  - written with `writer: "chat-\(hostName())"`, the file reviews already use.
- **Keep it out of the playlist features.**
  - `playlist_reviews`, `record_playlist_review`, and the phone look these up by shelf id, so a week
    never matches. Keep it that way with a test.
  - `newestFinishedPlaylist()` scans every finished line, so it must skip ids with this prefix.
- **`finish_new_music_week`** (`vf-mcp`, write, `destructiveHint: false`).
  - **Input:** `week`, required: the `lastModifiedDate` as `kept_and_passed` returned it. `undo`,
    optional boolean.
  - An unknown week is an error naming the date. Compare parsed dates, not strings.
  - **Repeat calls:** when the week is already in the requested state, append nothing and return
    `recorded: false` with the original `finishedAt`.
  - **Output:** `recorded`, `finishedAt` (absent after an undo), `awaitingSnapshot`,
    `snapshotTakenAt`, and the week's `counts`.
  - **Snapshot request:** any call that leaves the week `awaitingSnapshot` asks the app for a
    refresh, including a repeat call.
- **Classification** (`TasteIntelligence`). `classify`, for New Music weeks only, gains `finishedAt`:

  ```swift
  guard !keepKeys.contains(key) else { return .kept }
  if let finishedAt { return snapshot.generatedAt >= finishedAt ? .passed : .pending }
  // today's 14-day rule, unchanged
  ```

  - Build `[Date: Date]`, week to `finishedAt`, from `latestJonState`, and pass it to
    `keptAndPassed`, `recommendationOutcomes`, and through to `baselines`. It defaults to empty.
  - A staged batch's call to `classify` never gets one, even if its date happens to match a week.
  - A finished week never has `unheard` songs. Jon's statement replaces the listening log as the
    evidence that he heard them, so log gaps don't matter here.
- **New fields, all optional and omitted when not set:**
  - `NewMusicWeekResult`: `finishedAt`, and `awaitingSnapshot` (`true` when finished and the
    snapshot is older than `finishedAt`);
  - `RecommendationOutcomeBatch`, on `new-music-picks` batches: the same two, and
    `heardBeforePick`, listing `artist — title` for the songs left out of scoring.
- **The Mac app refreshes on request.**
  - **`vf-mcp`:** `LibraryMCPServer.make` gains an injected `requestSnapshotRefresh` closure. Live, it
    posts the `DistributedNotificationCenter` notification
    `com.jonphillips.vinylfever.refreshSnapshot` with `deliverImmediately: true`.
  - **The app:** a dependency client exposes the notifications as a stream.
    `PlaylistBuilderModel` runs the existing `refreshSnapshot(requestingPermission: false)` when one
    arrives, and once more five minutes later, for keeps still syncing to this Mac. A new request
    replaces a pending later refresh.
  - **Subscribe only under `context == .live`**, in the same `.task` as the launch refresh, so the
    app-test host never touches live dependencies (#108).
  - Without Automation access it does what the launch refresh does: no prompt, and the app shows
    the existing message.
- **Instructions** (`LibraryMCPServer.instructions`), added after the New Music picks text:

  > When Jon says he's finished a New Music week, read kept_and_passed for its lastModifiedDate and
  > call finish_new_music_week without asking him to confirm. Only his saying so counts; never
  > infer it. If he says he isn't done after all, call it with `undo: true`. Then read
  > recommendation_outcomes. While `awaitingSnapshot` is true, the Mac is refreshing its library:
  > report the keeps, and don't report passes yet. Check again after a minute or two. If it stays
  > true, call finish_new_music_week again, then ask Jon to open Vinyl Fever on the Mac. Once it's
  > false, review the picks: picked and kept, picked and passed, kept but not picked, and neither.
  > Say which songs were heard before the picks and weren't scored. If the week has no picks,
  > review what he kept. Record nothing of yours as a taste note.
- **Docs:** add the finished-week path beside the 14 days in `docs/feedback-guide.md`, and at the
  two-week rule in `docs/taste-intelligence.md`.

## Decisions

1. **Reuse `playlist-reviews`, as `version: 1`.** It's already append-only, with latest-Jon-line-wins,
   undo, and a `source`, and current readers accept the line and look up by shelf id. This
   extends M23 Decision 1's "keyed to the ledger batch" to weeks, which have no batch when the chat
   made no picks. A version bump or a new `kind` would have installed phones skip or miscount lines
   for no gain.
2. **`source: jon`, `device: "chat"`.** The statement is Jon's, so `review` lines' `source: chat`
   would misdescribe it. M22 S4's line stays: the chat's own words are still never Jon's.
3. **The freshness rule is `snapshot.generatedAt >= finishedAt`,** and no more. Outcomes are worked
   out on every read, so a keep that syncs later turns a pass into a keep by itself, and nothing
   stored goes stale. The second refresh is there to make that happen unprompted.
4. **Finishing is authoritative over the listening log.** Every unkept song is `passed`, whether or
   not a play was logged. This amends M18's "passed is heard within 14 days and not kept" for
   finished weeks only.
5. **Undo exists, the chat's only way to fix a mistake.** The log is append-only, and a false finish
   would otherwise count every unkept song as passed for good.
6. **Any saved week can be finished,** with the real time on it. 2026-10-30's and 2026-11-06's
   weeks can be finished once this ships. Their picks stay as recorded: 2026-10-30's batch scores,
   and 2026-11-06 has none.

## Done when

- **`VinylFeverNotes` tests:** the week id's format; a `chat` finish and reopen round-trip and pass
  `isValid`; latest Jon line wins.
- **`TasteIntelligence` tests:**
  - a finished week before day 14, 5 in keepers and 20 not, with a newer snapshot: 5 kept, 20 passed,
    0 pending;
  - the same week with an older snapshot: 5 kept, 20 pending, `awaitingSnapshot: true`. With a
    newer snapshot in which one more is kept: 6 kept, 19 passed;
  - plays logged for only some songs make no difference to a finished week;
  - an unfinished week follows the 14-day rule exactly, both sides of the window;
  - a reopened week goes back to that rule;
  - a staged batch dated the same as a finished week isn't affected;
  - picks on a finished week: all four cells are right, a `heardBeforePick` song is listed and not
    scored, and `taste_baselines` counts the week as finished.
- **`LibraryMCPServerTests`** (fixture folder, captured `requestSnapshotRefresh`):
  - finish, then `kept_and_passed` shows `finishedAt`;
  - a repeat call returns `recorded: false`, adds no line, and keeps the first `finishedAt`;
  - an unknown week is an error naming the date;
  - undo appends `reopened`, and undoing an unfinished week appends nothing;
  - the refresh is requested while awaiting, including on a repeat, and not once the snapshot is
    newer or after an undo;
  - a finish line doesn't appear in `playlist_reviews`, doesn't let `record_playlist_review` through,
    and isn't `newestFinishedPlaylist()`;
  - prior batches, notes, and playlist finishes and reviews are unchanged;
  - the tool's schema is in the expected-tools list, the golden JSON still matches for unfinished
    weeks, and the instructions carry the new text.
- **App model test** (injected stream and clock): a request refreshes now and again after five
  minutes; a second request replaces the pending later refresh.
- **Phone:** a test that a week's finish line changes no shelf playlist's state.
- `scripts/mcp-smoke` lists `finish_new_music_week` and checks the instruction sentence.
- Closeout (ADR-0005 D16) records the gate below.

**The gate.** After the install, in a new chat, on a real New Music week:
1. The chat saves picks (the [evicted-icloud-writes](evicted-icloud-writes.md) gate can be the same
   run).
2. Jon listens and keeps some songs, one of them on the phone just before finishing.
3. Jon says "I finished this week's New Music." The chat records it without asking him to confirm.
4. Without Jon touching the Mac, the snapshot is newer within about two minutes.
5. The chat's review matches Jon's keeps, and the kept-on-phone song counts within five minutes.
   If it doesn't, record how long the library took to sync, because that sets the second refresh's
   delay.

## Out of scope

- **Finishing from the phone or the Mac app.** The chat is how Jon does this. New Music weeks aren't
  on the phone's shelf, so it would need a place to show them. Plan it if Jon wants it after a few
  weeks.
- **A stored review of a New Music week.** `record_playlist_review` needs a staged batch. The chat
  reviews in the conversation, and Jon's reactions are taste notes.
- **The listening log's lag at pick time.** A song played minutes before the picks may not be logged
  yet, so `heardBeforePick` can read `false`. It can only err that way, and the poller's interval
  sets the size of the gap.
- **Scheduled snapshot refreshes.** The on-request refresh covers this flow, and
  `review-keeps-from-phone` covers playlists. Staged-playlist reviews don't request a refresh here.
