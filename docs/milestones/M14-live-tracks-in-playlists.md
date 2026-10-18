# Milestone 14 — Live Tracks in Playlists (Jon's own uploads)

*Let a playlist mix Apple Music catalog songs with Jon's own uploaded recordings, such as the live
shows from his drives. It starts after M13 S2; see Decision 3. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: today the playlist builder (M11) only searches Apple's catalog, and the chat (M12) is
told to leave Jon's uploads out. A 2026-10-18 probe showed that the Apple Music API can find
Jon's uploaded tracks and put them in the same playlist as catalog songs, in order, in the one
create call Vinyl Fever already makes. The tracks then play on his iPhone. M14 adds a
**library route** to the resolver: when a requested track names one of Jon's uploaded albums,
Vinyl Fever finds that upload instead of a studio version. Then the chat is allowed to ask for
them. Two slices in two dispatches. No schema, no Music.app scripting, and no new credentials.

## The milestone in one sentence

"Make me a 1988 Tunnel of Love tour mix from my shows, with a few studio cuts for contrast"
should come out as one playlist, in the right order, that plays on every device.

## Evidence (probe, 2026-10-18)

Run from a throwaway build of the app, which MusicKit already authorizes; the details are in
`open-questions.md`.

- **Jon's library is in iCloud.** Of 87,100 tracks, 54,166 are uploaded, only 5 are
  ineligible, and none are waiting to upload.
- **A mixed playlist works.** `POST /v1/me/library/playlists` took catalog `songs` and
  `library-songs` interleaved (201). It kept the order sent and synced to Music.app on the Mac
  within minutes. **All the tracks played on Jon's iPhone.** Appending `library-songs` works
  too (204).
- **Uploads look different.** An upload is a `library-songs` item with an `i.…` ID and no
  `playParams.catalogId`. A catalog song Jon already owns lands as his existing library copy.
- **Song search can't be the only route.** `GET /v1/me/library/search?types=library-songs`:
  - stops at **100 results per term**, so the 101st "Thunder Road" can't be reached;
  - doesn't match album names;
  - sometimes misses a full title that a prefix finds;
  - adding the artist to the term doesn't narrow it.
  - Over a random sample of 40 uploads it found **37**. All three misses were common or very
    long titles.
- **The album route works.** Search `types=library-albums` for the album name, keep albums
  whose name matches exactly, then read `GET /v1/me/library/albums/{id}/tracks` and match the
  title. It found **all three** song-search misses, including "Thunder Road" from *6/22/03 -
  Disc 2 - Midsummer Second Night*, and 38 of the 40. Its two misses were large compilations
  where several library albums share a name; song search had found both. **Album first, then
  song search: 40 of 40.**
- **Cost:** about 3–4 requests per upload on the album route.

## The resolve flow

```
VF-PLAYLIST row (artist, title, album hint)
   │
   ├─ snapshot has an `uploaded` copy of this song on the hinted album? ──yes──▶ library route
   │                                                                              1. library-albums search on the
   │                                                                                 album hint (shorten if empty)
   │                                                                              2. every exact-name album → its tracks
   │                                                                              3. else library-songs search on title,
   │                                                                                 to Apple's 100-result cap
   │                                                                              → matched / ambiguous / not found
   └─ no ──▶ catalog route (today's M11 search and scorer, unchanged)
                 └─ not found, but the snapshot has uploads of this song?
                      → the picker offers up to 3 of those uploads (by album)
Create: one call; each ID goes in as `songs` or `library-songs`, in row order
```

## Slices

**Dispatch 1: S0. Dispatch 2: S1.** Each owes a device gate.

- [ ] **S0 — The library route (core + app).** Device gate owed.
  - **`AppleMusicCatalogClient` gains three endpoints:**
    - `searchLibraryAlbums(term)`;
    - `libraryAlbumTracks(albumID)`, which follows `next`;
    - `searchLibrarySongs(term)`, which pages up to Apple's 100-result cap.
    They return a `LibrarySongCandidate` (ID, title, artist, album, whether it has a catalog
    ID). The live values sit beside the existing ones and share the resolver's retry and
    backoff for 429 and 5xx responses.
  - **`LibraryUploadMatcher` (Core, pure).** It runs the album route, then the song-search
    fallback. Each search term is shortened a word at a time until it returns results (no
    shorter than 2 words). It keeps only candidates without a catalog ID whose title, artist,
    and album match under `SongTextNormalizer`. The outcome is matched, ambiguous (for example
    a duplicated upload), or not found with a reason, such as "Apple Music's library search
    couldn't reach this upload."
  - **The routing rule (Core, pure, over `LibraryIndex`).** A row takes the library route only
    when the snapshot has an `uploaded` track with the same normalized artist and title whose
    album matches the album hint. Every other row takes the catalog route unchanged. When a
    catalog-route row comes back not found and the snapshot holds uploads of that song, the
    existing picker offers up to 3 of them, most played first. Choosing one resolves it
    through the library route. With no snapshot, nothing changes.
  - **The model.**
    - Candidates carry a `source` (`.catalog` or `.libraryUpload`). Duplicate detection keys
      on source and ID.
    - Create and append send `songs` or `library-songs` per row, in order, in the same calls
      as today.
    - The preview badge for an upload reads "Your upload · *album*" instead of "In library" or
      "New to you". The "Remove N played ≥ 20 times" action treats uploads like any other row.

  **DoD:**
  - Matcher tests with canned API pages:
    - an album-route hit;
    - two albums with the same name where the track is on the second;
    - shortening an album term that returned nothing;
    - the song-search fallback;
    - the 100-result cap ending in not found with its reason;
    - a candidate with a catalog ID is never picked as an upload.
  - Router tests:
    - an album hint that matches an upload takes the library route;
    - a studio-album hint takes the catalog route;
    - no hint takes the catalog route;
    - catalog not found with uploads gives picker candidates;
    - no snapshot means no change.
  - Model tests:
    - the create body interleaves `songs` and `library-songs` in row order;
    - an upload duplicated in the list is caught;
    - the upload badge text;
    - append sends `library-songs`.
  - The live API calls are **unverified** in the PR.
  - **Device gate:** paste a mixed `VF-PLAYLIST` with 3 live tracks with album hints,
    including "Thunder Road" from *6/22/03 - Disc 2 - Midsummer Second Night*, and 3 catalog
    songs. The preview shows the three upload badges. Create it. It plays on the iPhone in
    order.

- [ ] **S1 — Let the chat ask for uploads (`vf-mcp` + contract).** Device gate owed.
  - **The instructions head** replaces "Tracks with availability "uploaded" are library-only
    and can't be added to a catalog playlist; leave them out." with a sentence telling the
    model it can use one of Jon's own uploads, such as a live show, by giving its exact album
    from the library as the album hint. The head must still stand alone in 512 characters, and
    the pinned test is updated.
  - **`check_tracks`** gains `uploadedAlbums` for each song: up to 5 album names of its
    uploaded copies, most played first. Then the model can pick a show without another call.
  - **`PlaylistContract.trackRules`** gains one sentence: "For one of Jon's own recordings,
    such as a live show, set album to the exact album name from his library." That text is
    shared with the ChatGPT Project contract, so `PLAYLIST-CONTRACT.md` is updated and stays
    pinned byte for byte. Jon re-copies the Project instructions from Settings once.
  - The `~/music-chat` template in `MCP-SETUP.md` says the same.

  **DoD:**
  - The instruction pins: the head stands alone, and the new sentence is present.
  - `check_tracks` returns `uploadedAlbums` against the fixture, with no IDs in the output.
  - The contract pin is updated with `PLAYLIST-CONTRACT.md`.
  - **Device gate:** in ChatGPT on the iPad, ask for "a 1988 Tunnel of Love tour mix from my
    shows plus a few studio cuts". It calls `check_tracks`, then stages; the list appears under
    From chat with upload badges; Create; it plays on the iPhone.

## Prerequisites (Jon)

- [x] Sync Library is on and the shows are uploaded (54,166 uploaded, 2026-10-18).
- [x] No new App ID, profile, or entitlement: the existing MusicKit authorization covers the
  library endpoints (shown by the probe).
- [ ] After S1: re-copy the ChatGPT Project instructions from Settings.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Shortest search term | 2 words | Shorter terms return too much to be useful. |
| Song-search depth | Apple's cap (100 results, 4 pages) | There's nothing past it. |
| Upload candidates in the picker | 3, most played first | The same limit as the catalog picker. |
| `uploadedAlbums` in `check_tracks` | 5 | Enough to choose a show, and small. |
| Request concurrency | the resolver's existing limit | Library calls share its backoff. |

## Out of scope — with destinations

- **The 5 `ineligible` tracks** (never uploaded, Mac-only). The API can't see them. → Not
  planned; they'd need Music.app scripting.
- **Sharing.** Uploads are private to Jon: a shared playlist won't play them for anyone else.
  → No.
- **A full crawl of library IDs** (`/v1/me/library/songs`, about 870 requests). → Only if the
  gate shows the two routes missing real requests (Decision 1).
- **Storing library IDs in the snapshot.** Music.app's scripting doesn't expose `i.…` IDs, so
  the snapshot can't hold them. → No.
- **Official live releases in the catalog** (for example Springsteen archive releases). → The
  catalog route already handles them. An album hint naming a catalog album goes to the
  catalog.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves the
recommendations. It doesn't dispatch anything: M13 goes first.

1. **Album search first, song search as the fallback, and no crawl.** Together they found 40
   of 40 sampled uploads, at about 3–4 requests per upload. A crawl would cost about 870
   requests and its own cache to keep fresh, for no measured gain.
2. **Use the library route only when the album hint names an upload.** Guessing intent from
   the title alone would turn every request for "Thunder Road" into a choice among hundreds
   of shows. The explicit hint keeps today's catalog behavior for everything else. The
   not-found fallback catches requests that didn't name a show.
3. **Order: M13 S0 → S1 → S2, then M14, then M13 S3.** Jon wants this after the poller
   (2026-10-18). M13 S2 and M14 S1 both edit `vf-mcp`, so they run one after the other.
   M13 S3 (Vinyl Fever's own backup poller) is the least urgent, so it goes last.
4. **Change the shared contract sentence rather than add a format field.** `VF-PLAYLIST: v1`
   already carries `album`. Saying how to use it for uploads avoids a v2 and keeps old pastes
   valid.
