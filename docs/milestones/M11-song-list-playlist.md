# Milestone 11 — Song List → Apple Music Playlist

*Build a playlist with ChatGPT, paste its output into Vinyl Fever, review every
catalog match, and create an Apple Music library playlist from the confirmed songs.
Dispatch 1 is the current `NEXT_UP.md`. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those
conflict, stop and flag it.*

Summary: Paste a ChatGPT-emitted playlist (pinned `VF-PLAYLIST: v1` JSON contract from a Project),
match each track against the Apple Music catalog with a tested scorer, preview, and create a library
playlist via the Apple Music API. Three slices in two dispatches (S0 core decoder + scorer; S1 + S2
live client and a Playlists sidebar area). No schema. Dispatch 1 (S0) is set as `NEXT_UP.md`.

## The milestone in one sentence

A ChatGPT Project carries a versioned **playlist contract** (generated from one Core
constant, copied from Settings). When asked, ChatGPT returns a marker line plus one
JSON object. Vinyl Fever decodes it strictly and searches the Apple Music catalog for
each track through a new `AppleMusicCatalogClient`. It scores the candidates into
**matched / ambiguous / not found**, and after a mandatory preview one Apple Music
API call creates the playlist in Jon's library.

## Why this shape

- **Pin the format at the source instead of parsing whatever arrives.** Yes Chef
  (Recipe JSON-LD, `YC-RECIPE-CONTRACT`) and Galavant (`GV-CONTRACT`) have shown that
  ChatGPT reliably returns a pinned structured value when the contract lives in
  **Project Instructions**, is generated from a Core constant, and carries a version
  marker (yes-chef ADR-0042 D4). That turns the input side into a strict decode:
  artist and title arrive as separate fields, so there's no guessing which side of
  a dash is which, no stripping of list markers, and no separating prose from songs.
  The lossless-or-loud rule applies: a paste that isn't the contract fails visibly;
  it's never salvaged into a guessed list.
- **Converse freely; only the final reply is structured** (yes-chef ADR-0042 D1).
  Jon argues about the list in the chat as long as he likes. The contract governs
  only the turn where he asks for the playlist: that reply is a value, not
  conversation.
- **Matching is still the real work.** A pinned format fixes parsing, not
  facts: the LLM can still invent a song, credit the wrong artist, or leave the
  version ambiguous against a catalog full of karaoke, tribute, and live copies.
  The contract helps by asking for `album` and `year` as optional hints, which the
  scorer uses as tie-breakers, and by the no-invention rule ("omit a track you
  aren't sure exists as described"). Matching stays pure core logic tested with
  fixtures. Only a thin live client touches MusicKit.
- **MusicKit can't create playlists on macOS, but the Apple Music API can.**
  `MusicLibrary.createPlaylist` and `add(_:to:)` are `macOS, unavailable`. The
  working route on the Mac is `POST https://api.music.apple.com/v1/me/library/playlists`,
  sent through `MusicDataRequest`, which attaches the developer and user tokens
  itself. Catalog search is native MusicKit on macOS
  (`MusicCatalogSearchRequest`).
- **Hand-roll the client; don't add MusadoraKit as a dependency.** MusadoraKit
  (`rryam/MusadoraKit`, MIT) is ~13k lines. The only piece this milestone needs
  on macOS is the playlist-create POST: ~60 lines of request structs plus a
  `URLRequest` handed to `MusicDataRequest`. Adapt its
  `LibraryPlaylistCreationRequest` JSON shape and `MusicPostRequest` technique, with
  an attribution comment. Surface status and error bodies (its `add(songIDs:to:)`
  reduces them to a `Bool`) so the UI can say *why* (no subscription, Sync Library
  off).
- **Reuse the house handoff marker; skip the session machinery.**
  `jon-platform/packages/LLMHandoffKit`'s `HandoffContractMarker` already does
  "strip the marker line; missing or older is a warning, newer is a hard stop." A
  playlist paste has no originating session to route back to, so
  `HandoffSession`/routing are unused.
- **No schema.** A playlist build is a one-shot operation, not state the app keeps.
  Nothing persists except the playlist in Apple Music. This keeps the milestone clear
  of D9's schema escalation trigger.

## The contract (v1)

The Core constant `PlaylistContract` is the single source for the instruction text,
the marker, and the decoder. `docs/chatgpt/PLAYLIST-CONTRACT.md` is a checked-in copy
that a test asserts matches the constant byte for byte. It is what Jon pastes into
the Project.

Wire shape (marker line, then exactly one JSON object; no code fence, no prose):

```
VF-PLAYLIST: v1
{"name":"Late-70s Power Pop Deep Cuts","description":"optional one sentence","tracks":[{"artist":"The Records","title":"Starry Eyes","album":"The Records","year":1979},{"artist":"Shoes","title":"Too Late"}]}
```

- `name` required; `description` optional; `tracks` ordered, ≥ 1.
- Each track: `artist` and `title` required; `album` and `year` optional hints.
  `year` is the original release year.
- The instruction rules, kept to those with evidence behind them (ADR-0042 D4):
  - Straight ASCII quotes.
  - No code fence, preamble, or sign-off.
  - Omit a track you aren't confident exists as a released recording by that
    artist; don't substitute.
  - Name a specific version in the title only when that version is the point
    (`"… (Live at the Fillmore)"`).
  - No IDs, ISRCs, URLs, or commentary fields.
- Trigger: a reply is a playlist block only when Jon asks for one ("emit the
  playlist"). Otherwise the Project behaves conversationally.

## The spine

```
ChatGPT Project (contract v1) ──emit──▶ pasted text
            │
            ▼
PlaylistContract.decode  (marker via HandoffContractMarker; strict JSON;  (core, pure)
            │              smart-quote / stray-fence recovery only)
            ▼
      PlaylistRequest { name, description?, tracks: [TrackRequest] }
            │
            ▼
      CatalogMatchResolver ── searchSongs ──▶ AppleMusicCatalogClient (live: MusicKit)
            │   scores via CatalogMatchScorer    (core, pure)
            ▼
      [ResolvedRow: matched | ambiguous([candidates]) | notFound]
            │
            ▼
      preview (Playlists area) — Jon picks/re-searches/removes, edits name; Create needs ≥ 1 matched row
            │
            ▼
      createLibraryPlaylist(name, description, catalogSongIDs) ─▶ CreatedPlaylistRef
            │
            ▼
      leftover rows stay fixable ── appendToLibraryPlaylist(id, catalogSongIDs) ─▶ same playlist
```

Core value types, as a sketch. Refine them in code and flag big changes.

- `TrackRequest { index: Int; artist: String; title: String; album: String?;
  year: Int? }`.
- `CatalogSongCandidate { id: String; title: String; artistName: String;
  albumTitle: String?; releaseDate: Date?; durationSeconds: Double?; isrc: String? }`.
  This is a plain value type. MusicKit's `Song` never crosses into core.
- `MatchOutcome`: `.matched(CatalogSongCandidate, score)`,
  `.ambiguous([ScoredCandidate])` (top 3), or `.notFound`.

## Slices

**Dispatch 1: S0.** It stands alone because the scorer's quality could change
S1/S2. **Dispatch 2: S1 + S2.** They share the live client and the feature model.
Dispatch 2's gate is owed on Jon's Mac.

- [ ] **S0 — Contract + decoder + scorer (core, no MusicKit, no UI).**
  - Add `jon-platform/packages/LLMHandoffKit` as a path dependency of
    `VinylFeverCore`, mirroring the existing `LLMClientKit` entry.
  - `PlaylistContract`: `marker = HandoffContractMarker(prefix: "VF-PLAYLIST",
    version: "v1")`, `projectInstructions: String`, and
    `decode(_ pasted: String) throws -> (PlaylistRequest, warning: String?)`.
    - Decode strips the marker, then any wrapping code fence, then normalizes
      typographic quotes. Yes Chef salvages these the same way, as a recovery path
      and not a format to rely on.
    - Anything else that isn't valid JSON in the shape throws a typed, readable
      error. There is no fallback free-text parser.
    - Trim fields. Drop tracks with an empty artist or title and report them in the
      result; never pass them on silently.
  - Check in `docs/chatgpt/PLAYLIST-CONTRACT.md`.
  - `CatalogMatchScorer`: `TrackRequest` × `[CatalogSongCandidate]` → `MatchOutcome`.
    - Normalize both sides: case-fold, strip diacritics, collapse `&`/`and`, drop
      `feat./ft./with …`, and strip remaster parentheticals.
    - Score title and artist similarity.
    - Apply the version penalty (constants) unless the request names that version.
    - Boost an `album`/`year` match. Break ties by earliest `releaseDate`.

  **DoD:**
  - `swift test` is green.
  - Decoder tests cover: clean block; missing marker → decodes with a warning;
    newer marker → hard stop; fenced and smart-quoted paste → recovered; prose-only
    or malformed JSON → typed error; empty-field track → dropped and reported.
  - A test pins `docs/chatgpt/PLAYLIST-CONTRACT.md` byte-equal to
    `projectInstructions`.
  - Scorer tests use hand-built candidate lists and cover:
    - exact match → `.matched`;
    - karaoke/tribute/live in the candidates (not requested) → the studio original
      wins;
    - "Live" in the request → the live candidate wins;
    - the album/year hint breaks a same-title tie;
    - two close candidates → `.ambiguous`;
    - nothing close → `.notFound`.
- [ ] **S1 — `AppleMusicCatalogClient` + resolver (core interface, app live impl).**
  - Core `@DependencyClient` (shaped like `MusicAppClient`):
    - `authorizationStatus()` and `requestAuthorization()`;
    - `subscriptionStatus()`, which returns `canPlayCatalogContent` and
      `hasCloudLibraryEnabled` from `MusicSubscription`;
    - `searchSongs(term:limit:) -> [CatalogSongCandidate]`;
    - `createLibraryPlaylist(name:description:songIDs:) -> CreatedPlaylistRef`;
    - `appendToLibraryPlaylist(id:songIDs:)`. The same `…/tracks` call the chunking
      already uses, exposed so S2 can add rows that were fixed after Create.
  - Live impl in `VinylFever/Clients/AppleMusicCatalogClient+Live.swift`, the only
    file that imports MusicKit. Create posts the first chunk of IDs in
    `relationships.tracks`, then appends the remaining chunks via
    `…/playlists/{id}/tracks`. A non-2xx response throws a typed error that carries
    the status code and the API's `errors[].detail`.
  - Core `CatalogMatchResolver`: `PlaylistRequest` → `[ResolvedRow]`. It searches
    `"\(artist) \(title)"` with bounded concurrency, feeds the scorer, and removes
    duplicate catalog IDs (keeping the first occurrence and noting the dropped row).
  - Add `NSAppleMusicUsageDescription` to `project.yml` info properties.

  **DoD:**
  - Resolver tests use a stubbed client and cover: concurrency cap respected; order
    preserved; duplicates removed with a note; a search error on one row marks that
    row `notFound(error)` without failing the batch.
  - Live create is **unverified** in the PR.
  - **First live call is a smoke test.** If a catalog search fails with a
    developer-token error, stop and flag it. That means the portal step below is
    missing, not a code bug.
- [ ] **S2 — Playlists sidebar area: paste → preview → create, plus Settings copy (app).**
  - Add a fourth sidebar section, **Playlists**, next to Live Shows, Collections, and
    Policies (`AppShellView`'s section enum → a new `PlaylistsView`).
  - Back it with a `PlaylistBuilderModel` (`@Observable`, **its own feature model**,
    not more code in the 2.3k-line `AppModel`). The app shell owns it, so an
    in-progress build survives switching sections. It isn't persisted: quitting
    discards it (no schema).
  - The area has a paste box and a Resolve button. A decode error or marker warning
    shows inline, with a "re-copy the instructions from Settings" fix for a stale
    Project.
  - The preview shows the name and description (both editable) and a per-row
    status table:
    - ambiguous rows show a picker of the top 3 with album and year;
    - not-found rows can be re-searched with an edited term;
    - every row can be removed;
    - tracks dropped by the decoder are listed.
  - **Unresolved rows don't block Create** (Jon, 2026-10-14). Create needs at least
    one matched row. When rows are still unresolved, Create says so before it runs
    ("Create with 18 of 20 tracks; 2 unresolved will be skipped"), and those rows
    are excluded.
  - **Unresolved rows stay fixable after Create.** The result state keeps the
    leftover rows in the same table. Picking a candidate or re-searching a row and
    choosing **Add to Playlist** appends it to the playlist just created through
    `appendToLibraryPlaylist`. Appended tracks go at the end, not in their original
    position; the UI says so, and reordering happens in Music.app. A new paste or
    **Start Over** ends that session.
  - Before resolving, check authorization and subscription. Blocking banners cover
    not authorized, no subscription, and Sync Library off, each with the fix.
  - The result state shows the playlist name and track count, plus a note that it
    appears in Music.app after iCloud sync.
  - Settings gets a **"Copy ChatGPT Project Instructions"** button that copies
    `PlaylistContract.projectInstructions`. Also add a short `docs/chatgpt/SETUP.md`,
    the operator guide modeled on Yes Chef's `CHATGPT-SETUP.md`: create the
    **"Vinyl Fever Chat"** Project, where to paste the instructions, and a smoke test.

  **DoD:**
  - Model-level tests with a stubbed client:
    - a valid paste fills rows; a malformed paste shows the typed error and makes no
      search calls;
    - picking a candidate resolves a row;
    - Create is disabled with zero matched rows and enabled with one or more;
    - Create passes the edited name and only the matched rows' catalog IDs, in order;
    - a row fixed after Create calls `appendToLibraryPlaylist` with the created
      playlist's ID, and leaves the table once added;
    - each gating state blocks Resolve with its message.
  - The view code itself goes untested.
  - **Owed device gate:** on Jon's Mac, install the contract in "Vinyl Fever Chat",
    discuss a list, emit it, paste, resolve, and create while leaving one row
    unresolved. Fix that row and add it. Confirm the playlist appears in Music.app
    with the right songs, the fixed one appended at the end. Then delete it by hand
    (the API can't).

## Prerequisites (Jon, before Dispatch 2 — not the executor's)

- Enable the **MusicKit** App Service for `com.jonphillips.vinylfever` (lowercased in #64; register it as a new App ID)
  (developer.apple.com → Identifiers). Without it, `MusicDataRequest` has no
  developer token to attach.
- Apple Music subscription with **Sync Library** on (already true for daily use).
- A ChatGPT Project named **"Vinyl Fever Chat"**, with the contract pasted into its
  Project Instructions once S2 lands (per `docs/chatgpt/SETUP.md`).

## Constants register (starting values; tune against real emitted lists)

| Constant | Value | Rationale |
| --- | --- | --- |
| Contract marker | `VF-PLAYLIST: v1` | Same `PREFIX: vN` shape as `GV-CONTRACT`/`YC-CONTRACT`, so `HandoffContractMarker` handles it unchanged. |
| Search result limit | 10 | Enough to get past karaoke and tribute clutter to the original. The API caps song search at 25. |
| Search concurrency | 4 | The Apple Music API's rate limits aren't published. A 50-song list resolves in a few seconds without bursting. |
| Auto-match threshold | score ≥ 0.90 **and** ≥ 0.10 ahead of #2 | Auto-accept only a clear, unique winner. Anything close goes to Jon. |
| Ambiguous floor | score ≥ 0.60 | Below this, top-3 suggestions are noise. Call it not found and let Jon edit the term. |
| Version penalty | −0.30 each | Tokens: `live`, `karaoke`, `instrumental`, `tribute`, `originally performed`, `cover`, `remix`, `acoustic`, `demo`, `sped up`, `slowed`. Big enough to push a karaoke exact-title hit below the studio original. Waived if the request contains the token. |
| Album/year hint boost | +0.05 each | A tie-breaker, not a driver. A wrong hint from the LLM must not override a strong artist/title match. |
| Tracks per create/append request | 100 | Apple doesn't document the cap. Splitting into chunks costs nothing and avoids a silent truncation. |

## Out of scope — with destinations

- **Free-form list parsing** (pastes from a chat without the contract). The
  fallback is Yes Chef's: paste `PLAYLIST-CONTRACT.md` into that one-off chat
  first. → revisit only if Jon regularly wants lists from outside the Project.
- **A routed handoff** (VF → ChatGPT with context, e.g. "extend this playlist").
  `LLMHandoffKit`'s session and routing would fit, but nothing needs it yet.
- **Library-only tracks** (live shows, bootlegs, anything not in the catalog). They
  need the AppleScript `MusicAppClient` surface, and mixing them into an API-created
  playlist fights iCloud sync lag. → a later milestone if Jon's playlists turn out
  to need them.
- **Generating the list inside VF** via `ModelClient`. The deliberation belongs in
  the chat app, where it's unmetered and you can argue with it (ADR-0042 D2).
- **Editing, reordering, or deleting existing playlists.** The API only creates and
  appends. Reordering happens in Music.app.
- **Appending to an older playlist** (anything other than the one this session just
  created). The API supports it, but choosing a target
  needs a library-playlist picker. → fast-follow if asked.
- **Smart playlists / Collection Policy binding.** This is a manual, ordered list;
  per `metadata-policy-model.md`, "use manual playlists when order matters."

## Decisions

Resolved (Jon, 2026-10-14):

- **Sequencing:** after M6 · S2. M6 · S2 turned out to be already done (#35/#50), and the
  one-true-import-folder effort is in review as #65, so Dispatch 1 is next.
- **Wire format:** JSON (marker line + one object), as specified in *The contract*.
  Labeled lines were the alternative; they suit Yes Chef's case where the human edits
  the raw text, and here review happens in the preview table.

- **ChatGPT Project:** a dedicated Project named **"Vinyl Fever Chat"**. Its only
  standing job is the playlist contract.
- **Where it lives:** a fourth sidebar area, **Playlists**, not a sheet.
- **Unresolved rows at Create:** they don't block Create, as long as Jon can still fix
  them. Before Create, any row can be picked, re-searched, or removed. Create runs with
  the matched rows and says how many it skipped. Afterwards, the leftover rows stay
  fixable and **Add to Playlist** appends them (the API can append, though it can't
  remove).

Nothing is open. Dispatch 2 waits only on the MusicKit App ID prerequisite.
