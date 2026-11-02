# Milestone 23 — Done listening, and taste that travels

*Let Jon say he's done with a playlist and have the chat review it on the record. Make sure
what Jon tells the chat about his taste lands in Vinyl Fever's files, not only in one
provider's history. Then find out whether ChatGPT can be woken from outside. Rules in
[../technical-architecture.md](../../technical-architecture.md), jon-platform `AGENTS.md`, and
`docs/ios/mcp-access.md` apply. The phone screens follow jon-platform
`docs/ios/ui-and-platforms.md`. Where this doc and those conflict, stop and flag it.*

Status: Done 2026-11-02
Summary: S1 has the chat record Jon's taste statements word for word as he makes them, S2 adds Done listening on the phone and a recorded chat review of each finished playlist, and S3 probes whether ChatGPT's MCP Events reach `vf-mcp` through the Secure MCP Tunnel, which decides the push milestone after it.

Jon asked for this on 2026-11-02, after M22:
1. A button in the phone app that says "I've listened to this playlist, please evaluate it,"
   and a way to post that to the chat. He asked whether an App Intent could do it, and what
   ChatGPT and Claude can now do to push into a chat from outside.
2. OpenAI has announced that flat-rate ChatGPT is ending (Jon, 2026-11-02; not checked against
   OpenAI's announcement). Chat and Work will count against one token tally. That makes Jon
   open to switching providers, so he asked whether Vinyl Fever records enough that a switch
   wouldn't lose his taste history.

## The milestone in one sentence

Jon finishes a playlist, taps Done listening, and the chat's review of it is recorded beside
the playlist. Anything he tells the chat about his taste is saved in his words, so another
provider could pick up where this one left off.

## What's true today (architect research, 2026-11-02)

**The review needs no data push.** `vf-mcp` already serves `kept_and_passed`,
`recommendation_outcomes`, `taste_notes`, and `record_taste_note`. Since M22 S4 the ledger
keeps Jon's request word for word, the chat's description, and every song's why. A chat asked
to review a playlist can read everything it needs. What's missing is a record that Jon is done,
and a home for the review.

**Pushing into ChatGPT:**
- **There's no API to post into a Project.** OpenAI's developer forum has open feature
  requests for one. An unofficial bridge fails on project-scoped chats.
- **MCP Events (OpenAI, 2026-09-29)** is the real push. A plugin's MCP server advertises
  `events` and serves `events/list`, `events/subscribe`, and `events/unsubscribe`. In a
  **Work** chat or a dot, Jon asks ChatGPT to watch an event and says what to do. ChatGPT
  subscribes with a callback URL and a `whsec_` secret. The server checks the callback with a
  signed challenge, then POSTs Standard Webhooks-signed events to it, at most 256 KiB each.
  The run happens in the chat that subscribed.
  - Limits: 30 runs an hour and 720 a day across all event-triggered tasks. Matching events
    may be batched into one run. Not on Free or Go.
  - Unknown, and S3 finds out: whether the Secure MCP Tunnel passes `events/*` to the stdio
    helper; whether a personal plugin qualifies; and what sends the event, since the tunnel's
    `vf-mcp` lives only while ChatGPT is connected.
  - Work vs Project no longer matters for cost, given the metering change.
- **Shortcuts:** the ChatGPT app's **Ask ChatGPT** action takes a message and has a "start new
  chat" toggle. iOS 26's **Use Model** action can pick ChatGPT. No Project picker was found. It
  isn't known whether a Shortcuts-started chat gets the Vinyl Fever plugin.
- **Apple:** iOS 27 Siri Extensions for ChatGPT, Claude, and Gemini, and MCP inside App Intents,
  were found in betas and reported. Apple hasn't documented either.

**Pushing into Claude:**
- **Channels (Claude Code, research preview, v2.1.80+):** an MCP server pushes events into a
  session that's already running, and can reply through the same channel. It fits
  `~/music-chat`, which already runs `vf-mcp`. A watcher on the iCloud folder could push "Jon
  finished X" with no public URL. Custom channels need `--dangerously-load-development-channels`.
  A permission prompt pauses the session while Jon is away.
- **Scheduled tasks' API trigger (formerly routines):** POST `text` to
  `/v1/claude_code/routines/{id}/fire` with a per-task token, and a cloud session starts. The
  cloud can't reach `vf-mcp` unless it's a claude.ai connector. An open bug
  (anthropics/claude-code#106037) leaves custom connector tools unloaded in triggered runs.
- **claude.ai connectors** support MCP Apps (interactive UI, since 2026-01-26) and MCP tunnels
  (research preview). No connector-to-chat push like MCP Events was found.
- **Ask Claude** App Intent on iOS: no project targeting found.

**What would travel to another provider (measured 2026-11-02, iCloud `Taste Intelligence/`):**
- **Provider-neutral, served by `vf-mcp` to any MCP client:**
  - the listening log;
  - the curation log (10 lines);
  - New Music exposure (since 2026-10-30);
  - `playlist-roles.json` and the library snapshot;
  - 7 recommendation batches (request and whys since 2026-10-28);
  - 56 notes: 19 from the shortcut, 9 from the iPhone intent, and 28 from the chat. Of the
    chat's 28, 19 are notes, 4 questions, 4 answers, and 1 older line.
- **Stays with ChatGPT:**
  - **Most of what Jon says in chat.** The server instructions tell the chat to record only
    answers to its own questions. Jon's other chat notes exist because he said "record this."
  - **ChatGPT's memory and its picture of Jon's taste.** By design, no file holds the chat's
    interpretation.
  - **Music conversations from before `vf-mcp`.**
  - **Reviews of playlists,** until S2 gives them a home.

Sources: OpenAI [MCP Events](https://developers.openai.com/plugins/build/mcp-events);
[ChatGPT release notes](https://help.openai.com/en/articles/6825453-chatgpt-release-notes);
[scheduled tasks in ChatGPT](https://help.openai.com/en/articles/10291617-scheduled-tasks-in-chatgpt);
[projects API request](https://community.openai.com/t/api-request-programmatic-management-of-chatgpt-projects-and-conversations/1394663);
Claude Code [channels](https://code.claude.com/docs/en/channels) and
[scheduled tasks](https://code.claude.com/docs/en/routines);
[routine fire API](https://platform.claude.com/docs/en/api/claude-code/routines-fire);
[MCP 2026-07-28 in Claude](https://claude.com/blog/bringing-mcp-2026-07-28-to-claude);
[Ask Claude on iOS](https://support.claude.com/en/articles/10263469-use-claude-app-intents-shortcuts-and-widgets-on-ios);
[Siri Extensions missing from WWDC](https://thenextweb.com/news/apple-siri-extensions-third-party-ai-missing-wwdc).

## Shared rules (every slice)

- **Vinyl Fever stays deterministic.** No model calls in the app or the helper. The chat
  interprets, and Vinyl Fever records (taste-intelligence design).
- **Whose words, as M22 S4:** taste notes are Jon's words, word for word. The chat's words,
  such as a review, are never written as a taste note.
- **New logs follow the notes pattern:** append-only JSON lines in the iCloud
  `Taste Intelligence` folder. One file per writer (`<device-or-host>.jsonl`), with `format`
  and `version` on every line. Readers skip lines they can't read, count them, and never
  rewrite a file.
- **Shared logic lives in `VinylFeverNotes`,** Foundation only, tested on macOS, and used by the
  phone app and `vf-mcp`.
- **House stack, as M22:** `@Observable` models, dependency clients, an injected folder and
  clock. Tests never touch live paths.
- **Instruction changes ship in `LibraryMCPServer.instructions`,** never in Settings' copy.
  Verify with `scripts/mcp-smoke` against the built helper.

## Slices

**Dispatch 1: S1** (Jon's words saved). **Dispatch 2: S2** (Done listening and the review).
**Dispatch 3: S3** (the MCP Events probe). Each completing PR advances `NEXT_UP.md`. None waits
on Jon's gates.

- [x] **S1 — Jon's words, saved when he says them.**
  - **Why.** The chat records Jon only when he answers one of its questions or says "record
    this." His reactions, reasons, and preferences otherwise live only in one provider's
    history.
  - **`vf-mcp` instructions.** In any taste conversation, when Jon states a preference, reacts
    to a song, artist, or playlist, or explains a keep or a pass, record his words word for word
    with `record_taste_note`. Name the songs or playlists in `about` when he names them. After
    recording, say in a few words that it's saved, so he can say "don't." Don't record:
    - the chat's own words or a paraphrase;
    - a playlist request (it goes in `stage_playlist`'s `request`);
    - small talk without a taste statement;
    - the same words twice in one conversation.
  - **`record_taste_note`'s description** says the same in one sentence.
  - **DoD:**
    - a test that the instructions and the tool description carry the rule;
    - `scripts/mcp-smoke` shows the built helper serving it;
    - closeout (ADR-0005 D16) records the gate: after the install, in a new chat, Jon makes
      two unprompted taste statements and checks that both land in `notes-chat-<host>.jsonl`,
      word for word.
  - **The gate (2026-11-02): failed.** In a new Work chat, Jon reacted to "Red Flags" and "Sister
    Ray". The chat replied, but saved nothing until Jon asked it to quote the rule. Then it quoted
    the rule exactly and saved both reactions word for word. The fix and the re-run are in
    [review-keeps-from-phone](../../efforts/review-keeps-from-phone.md).

- [x] **S2 — Done listening, and the chat's review on the record.**
  - **The log (Decision 1).** `Taste Intelligence/playlist-reviews/<device-or-host>.jsonl`,
    `format: "vf-playlist-review"`, `version: 1`. Every line names its playlist by the ledger
    batch's `host` and `recordedAt`, the shelf's identity, plus the `playlist` name for people.
    Every line carries `source` (`jon` or `chat`). Kinds:
    - `finished` (Jon, from the phone): `at`, `device`.
    - `reopened` (Jon, from the phone): undoes a `finished`. A playlist's latest Jon line wins.
    - `review` (the chat, through `vf-mcp`): `at`, `host`, `text` (the chat's words), and the
      heard, kept, passed, and unheard counts as read when the review was written.
  - **The phone.**
    - A labeled **Done listening** button on the playlist detail, placed per
      `ui-and-platforms.md` § Controls. It confirms, then appends `finished`.
    - A finished playlist without a review shows "Done · waiting for the chat's review," with a
      **Not done** action that appends `reopened`.
    - Once a review exists, the detail shows it under the progress bar in the chat's type
      (M22 S4: body font, secondary, no rule, no italic), with its date.
    - The list shows a finished playlist's state in its row.
  - **`vf-mcp`.**
    - `playlist_reviews` (read): finished playlists without a review, newest first. Each comes
      with its request, description, and every song's why, heard, kept, or passed (M22 S2's
      rule, from `VinylFeverNotes`), and Jon's notes about it. Recent reviews follow.
    - `record_playlist_review` (write): the batch identity and `text`. It's refused when the
      batch doesn't exist or Jon hasn't finished it. A second review of the same batch is
      appended, and readers show the latest.
    - The instructions: when Jon asks for a review of his finished playlists, read
      `playlist_reviews`, judge each against its request and whys, show Jon the review, then
      record it. Never claim an outcome a tool didn't report.
  - **DoD:**
    - package tests: the codec round trip for each kind; latest-Jon-line-wins; a review
      refused for an unfinished batch; unreadable lines skipped and counted;
    - phone model tests: finished, reopened, and reviewed states, with an injected folder and
      clock;
    - an MCP test for both tools against a fixture folder;
    - closeout (ADR-0005 D16) records the gate: Jon finishes a real playlist on the phone, asks
      the chat in a new conversation to review his finished playlists, and sees the review on
      the phone.

- [x] **S3 — Probe: do MCP Events reach `vf-mcp` through the tunnel?**
  - **Why.** The push milestone depends on answers no document gives (see *What's true
    today*).
  - **The probe build.** When `VF_MCP_EVENTS_PROBE=1` is set, `vf-mcp`:
    - advertises `events: {}`;
    - lists one event, `playlist.finished`, with an empty `inputSchema` and a payload of
      `playlist`, `host`, and `recordedAt`;
    - serves `events/subscribe` and `events/unsubscribe` per OpenAI's MCP Events doc: callback
      verification, `whsec_` secret checks, and deterministic subscription IDs;
    - stores subscriptions in `~/Library/Application Support/VinylFever/EventSubscriptions/`.
    - `vf-mcp --probe-fire` sends one signed `playlist.finished` for the newest `finished`
      line to every stored subscription and prints each response.
    - Without the variable, nothing changes.
  - **The run (Jon and the architect, after the install).** Set the variable in the tunnel
    agent's environment. In a ChatGPT Work chat, ask it to watch `playlist.finished` and
    review the playlist. Then run `--probe-fire`. Record in this section:
    1. whether ChatGPT shows the event;
    2. whether `events/subscribe` reached the helper (log it);
    3. whether verification and delivery succeeded from the Mac;
    4. whether the run called `playlist_reviews` and `record_playlist_review`;
    5. whether the subscription survives a tunnel restart.
  - **DoD:**
    - tests for subscribe validation, signing (a Standard Webhooks test vector), and the
      unset-variable path;
    - closeout (ADR-0005 D16) records the run as the gate.
  - **The run (2026-11-02, Jon and the architect).**
    - **The route:** on this Mac, a ChatGPT Work chat reaches Vinyl Fever through ChatGPT's
      built-in Codex, which starts its own `vf-mcp` from `~/.codex/config.toml`, not through
      the tunnel. The tunnel's helper had no requests during the run. The probe variable went
      into both: `launchctl setenv` for the tunnel, and the server's `env` in Codex's config.
    - **The answers:**
      1. ChatGPT didn't use the event. With `events` advertised, it never called `events/list`.
      2. `events/subscribe` never reached either helper: no `probe.log` was written.
      3. Verification and delivery were never reached.
      4. Yes. Asked to watch `playlist.finished`, ChatGPT made its own monitor in the chat:
         "Review finished Vinyl Fever playlists", every 15 minutes. It calls
         `playlist_reviews`, and `record_playlist_review` when one is waiting. Its first try
         failed because it couldn't identify the chat; "host the monitor in this chat" fixed it.
      5. Doesn't apply: the monitor is a ChatGPT scheduled task, not a subscription.
    - **End to end:** Jon tapped Done listening on *Pop with Bite* at 15:57:51. The line reached
      the Mac at 16:03, the monitor recorded its review at 16:09, and it showed on the phone.
      The review missed Jon's keeps, because the Mac's library snapshot dated from 2026-10-31.
      The fix is [review-keeps-from-phone](../../efforts/review-keeps-from-phone.md).
    - **So:** the review loop needs no push. The monitor's polling delivers it within 15 minutes
      plus iCloud sync, and Jon sets its interval in ChatGPT, since each check costs tokens.

## Out of scope — with destinations

- **The push itself** (a Mac-side sender, or the Shortcuts fallback): not needed, per S3's
  run. ChatGPT's own monitor covers the review loop. Revisit only if polling's delay or token
  cost becomes a problem.
- **A Claude channel** reading the same `playlist-reviews` log: M24, as a second reader once
  the log exists.
- **Importing music conversations from before `vf-mcp`:** after S1. Jon requests a ChatGPT data
  export, then the architect plans the import. Jon's words become dated notes tagged as
  imported. ChatGPT's own summary of his taste is kept apart and labeled as the chat's.
- **The cold-start drill:** after S2. A fresh Claude session with no history gets the same
  request as a recent ChatGPT batch, and Jon's keeps judge (M18 outcomes). It's the test of
  whether the evidence is enough to switch.
- **Claude scheduled tasks' API trigger:** not while `vf-mcp` can't be reached from the cloud
  and #106037 is open.
- **Siri Extensions and MCP in App Intents:** revisit when Apple documents them.

## Decisions

1. **One review log, two writers (architect, 2026-11-02).** Done listening is Jon's record and
   the review is the chat's, so they share a log keyed to the ledger batch, with a `source` on
   every kind. The recommendation ledger stays the Mac's own file, and older readers never see
   a new kind. A review isn't a taste note, because notes are Jon's words (M22 S4).
2. **Save first, push second (architect, 2026-11-02).** S1 and S2 are useful with any chat
   and no push, because Jon can just ask for his reviews. The push is decided by S3's probe,
   not by research alone.
3. **The probe ships behind a variable (architect, 2026-11-02),** like M20 S0's probe intent.
   It costs nothing when the variable is unset, and S3's answers decide whether it becomes the
   real sender or is removed in M24.
