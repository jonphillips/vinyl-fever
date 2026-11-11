# Effort — The phone shows what the chat wrote

Status: Ready
Summary: The chat writes each song a label, a few facts, and a paragraph, and groups songs under headings, but `stage_playlist` only carries a one-sentence `why`, so the phone shows a thinner list than the chat did. Staging gains four optional per-song fields in the chat's own words (`tag`, `details`, `story`, `section`); the ledger keeps them and the phone shows them.

Related: M24 (the phone shelf) · [Taste Intelligence](../taste-intelligence.md) ·
[Efforts index](../README.md)

Branch `effort/chat-writeups-on-phone`, from a fresh `main`. One PR: the MCP server, the ledger
type, and the phone. No Mac UI change.

## Why

Jon, 2026-11-11, comparing the chat on his iPad with the phone on a walk: "The list that ChatGPT
posts in the chat is a bit more fun … descriptions are longer, songs are highlighted as strong
recommendation, challenge, etc. Then those go away and shorter descriptions show up in the mobile
app. … I don't want to curtail the 'creativity' in the moment of how it might choose to classify.
But predictions/challenges/full descriptions/ & optional supplemental info … would be fun to see
this in the mobile app."

His screenshots of two lists:

- *Hooks, Beats & Guitars*: in the chat, "3. Wannabeher — MUNA (2026)" with a green "Strong
  prediction" pill and three sentences; "7. I CAN'T LOSE YOU" under "CHALLENGE TRACK". The phone
  shows "Punchier guitar-pop from a group you selected for Dancing on the Wall."
- *Beyond the Boss, Vol. 2*: in the chat, "SCOTLAND · Lyrical challenge" and "UNITED STATES · Very
  strong bet" lines, a paragraph per song, and a "Five more with major upside" heading over songs
  6–10 ("Highlands — Middle Kids (2023, Australia)… Released as a single in 2023, then included on
  *Faith Crisis Pt 1* in 2024"). The phone shows one sentence each and no heading.

**Where it's lost (architect reading, 2026-11-11).** The phone shows all it gets.
`stage_playlist`'s track schema (`LibraryMCPServer.swift`, `stageSchema`) has only `artist`,
`title`, `album`, `year`, `why`, `like`, and the server instructions ask for "a one-sentence why".
So the chat writes the long version for Jon and a short one for the tool. `RecommendationTrack`
(`VinylFeverNotes/…/RecommendationLedger.swift`) has nowhere to keep more, and
`PlaylistSongView` renders `familiarity`, `why`, notes, and `like`.

## Changes

- **Four optional per-song fields on `stage_playlist`.** Add to the track item properties in
  `stageSchema`, and to `PlaylistToolPayload.Track` (decode each with `decodeIfPresent`):

  | Field | Type | Schema description (use this wording) | Cap |
  |---|---|---|---|
  | `tag` | string | "The short label you gave this song in chat, in your own words, if you gave it one. Omit it otherwise." | 40 characters |
  | `details` | array of string, `maxItems` 3 | "Short facts you showed beside this song in chat, such as where the artist is from or how it was released. Omit them otherwise." | 80 characters each |
  | `story` | string | "The paragraph you showed Jon about this song in chat, word for word. Omit it if you showed only a sentence." | 1,500 characters |
  | `section` | string | "The heading you showed this song under in chat, word for word. Omit it if the list had no headings." | 80 characters |

  None is required, and no field gets an `enum` or example list: the chat chooses its own labels
  and headings each time (Decision 1). Trim whitespace; an empty string, or a `details` that's
  empty after dropping empty entries, is stored as absent. A value over its cap is cut to the cap
  and sets the existing `truncated` result flag, the same way `why` over 300 does today. More
  than three `details` keeps the first three and sets `truncated`, as `like` does.
- **The ledger keeps them.** `RecommendationTrack` gains `tag: String?`, `details: [String]?`,
  `story: String?`, `section: String?`, with defaulted `nil` init parameters. The stage path in
  `LibraryMCPContext` (where it enriches `why` and `like` from `survivingInputs`) copies them onto
  the track, so a dropped track drops its fields with it. They're written only when set (the
  synthesized `Codable` already omits `nil` optionals); `RecommendationBatch.version` stays 1.
- **The server instructions** (`LibraryMCPServer.instructions`):
  - After "Give every discovery a one-sentence why and up to three songs in `like`.", add: "Show
    each song in chat however suits the conversation, then stage what you showed: your label for
    it as `tag`, the facts beside it as `details`, its paragraph as `story`, and its heading as
    `section`. The `story` is the same words Jon reads in chat, not a second version."
  - Replace "When you stage, show Jon each song's year and why." with "When you stage, show Jon
    each song's year, and its story or why."
  - Change "judge each against its request and song whys" to "judge each against its request and
    each song's why and tag".
  - **Stop telling the connector "no commentary fields".** The instructions end with
    `PlaylistContract.trackRules`, whose last sentence is "Do not include IDs, ISRCs, URLs, or
    commentary fields." That rule is for the `VF-PLAYLIST: v1` paste format; on the connector it
    already contradicts `why` and `like`, and it would invite the chat to leave the new fields
    empty. Split the sentence out: `trackRules` ends at "…when that version is the point, such as
    "Song (Live at the Fillmore)"."; `projectInstructions` appends "Do not include IDs, ISRCs, URLs,
    or commentary fields." as before (its text must not change); `LibraryMCPServer.instructions`
    appends "Do not include IDs, ISRCs, or URLs." instead.
  - Update the `"show Jon each song's year and why"` assertion in `LibraryMCPServerTests` to the
    new sentence. Add assertions that the instructions don't contain "commentary fields" and that
    `PlaylistContract.projectInstructions` equals a literal copy of today's text.
- **`playlist_reviews` returns each song's `tag`.** Add `tag: String?` to `MCPPlaylistReviewSong`,
  and "tag" to the tool's description ("each song's why, tag, and listening outcome"). Not
  `story`, `details`, or `section`: reviews judge the bet, and the paragraph would double the
  tokens of every review read (Decision 3).
- **The phone shows them.** `PlaylistShelfSong` (`VinylFeverNotes`) gains `tag`, `details`
  (`[String]`, empty when absent), `story`, and `sectionHeading: String?`. `PlaylistShelf.make`
  fills them with the same `nonempty` normalizing it uses for `why`, and sets `sectionHeading`
  only on the **first song of each consecutive run** of songs with the same nonempty `section`.
  Songs with no `section` get no heading, and a later run reusing an earlier heading gets it
  again. In `PlaylistSongView` and the playlist detail list:
  - **Section heading.** In the detail's `ForEach`, a song with a `sectionHeading` gets it above
    its row as a `.title3.weight(.semibold)` heading with some top padding, like the chat's "Five
    more with major upside". The existing dividers stay between songs.
  - **Tag** as a capsule pill under the artist, before the progress pill: the same font, padding,
    and shape as `PlaylistSongProgressPill`, in one fixed accent (indigo foreground on an indigo
    `opacity(0.12)` background). It must not use green or red, which mean Kept and Passed there,
    and its color never depends on the text (Decision 1).
  - **Details** joined with " · " on one `.subheadline` secondary line right under the tag,
    wrapping as needed.
  - **Story** in place of `why`: under "New to you", show `story` when there is one, else `why`
    as today. Full length, no line limit; that's what Jon reads on a walk.
  - Everything else in the row (title, artist, progress, album · year, buttons, familiarity, notes,
    "Sounds like") is unchanged. A song with none of the new fields looks exactly as it does today.
  - Accessibility: the tag pill reads as its text; the section heading has `.isHeader`.
- **Docs.** In `taste-intelligence.md`, after the "Recommendation ledger" bullet, note the four
  fields: written by the chat, optional, shown on the phone, `tag` read back by
  `playlist_reviews`. In `docs/chatgpt/music-chat/AGENTS.md`, drop "or commentary fields" from its
  copy of the track rules and add to its staging paragraph: "Stage each song's label, facts,
  paragraph, and heading as you showed them." `PLAYLIST-CONTRACT.md` is the paste format and is
  unchanged.

## Decisions

1. **The chat's words, not a taxonomy** (Jon, 2026-11-11: "I don't want to curtail the
   'creativity'"). `tag` and `section` are free text with no enum, no example list in the schema,
   and no styling keyed to their text. "Strong prediction", "Challenge track", and "Very strong
   bet" are all just tags. If a pattern earns a fixed meaning later (for outcomes by kind of bet),
   that's a new decision, not this effort's.
2. **`why` stays, and stays one sentence.** Outcomes, reviews, and Music Feedback's "why this
   song" (`WhyThisSong`) read `why`; a short, steady reason is what they compare. `story` is for
   Jon to read and is never judged.
3. **Full version, with its token cost** (Jon, 2026-11-11, choosing it over a lean version). The
   chat repeats each paragraph in the staging call: roughly 1,000 more output tokens for a 10-song
   list, which counts once ChatGPT is metered. Reviews take only `tag` so that cost isn't paid
   again on every review.
4. **Links stay out.** The chat's citations (lpm.org, YouTube) aren't verified and would add tokens
   for little on a walk. `details` is text only, and the existing contract's "Do not include …
   URLs" stands.
5. **No new iCloud format.** The ledger is append-only JSONL in iCloud Drive, with no CloudKit
   schema to deploy. The fields are optional, omitted when unset, and `version` stays 1. Older
   Mac and phone builds decode ledger lines with `JSONDecoder`, which ignores keys it doesn't
   know, so they show such a batch as they would today. The phone's shelf cache stores the batch
   as JSON, so the fields ride along with no migration; rows from an older build just lack them
   until the next refresh.

## Done when

- **`VinylFeverCoreTests` (`LibraryMCPServerTests`):**
  - **Schema.** `stage_playlist`'s track items list `tag`, `details` (`maxItems` 3), `story`,
    and `section`; none is required and none has an `enum`.
  - **Round trip.** Staging a batch whose tracks carry all four fields writes a ledger line whose
    track has them, trimmed. A track with empty strings and an empty `details` has none of the
    four keys in the written line.
  - **Caps.** A 41-character `tag`, a 1,501-character `story`, an 81-character `details` entry,
    and four `details` each come back cut to the cap with `truncated: true`.
  - **Dropped tracks.** A track the contract drops (blank artist) takes its fields with it; the
    surviving tracks keep their own, paired correctly.
  - **Reviews.** `playlist_reviews` shows a staged song's `tag`, and has no `story`, `details`, or
    `section`.
  - The updated instructions assertions pass, including `projectInstructions` unchanged.
- **`VinylFeverNotesTests`:**
  - **Golden lines.** A ledger line written before this change decodes, with the four fields
    `nil`. Encoding a track with none of them set produces exactly the keys it did before.
  - **Shelf.** `PlaylistShelf.make` copies `tag`, `details`, and `story`, and sets
    `sectionHeading` on the first song of each run only: for sections `[nil, "A", "A", "B", "A"]`
    the headings are `[nil, "A", nil, "B", "A"]`.
- **`VinylFeverMobileTests`:** the shelf cache round-trips a batch with the new fields (a cached
  shelf shows the same `tag`, `details`, `story`, and `sectionHeading` before the read returns).
- `xcodebuild -scheme VinylFeverMobile … test` and the `VinylFeverCore` and `VinylFeverNotes`
  package tests pass (per `verification.md`), and the Mac app builds.
- Closeout (ADR-0005 D16) adds the gate below to `device-passes.md`.

**What tests can't show:** whether the chat actually fills the fields with what it showed, and how
the row reads on a phone with a long story and a long tag.

**Architect probe at review:** pipe an `initialize` and a `tools/list` into the built `vf-mcp`
and confirm the new instructions and the four fields are served.

**The gate** (after install on the Mac and iPhone, in a **new** ChatGPT conversation):

1. Ask for a playlist the way Jon usually does, and let the chat label and group songs however it
   likes. Ask it to stage.
2. On the phone, open the playlist. Each song's label, facts, and paragraph match the chat's, and
   the chat's headings sit over the same songs.
3. Open a playlist staged before the install. It looks as it did.
4. After listening, ask for a review of a finished playlist. It speaks to the labels (for
   example, a pass on a song labeled a challenge).

## Out of scope

- **The Mac's Playlists view.** It shows no song reasons today; this effort doesn't add them.
- **Outcomes by tag** (does a "challenge" stick less than a "prediction"?). Free-text tags make
  that a later decision (Decision 1).
- **The paste contract (`VF-PLAYLIST: v1`).** Unchanged; it's the fallback without the connector.
- **Links and artwork from the chat** (Decision 4).
