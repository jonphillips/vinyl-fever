# Open Questions

The architect's and Jon's scratch pad: candidates, parked work, and decisions for Jon's review.
**The executor never reads this file** (jon-platform ADR-0005). Work becomes dispatchable only when a
plan PR moves it into a milestone or effort and sets `docs/NEXT_UP.md`.

## Candidates & parked work (moved from `CURRENT_HANDOFF.md`, 2026-09-29)

- **M4 Reconcile fast-follow** — re-point the registry entry when identity drift is found, and sharpen
  same-title/different-owner duplicate detection
  ([ledger](milestones/M4-compilation-album-append.md)). **Evidence-gated by design:** build it only when
  a real append spawns a `Great Covers 2` drift. None observed in daily use yet.
- **Pending Jon decision — M4 identity-drift (#2/#3).** Decide identity-match forgiveness and no-match
  behavior *when* a real append mangles a title. Parked until the evidence appears.
- **LLM song list → Apple Music playlist** — [M11](milestones/M11-song-list-playlist.md) shipped
  in #66 (S0) and #67 (S1 + S2, merged 2026-10-15). Jon passed the on-device gate on
  2026-10-17. Settled in the feasibility pass: hand-roll the Apple
  Music API create call rather than depend on MusadoraKit; catalog-only for v1; input is a
  pinned ChatGPT Project contract (`VF-PLAYLIST: v1`, Yes Chef/Galavant pattern), not free-text
  parsing.
- **Library context for the playlist chat** — [M12](milestones/M12-library-context-mcp.md)
  **closed 2026-10-18.** The shared `MCPServerKit` effort (jon-platform#74), S0 + S1 (#72), and
  S2 (#76, `vf-mcp` and the playlist inbox) shipped with their device gates passed, and the
  close-out PR folded in the gate's fixes. Decision 1 is **no**: Last.fm (S3) is dropped in
  favor of Apple's recently-played feed ([M13](milestones/M13-listening-history.md)). A Yes
  Chef MCP server, reading its synced database read-only, is the likely second `MCPServerKit`
  consumer and starts by spiking app-group container access (ADR-0007 *Open*). Galavant waits.
- **Listening history** — planned as [M13](milestones/M13-listening-history.md) (2026-10-18):
  an hourly poller of Apple's recently-played feed. It runs as a separate macOS 26 app on the
  Intel Mac mini, with the same engine inside Vinyl Fever for the laptop now and an
  Apple-silicon mini later. The log lives in iCloud Drive, and `vf-mcp` gains
  `recent_listening` and periods. Merging that plan PR approves its Decisions 1–5 and
  dispatches S0. S0 landed in #83 (2026-10-18). Dispatch 2 (S1) needed only the developer-portal
  App ID and profile, which are done. Owed by Jon before the S1 gate: the mini's macOS 26
  check, Optimize Mac Storage off, and adding the mini to the profile (M13 *Prerequisites*).
  The mini is on the profile as of 2026-10-19. The mini's last macOS turned out to be 15
  Sequoia, not 26, so Decision 2 was amended the same day. The poller and
  `VinylFeverListening` (now its own package) target macOS 15. The probe evidence moved into the milestone.
- **Listening analytics: what the log is for** (Jon, 2026-10-20). The M13 log is gathering
  data before there's an analytical strategy, and Jon is fine with that. Directions he named:
  - **Varying his listening:** what he's been on, and how to steer him away from ruts.
  - **Heard, then chosen:** which recently played songs he then added to a playlist. That's a
    much stronger signal than a play, and Vinyl Fever sees the playlist side (M11, M14).

  **Parked: filtering short plays.** The feed counts starts (M13 *Fidelity*). Polling every
  couple of minutes could estimate listened time from the gap between one song's appearance
  and the next. It can't size the last song of a session, and Jon didn't want the request rate
  or the precision before a use exists. Revisit when an analysis needs listens rather than
  starts.

  The analytical strategy is now the *Taste Intelligence* candidate below.
- **Taste Intelligence** — candidate v1 design in [taste-intelligence.md](taste-intelligence.md)
  (Jon and the architect, 2026-10-20, from a Codex brief). Vinyl Fever learns Jon's taste from
  evidence he already produces and lets the chat do the reasoning, aiming at "15 songs I
  probably don't know but will love, explained, and learn which stick." Key findings:
  - Explicit signals are nearly unused: 19 favorites, 4 dislikes, 70 ratings in 87,114 tracks.
  - **Jon's Selections** (2021–2026, 512 songs) is the strongest signal: songs from the current
    year he adds as he hears them.
  - **Replay** 2018–2026 is in the library now, ranked; pre-2018 data is a shared family
    account and is excluded.
  - **New Music** is graded in full every week, so kept vs passed is a real contrast, and its
    keep rate is Apple's discovery yield, the baseline to beat.
  - Keep is Jon's native add to Selections, and Pass is inferred from New Music heard and not
    added, so neither needs a tap. One shortcut, **VF Note**, captures his spoken reasons from
    CarPlay, Siri, or the Action button, with no iOS app. `Get Current Song` is blank on a first
    hearing (it fills in only after the queue moves on), so the shortcut falls back to Shazam's
    `Recognize Music`, then to the time alone.

  Candidate phasing: S0 probes, S1 playlists in the snapshot with roles, S2 feedback (VF Note
  and chat notes), S3 exposure and curation logs, then an outcomes milestone. It follows M14 S1; where
  M13 S3 falls is Jon's call.
- **Live tracks in playlists** — planned as [M14](milestones/M14-live-tracks-in-playlists.md)
  (2026-10-18). It interleaves with M13: S0 after M13 S1, S1 after M15 S0 (order amended
  2026-10-20, M14 Decision 3). Probes on 2026-10-18 showed:
  - One API create call mixes catalog songs with Jon's uploaded live tracks, in order, and they
    play on his iPhone (Jon checked).
  - Library song search stops at 100 results per term, but searching his library's albums by
    the show's name and then reading the album's tracks reaches every upload. The two routes
    together found 40 of 40 sampled uploads.
  - Jon's library: 54,166 uploaded, 26,977 matched, 5 ineligible, and none waiting to upload.
    Uploaded plus matched is about 81,000, against iCloud Music Library's 100,000-song limit.
  - The full evidence is in the milestone. Merging that plan PR approves its Decisions 1–4.
    M13 S1's completing PR (#85) dispatches M14 S0.
  - **S0 merged as #89 and its device gate passed (2026-10-20).** The review added Decision 5:
    on the library route, artists match by whole-word prefix, because most of Jon's uploads
    carry variants such as `… & The E Street Band (Live)`. S1's `uploadedAlbums` uses the same
    rule.
  - **Decision 5 is superseded by [M15](milestones/M15-artist-identity.md)** (2026-10-20), which
    gives every artist comparison one `ArtistIdentity`.
  - **S1 merged as #97, and its device gate passed (2026-10-20). M14 is complete.** The gate's
    Tunnel of Love mix led to the library duplicates report below.
- **Artist identity** — planned as [M15](milestones/M15-artist-identity.md) (2026-10-20), after
  Jon asked why artist matching kept coming back. A probe of his 87,115-track library found
  three kinds of mismatch: band and live suffixes (34,909 tracks across 293 keys), spelling
  noise ("The" and apostrophes), and true aliases (44 overlap candidates, about half real). S0
  is one rule with duet credits. S1 is an alias list Jon approves in Settings. The order is
  M13 S2 → M15 S0 → M14 S1 → M15 S1 → M13 S3, so M13 S2's completing PR (#93) dispatches
  M15 S0.
  - **S1 (#101) went back for changes (2026-10-20).** On the real snapshot its finder returned
    2,958 candidates, because the joined-words rule had become a prefix rule. A Different click
    could also delete an accepted alias. Jon approved the schema fix: one row per
    (variant, canonical) pair, with one accepted alias per variant. The milestone now adds an
    inserted-word shape and expects about 100 candidates at the gate.
- **Adding an artist alias by hand** (from the #101 review, 2026-10-20). M15 S1's finder can't
  propose an alias without evidence in the library. `john cougar` (4 remixes) shares no titles
  with `john mellencamp`, and `on a friday` (Radiohead's early name) shares 3 titles, one short
  of the threshold. Both are real aliases that Jon would have to type himself.
  - **Candidate:** an **Add alias…** button in the Artist Aliases sheet. Jon types two
    spellings, and the decision goes through the same store rules as an accepted candidate:
    base keys, no chains, re-pointing.
  - **Decide after S1's gate**, once Jon has seen what the finder misses. If it's only these
    two, a seeded pair or a one-off decision row is simpler than new UI.
- **Library duplicates report** (Jon, 2026-10-20, from the M14 S1 device gate). Jon asked for a 1988
  Tunnel of Love mix. Two rows went to the picker: Roulette and Chimes of Freedom. ChatGPT had
  sent the exact album, `1988‐07‐03: Stockholms Stadion, Stockholm, Sweden`, with U+2010 hyphens.
  But Jon's library holds that show twice: that copy, plus `1988-07-03 - Stockholms Stadion -
  Stockholm, Sweden`, with 35 tracks each. A third copy is tagged `Summer Night - Cd1 (Stockholm -
  July,3,1988)`. Under `SongTextNormalizer.album` the first two names are identical, so the
  matcher returns ambiguous. Jon would rather see these duplicates than have Vinyl Fever hide them.
  - **Rough size (architect's probe of the snapshot):**
    - 72 uploaded album names (1,237 tracks) collide once case and punctuation are ignored. Some
      are real splits, such as `Moanin' & Howlin'` / `Moanin' And Howlin'` and
      `2019-12-20 Harrisburg, PA` / `2019/12/20 Harrisburg, PA`. Some are different artists'
      albums with the same title, such as `Greatest Hits`.
    - 129 artist-and-date pairs have differently named albums. This count is crude: a date
      regex and a rough artist key.
  - **Candidate:** a read-only report, built from the snapshot, that groups likely duplicate
    uploads by `ArtistIdentity` key with either the normalized album or the show date. Jon fixes
    them in Music.app. Possible surfaces: a Settings sheet like M15 S1's alias review, or a
    `vf-mcp` tool ("what's duplicated in my Springsteen shows?").
    - It needs a decision on scope: duplicates only, or also near-duplicate album splits such as
      case-only differences.
  - **Decided (Jon, 2026-10-20): no exact-album tiebreak in the matcher.** Preferring the
    upload whose raw album equals the hint would resolve these rows silently and hide the
    duplicates. The picker stays as it is.
- **M11: Create can lose the playlist it just made when a later batch fails** (from the #67
  review, 2026-10-15). `createLibraryPlaylist` sends the first 100 IDs with the create call,
  then appends the rest in batches of 100. If a later batch throws, the error drops the
  `CreatedPlaylistRef`. The model then shows no playlist, and Create again makes a second one.
  This only affects playlists over 100 songs. Candidate fix: throw a typed partial-create error
  that carries the ref and the unsent IDs, so the model enters the post-Create state with those
  rows left over. Low priority until Jon builds a playlist that long.
- **App-target test failing on `main`: `CollectionInboxAppendTests`** (found in the #67 review,
  2026-10-15). `resumingInboxRebuildsFromStagedFilesAndClearsDerivedFolders` hits an
  unimplemented `@Dependency(\.uuid)` (reached through `FileSystemClient`) and fails. It most
  likely dates from #60/#65. It went unnoticed because the executor's host runs macOS 26.6,
  which only compiles the app test bundle; the architect's macOS 27 host is the only place it
  runs. Candidate fix: a one-line `$0.uuid = .incrementing` override in that test. It's small
  enough to fold into the next dispatch that touches the Inbox, or to send as its own small
  effort.
- **Folder-picked compilation appends leave derived folders behind** (from the #65 review,
  2026-10-14). A compilation append builds `Working/` and `Output/` *inside* the user's picked
  folder, and after #65 `Output/` holds a copy of every track. Nothing cleans either one up after
  certify (Inbox appends are drained; live shows have `cleanUpProducedFolders`). Candidate effort:
  offer the same certify-gated cleanup for folder-picked appends, or build them under an
  app-owned scratch root instead of the user's folder.
- **M12: is the 30 s read budget still right for an 87k-track library?** (from the #72 review,
  2026-10-17). **Recommendation: keep the budget and watch it;** revisit if a refresh fails or the
  library grows. M12 assumed about 30k tracks; Jon's library is 87,100, and a full snapshot
  refresh measured 21–25 s at the S1 gate. That leaves about 5 s of headroom.
- **M12: should the launch refresh skip when Music.app isn't running?** (from the #72 review,
  2026-10-17). **Recommendation: yes;** launch refreshes only when Music is already running, and
  the manual **Refresh Library Snapshot** button stays the way to launch it. Today a snapshot
  older than 6 h makes Vinyl Fever launch Music.app at its own launch. Pending Jon.
- **M12: what to do with `LibrarySnapshot.lastfm` now that S3 is dropped** (from the #72
  review, 2026-10-17; updated 2026-10-18). It's typed `Data?`, which would encode as base64, and
  it's always `null`. **Recommendation:** leave it. Drop the field at the next snapshot format
  bump; nothing reads it.
- **M12: sign `vf-mcp` for a distributed build** (from the #76 review, 2026-10-17). The app
  bundles the helper at `Contents/Helpers/vf-mcp` from a post-build `swift build`, and the
  linker only ad-hoc signs it. That's fine for local builds: the app's
  `codesign --verify --deep --strict` passes. An archived or notarized build would need the
  helper signed with the team identity and the hardened runtime before the app is signed.
  **Recommendation:** nothing until Vinyl Fever is archived for anyone but Jon. Then the build
  phase runs `codesign --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime` on the helper.
- **M12: a release build of `vf-mcp` takes about 5 minutes** (from the #76 review, 2026-10-17).
  The Release post-build phase does a full `swift build -c release` of the helper and its
  dependencies in its own scratch path. Debug builds take about 30 s. That only costs Release
  builds and archives today. **Recommendation:** watch it. If archives get frequent, cache the
  scratch path across builds, or build the helper as an Xcode target in the same build graph.

## V1 Scope

- Which existing script is most important after `music_pipeline.sh`?
- Which remaining steps truly need shell/Python rather than Swift?

## Live Show Prep

- Are the default live-show album title rules in `setlist-formatting-rules.md`
  complete?
- Are the source labels in `setlist-formatting-rules.md` complete, or should
  additional defaults such as `WEB`, `MTX`, or others be added?
- Resolved: see "Verified" in [App Areas](app-areas.md) and Source Of Truth And
  Storage Ownership in [Metadata Policy Model](metadata-policy-model.md). A show
  is verified when its album appears in the Apple Music scan with a matching
  album title and a track count equal to the setlist, with an optional duration
  spot check.
- What Apple Music fields/data should identify an imported album as a live show
  for the chronological artist view?
- What should the local-model live-show label audit flag as "probably mislabeled"?
- Resolved (2026-07-03 review): see *Automation Implications* in
  [Setlist Formatting Rules](setlist-formatting-rules.md). The Normalizer is a
  sandwich — deterministic pre-segment (clean + region hints, no decisions) ->
  frontier LLM via `ModelClient` (all semantic judgment, emits structured JSON)
  -> deterministic validate (tags, ALBUM/DATE shape, controlled source vocab, no
  invented source, track-count sanity) -> mandatory human preview. Source of
  truth is what's on the media, not a reconstructed show. Buildable now,
  independent of the M3 beta-3 pause.
- Resolved: the interactive review session ran 2026-07-03 against a 18-file raw
  corpus; outcomes folded into *Automation Implications*. The rules body remains
  open to revision, but the automation boundary is settled.

## Collection Policies

- What are the first Collection Policies to model?
- Should a policy target an Apple Music playlist, a Smart Playlist rule, or both?
- Is ` | ` the final delimiter for multiple Grouping tokens?
- What should happen when imported files already have Grouping values?
- What should the first folder-application workflow do when a folder contains
  mixed artists or already-tagged songs?
- Which fields can a policy change automatically?
- Which fields always require review?

### Compilation-Album (Append) Policy

- Resolved direction: see *Compilation-Album (Append) Policy* in
  [Metadata Policy Model](metadata-policy-model.md). VF appends tracks to
  curated albums that already exist in Apple Music; it never creates albums or
  the silent cover-carrier track. A small SQLiteData registry (~10–20 entries),
  seeded by folder-drop / parent-folder discovery, is the workspace — not a
  library mirror. Album Artist is the owner identity; track/disc strip defaults
  on (per-album toggle); Compilation flag defaults off (per-album override);
  artwork keeps original embedded art and falls back to the collection cover
  only when a song has none.
- Identity drift is the main open risk: the merge key (`Album` / `Album Artist`)
  is read from file tags, but Apple Music may have mutated it on import, which
  silently spawns a duplicate album instead of merging. First-append
  certification checks the exact album exists and its track count went up. Open:
  how forgiving should the match be — exact string only, or trim/normalize
  whitespace and leading articles before comparing? And what should VF offer when
  the check finds no matching album (block, warn-and-proceed, or open a
  reconcile step to re-point the entry at the real album)?
- Open: when seeding an entry from a folder whose files disagree on `Album` or
  `Album Artist`, which value wins — most common, first, or prompt?

## Metadata Management

- What exactly belongs in Metadata Management versus Collection Management?
- Is Apple Music remediation part of Metadata Management, or should it become its
  own app area later?
- Which first metadata-repair workflow would make this area concrete?

## MusicBrainz and Artwork

- For song-level lookup, what release types should be preferred by default?
- How strongly should various-artist compilations be penalized?
- Are there cases where VA compilation artwork is desired?
- Should cover art be fetched only from MusicBrainz-linked sources, or can the app
  use other sources later?
- Should lookup decisions be cached permanently?

## Apple Music Remediation

- Resolved direction: the read/verification surface is decided early, not later.
  Default to AppleScript/ScriptingBridge as the primary read surface with
  `Library.xml` as a fallback; see Verification Surface in
  [Technical Architecture](technical-architecture.md).
- Should the app ever automate deletion from Music.app, or only prepare manual
  reimport packages?
- What fields does Music.app most often fail to refresh?
- What is the safest manual reimport checklist?

## File Safety

- Should every source file get SHA-256 checksummed before a run?
- Should checksums be required only for destructive or source-mutating workflows?
- Should the app maintain an archive folder for replaced files?
- For failed or unapproved live-show runs, how long should generated `Working/`
  folders be kept before cleanup?

## iPad Companion

- Which screens would be useful away from the Mac?
- Should work queues and metadata policies sync through CloudKit eventually?

## Shared Components

- Extraction trigger: when Vinyl Fever starts consuming model access (Phase 5),
  lift Galavant's `GalavantAI` into a neutrally-named shared package both apps
  depend on, per `jon-platform/docs/adr/0001-extract-model-layer.md`. Confirm the
  path: depend on the extracted shared package (intended), copy/vendor for now, or
  defer AI until after extraction. Recommendation: rename-and-move at Phase 5; do
  not pre-extract and do not copy.
- Resolved (2026-07-03 review): setlist normalization targets the frontier /
  BYO-key tier. The prose-inference, dirty-OCR, and multi-line-jam cases in the
  raw corpus lean on reasoning quality the on-device/Apple-cloud tier cannot yet
  be assumed to reach, so the feature is BYO-required. See *Automation
  Implications* in [Setlist Formatting Rules](setlist-formatting-rules.md). A
  tiered on-device-then-escalate approach remains a possible later optimization.
- Does AcoustID fingerprint lookup ever enter scope? If so, it is the only
  non-model credential; decide whether it reuses the shared Keychain key store.
