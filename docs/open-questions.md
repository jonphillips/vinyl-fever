# Open Questions

The architect's and Jon's scratch pad: candidates, parked work, and decisions for Jon's review.
**The executor never reads this file** (jon-platform ADR-0005). Work becomes dispatchable only when a
plan PR moves it into a milestone or effort and sets `docs/NEXT_UP.md`.

## Candidates & parked work

- **Siri AI tool intents — wait for the release, not the beta** (Jon and the architect,
  2026-11-16). Apple's Siri AI developer preview
  ([news](https://developer.apple.com/news/?id=gdk2umrf),
  [docs](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri))
  lets Siri call an App Intent marked `@AppIntent(.tool)` from natural speech. It's 27.3-beta only, and only for
  dev-signed and internal-TestFlight builds. Jon isn't running betas, so revisit when Siri AI ships to customers
  ("a few months" from 2026-11-03) and App Store submission opens (spring 2027). The cheap win then: mark
  `WhyThisSongIntent` and `MusicFeedbackIntent` as tools, and add a parameter description to `note`, so "tell
  Vinyl Fever this bridge is gorgeous" fills the note. About four lines. Leave `VinylFeverProbeIntent` out:
  it's a diagnostic. Re-read the docs first, because the API may change before release.
- **From M24 (architect, 2026-11-08):**
  - **Dismiss a staged playlist from the phone,** writing M24 S4's `dismissed` line. Today the
    14-day rule archives one he never creates.
  - **Tap the player strip to jump to the song** in the open playlist.
- **Phone shelf: re-read only what changed** (architect, 2026-11-08). After
  [phone-remembers-shelf](efforts/archive/phone-remembers-shelf.md), every launch still re-reads every
  ledger file and every Keepers playlist's tracks behind the cached shelf. Skip ledger files whose
  modification date hasn't changed, and Keepers playlists whose `lastModifiedDate` hasn't. Build it
  only if the background refresh still feels slow.
- **Now-playing album brief and queueing** — [parked brief](efforts/archive/now-playing-album-brief.md)
  (Jon and the architect, 2026-10-27). Ask the chat about the song that's playing and get a brief
  against Jon's own evidence, then queue tracks without a playlist. Its first intent shipped as
  M20; the brief tool and queueing are designed but not planned.
- **Collection Policy, the rest of it** — [parked design](archive/metadata-policy-model.md).
  `CollectionPolicy` is deliberately thin (M7): membership rules, artwork policy, and MusicBrainz
  lookup policy are designed there and not built.

- **M4 Reconcile fast-follow** — re-point the registry entry when identity drift is found, and sharpen
  same-title/different-owner duplicate detection
  ([ledger](milestones/archive/M4-compilation-album-append.md)). **Evidence-gated by design:** build it only when
  a real append spawns a `Great Covers 2` drift. None observed in daily use yet.
- **Pending Jon decision — M4 identity-drift (#2/#3).** Decide identity-match forgiveness and no-match
  behavior *when* a real append mangles a title. Parked until the evidence appears.
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

  The analytical strategy is now *Taste Intelligence*, planned as
  [M17](milestones/archive/M17-taste-intelligence.md) (2026-10-23).
- **The executor posted as Jon** (from the #126 review, 2026-10-24). One of Codex's PR comments
  was posted as `jonphillips`, not `jon-codex-bot`, so at least one of Codex's shells reaches
  Jon's `gh` keyring login. Later comments came from the bot. **For Jon:** check which shell or
  tool Codex used for that comment, and make sure only the bot's token is available to it. The
  split between the two identities is what makes native reviews work.
- **Artist Aliases sheet follow-ups** (from the #101 review and M15 S1's gate, 2026-10-20/21).
  - **Adding an alias by hand.** The finder can't propose an alias without evidence in the
    library. `john cougar` (4 remixes) shares no titles with `john mellencamp`, and
    `on a friday` (Radiohead's early name) shares 3 titles, one short of the threshold. Both are
    real aliases that Jon would have to type himself.
    - **Candidate:** an **Add alias…** button in the sheet. Jon types two spellings, and the
      decision goes through the same store rules as an accepted candidate: base keys, no
      chains, re-pointing.
    - **Jon to decide, now that the gate has passed.** If these two are the only misses, a
      one-off decision row is simpler than new UI.
  - **The direction choice is invisible and doesn't need to exist.** Jon didn't know the two
    **Same artist** buttons pick the canonical spelling, so 49 of his 73 accepted aliases point
    at the smaller key (`bruce springsteen` → `bruce springsteen band`). It doesn't change
    behavior: matching and grouping compare keys, and display names come from track tags. The
    Accepted list is the only place it shows, and it reads backwards. The swap was the
    architect's brief, and it gives Jon a choice that has no effect.
    - **Candidate:** one **Same artist** button, with the key that has more tracks always
      canonical. A one-time migration re-points Jon's 49 rows the same way, and the Accepted
      list shows display spellings instead of keys. Small, cosmetic, and it can ride along with
      Add alias if that's built.
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
  older than 50 min makes Vinyl Fever launch Music.app at its own launch, and since the
  50-minute threshold (2026-11-27) the hourly check relaunches a quit Music.app every hour while
  Vinyl Fever is open. That's harmless on the mini, where Music stays open, and noticeable on
  the laptop. Pending Jon.
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

- **`setup-mac`'s Time Machine check stops at the first destination without snapshots** (from
  the #135 review, 2026-10-26). The loop reads `Destinations.$i.SnapshotDates` for i = 0, 1, …,
  and stops at the first one that's missing. So if Jon adds a second destination and the first
  has no snapshots, the newer one is never read. It errs toward a warning ("no completed
  snapshot found"), never toward a silent pass. **Recommendation:** read the destination count
  first (`plutil -extract Destinations raw`), and skip destinations that have no dates. A
  fixture with an empty first destination and a recent second one gives no warning. Do it with
  the next `setup-mac` change; it isn't worth its own dispatch.
- **An idle listening agent can't be stopped on its own** (from the #105 review). While another
  Mac holds the lease, Settings shows this Mac's toggle as off, so the only way to unregister its
  idle agent is to take the lease and then turn polling off. The idle agent's hourly run skips
  and writes nothing. **Recommendation:** a "Stop this Mac's idle agent" button, if an idle agent
  ever matters in practice.

## V1 Scope

- Which existing script is most important after `music_pipeline.sh`?
- Which remaining steps truly need shell/Python rather than Swift?

## Live Show Prep

- Are the default live-show album title rules in `setlist-formatting-rules.md`
  complete?
- Are the source labels in `setlist-formatting-rules.md` complete, or should
  additional defaults such as `WEB`, `MTX`, or others be added?
- What Apple Music fields/data should identify an imported album as a live show
  for the chronological artist view?
- What should the local-model live-show label audit flag as "probably mislabeled"?

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

- The iPhone and iPad app is M20 (voice) and M21 (the playlists view). Its packages would serve
  a larger iPad surface later.
- Which other screens would be useful away from the Mac?
- Should work queues and metadata policies sync through CloudKit eventually?

## Shared Components

- Does AcoustID fingerprint lookup ever enter scope? If so, it is the only
  non-model credential; decide whether it reuses the shared Keychain key store.
