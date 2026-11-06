# Effort — Writes survive iCloud eviction

Status: Dispatched
Summary: `vf-mcp` runs under launchd, where a write to an iCloud file that Optimize Storage has evicted fails, so New Music picks and a staged playlist's record were lost on 2026-11-06. One shared append fetches the file first and reports the real error, a week keeps its first picks, and the chat says when something wasn't saved.

Related: [M18](../../milestones/M18-taste-outcomes.md) · [M23](../../milestones/archive/M23-done-listening.md) ·
[Efforts index](../README.md)

Branch `effort/evicted-icloud-writes`, from a fresh `main`. One PR. No schema change and no sync
change: every log keeps its format and version.

**It needs to be installed before New Music on Friday 2026-11-13.**

## Why

On 2026-11-06 `record_new_music_picks` failed twice with "The file couldn't be saved." The
same session's `record_taste_note` worked.

**The cause, reproduced by the architect on throwaway iCloud files.** The same append code ran
two ways against an evicted file:

| Run as | Result |
|---|---|
| A login shell | Works. The write downloads the file, and the line lands. |
| A launchd job, as the tunnel's `vf-mcp` is | `NSCocoaErrorDomain` 512, "The file couldn't be saved.", underlying POSIX 11 `EDEADLK` |

A process started by launchd isn't allowed to fault in an evicted file by reading or writing it.
A plain `Data(contentsOf:)` fails the same way. The same run tried each possible fix:

| Tried, as a launchd job, on an evicted file | Result |
|---|---|
| Today's code: a `.forMerging` write claim | Fails |
| One combined read-and-write claim | Fails. The file is still evicted inside the claim. |
| **A separate read claim, then today's write claim** | **Works.** The read claim alone downloads it. |
| `setiopolicy_np`, materialization on, thread or process scope | Works |

**The timeline on 2026-11-06 (unified log, `fileproviderd`, and the files):**

| Time | What happened |
|---|---|
| 11:08:43 | iCloud evicts `recommendations/Jon_MBP.jsonl`. It was last written on 2026-11-04. |
| 11:20:03 | `notes-chat-Jon_MBP.jsonl` is downloaded again |
| 11:26:15 | `stage_playlist` writes *The Missing Decade*'s `.vfplaylist` |
| 11:26:17 | Its ledger write claim. No line lands, so the batch is lost. |
| 11:32:19, 11:32:27 | The two pick attempts' write claims. Neither changes the file. |
| 12:25:57 | The ledger is downloaded again |
| 12:36:01 | `record_taste_note` writes normally, to the file downloaded at 11:20 |

The helper doesn't log its errors, so applying the reproduction to those three claims is an
inference. It's why this effort also adds real errors.

**Why the ledger and not the notes.** Both use the same code. `taste_notes` reads its files often,
and a coordinated read downloads them. The ledger's reader caches by modification date, and
`recordNewMusicPicks` never reads the ledger, so nothing brought it back. Any append the helper
makes can fail this way once its file has sat idle.

**Two more things this showed:**
- `stage_playlist` caught the error, so the playlist staged while its record vanished: no phone
  shelf entry, no outcomes. M18's "a ledger problem never fails staging" stays, but
  `ledgerReason` says only "ledger could not be read or written", and no instruction tells the
  chat to pass that on.
- Cocoa's message names neither the file nor the cause. The `EDEADLK` was only visible in
  `NSUnderlyingError`.

## Changes

- **One shared append** (`VinylFeverNotes`, new `JSONLAppend.swift`, Foundation only).
  - `JSONLAppend.append(_ data: Data, to url: URL) throws` does, in order:
    1. create the folder;
    2. a coordinated **read** claim on `url` with an empty accessor, as its own call, which
       downloads an evicted file;
    3. the `.forMerging` write claim from today's code: create the file if it's missing, open,
       seek to the end, write, synchronize.
  - It checks `createFile`'s result, so a failed create can't surface later as a confusing open
    error.
  - **Callers, each losing its copy of this code:**
    - `TasteNotesCodec.append`, `RecommendationLedgerCodec.append`, and
      `PlaylistReviewsCodec.append`;
    - `ListeningCoordinatedFiles.append` (`VinylFeverListening`), because the listening agent is
      also launchd-run;
    - `TasteCurationLog.append` (app).
  - **Leave alone:** `MCPEventsProbe` (its log is local) and `ProbeLogWriter` (a probe).
- **Errors say what happened.** `JSONLAppend` throws a `LocalizedError` naming:
  - the step: `create folder`, `download`, `create file`, `write`, or `coordinate`;
  - the file as its last two path components, such as `recommendations/Jon_MBP.jsonl`, never the
    full path;
  - the underlying domain, code, and description, read from `NSUnderlyingError` when present.

  For example: `Couldn't save recommendations/Jon_MBP.jsonl (write): NSPOSIXErrorDomain 11,
  Resource deadlock avoided`.
- **A week keeps its first picks** (`recordNewMusicPicks`).
  - If the ledger already has a `new-music-picks` batch for this week's `lastModifiedDate`, from
    any host, append nothing and return `recorded: false` with that batch's `recordedAt` and
    picked-song count.
  - So a retry after a real failure records normally, because a failed write left nothing, and a
    retry after a success changes nothing. Later picks can't stand in for blind ones.
  - `taste_baselines` already scores only a week's first batch (`pickYields`), so no reader
    changes. The existing lines stay as they are.
  - The check reads the ledger, which will also download it. The append must not rely on that.
- **`stage_playlist`'s `ledgerReason`** carries the error's description instead of the fixed
  string. Staging still succeeds.
- **Instructions** (`LibraryMCPServer.instructions`). Replace "When Jon asks which New Music songs
  he'll keep, read kept_and_passed, choose before he listens, then call record_new_music_picks."
  with:

  > When Jon asks which New Music songs he'll keep, read kept_and_passed, choose, then call
  > record_new_music_picks right away, even if he has started listening: songs he's already heard
  > are marked and left out of scoring. A week keeps its first picks, so `recorded: false` means
  > they're already saved. If the call fails, show Jon the error as reported and say the picks
  > weren't saved. If stage_playlist returns `ledgerRecorded: false`, tell Jon the playlist is
  > staged but its record wasn't saved, and give him `ledgerReason`.

  Begin the tool's description with the same point: "Record the chat's picks from the latest saved
  New Music week as soon as they're chosen." Keep the rest of the description accurate.

## Decisions

1. **A read claim, not `setiopolicy_np`.** Both pass the probe. The read claim is plain Foundation,
   which `VinylFeverNotes` requires. It's the same mechanism `readCoordinated` already relies on,
   and the phone shares this code. The process-wide policy would also cover plain reads, but the
   helper's iCloud reads are already coordinated.
2. **No backfill, and no backdating.** The 2026-11-06 picks aren't recorded after the fact. That
   week was heard before anything could be saved, so it stays unscored (M18 Decision 5's reasoning).
3. **No retry loop.** A file evicted in the moment between the two claims would report a clear
   error, and the chat can call again. The window is too small to justify the code.
4. **No torn-line handling.** This failure happens before any byte is written, and a line is one
   `write`. Readers already skip and count unreadable lines.

## Done when

- **`VinylFeverNotes` tests** (temporary folders, as usual):
  - appending to a missing file in a missing folder creates both;
  - appending to an existing file keeps its bytes and adds the line;
  - the folder path is a file, and the target is a directory: each throws the error above, with
    the step and two path components, and no full path;
  - each of the three codecs round-trips through `JSONLAppend`.
- **`LibraryMCPServerTests`** (fixture folder):
  - record picks, then a separate read through `recommendation_outcomes` finds the batch;
  - a second call for the same week returns `recorded: false` with the first `recordedAt`, and
    the ledger still has one batch;
  - a write failure (make the ledger's path a directory) returns `isError: true`, its text names
    the file and step, and it doesn't contain the taste folder's path. A later call, with the path
    fixed, records normally;
  - `heardBeforePick`: a song played before `recordedAt` is `true`, a song played only after it
    and a song never played are `false`;
  - `stage_playlist` with a failing ledger still stages, with `ledgerRecorded: false` and a
    `ledgerReason` naming the file;
  - earlier batches and notes survive all of the above;
  - the instructions and the tool description carry the new text.
- **Listening package tests** still pass with the shared append, and the app builds.
- `scripts/mcp-smoke` passes against the built helper, and checks the new instruction sentence.
- Closeout (ADR-0005 D16) records the gate below.

**What tests can't show:** evicting a file needs real iCloud, and the failure needs a launchd
process, so no automated test reproduces it. Name that in the PR.

**The architect's review probe:** compile the merged `JSONLAppend.swift` into a scratchpad probe,
run it with `launchctl submit` against evicted throwaway files in iCloud, and confirm the control
fails and the shared append passes.

**The gate.** After the install, on New Music Friday, before asking for picks, Jon runs these:

```bash
brctl evict "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/recommendations/Jon_MBP.jsonl"
```

```bash
stat -f '%Sf' "$HOME/Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Taste Intelligence/recommendations/Jon_MBP.jsonl"
```

The second prints a list that includes `dataless` when the file is evicted. Evicting loses nothing, because the file
stays in iCloud. Then, in a chat started after the install, Jon asks which songs he'll keep. The
chat saves its picks with `recorded: true`, and `recommendation_outcomes` lists the batch.

## Out of scope

- **The finished-week signal:** the next effort,
  [finish-new-music-week](../finish-new-music-week.md).
- **Recovering *The Missing Decade*'s record.** The `.vfplaylist` has the songs but not the request
  or the whys. If Jon wants it tracked, the chat that wrote it can stage it again.
- **Testing the phone for this failure.** Its appends go through the shared code, so they gain the
  read claim either way.
