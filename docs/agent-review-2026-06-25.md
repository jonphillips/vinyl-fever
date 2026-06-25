# Vinyl Fever — Planning Review (2026-06-25)

> **Status (2026-06-25): folded into the planning docs.** Jon approved these
> recommendations; the actionable items are now reflected directly in
> `product-requirements.md`, `app-areas.md`, `metadata-policy-model.md`,
> `setlist-formatting-rules.md`, `technical-architecture.md`,
> `implementation-plan.md`, and `open-questions.md`. This file is retained as the
> rationale/changelog, not as a separate to-do list.

Reviewer: Claude (agent). Scope: all of `docs/vinyl-fever/`, plus
`apple_music_library_strategy.md`, `music_pipeline.sh`, the legacy
`MusicWorkbench_Codex_Handoff.md`, and `jon-platform/AGENTS.md`.

You asked for aggressive pushback. The docs are genuinely strong — safety-first,
honest about what's unsettled, and well aligned to the house stack. So this is
mostly about a handful of places where the plan will bite you, plus cleanup.

---

## TL;DR — read this part on the phone

**Top things I'd change before writing code:**

1. **Your `Working/` lifecycle has a real bug.** "Delete `Working/` after
   approval, then import" only works for FLAC→ALAC. For MP3/M4A (and FLAC with
   no conversion) the approved files *live inside* `Working/`. Deleting it
   deletes what you import. **#1 priority.**
2. **"Verify" is the keystone and it's deferred to Phase 7.** The whole
   preview→run→verify loop is worthless if you can't confirm Music.app reflected
   the change. The verify mechanism (Library.xml vs AppleScript vs MusicKit) is
   an architecture fork — decide it in Phase 1, not Phase 7.
3. **Don't commit to three top-level "areas."** Metadata Management is an
   admitted junk drawer that overlaps Collection Management. Organize around
   *objects* (Show, Collection Policy, Track, Run) + *operations*, and ship two
   areas, not three.
4. **The plan has no vertical slice.** Phases are horizontal layers; the primary
   value (live-show import) doesn't land until Phase 5. Cut one real show
   end-to-end first.
5. **Decide the boundary you're actually building:** a Swift-native music app, or
   a shell-script launcher console. The product docs say the former; the data
   model (script registry, generic `WorkflowDefinition`, `ScriptClient` in Phase
   4) describes the latter.
6. **GUI apps don't inherit your shell `PATH`.** `which ffmpeg` will fail from a
   Finder-launched app. Tool discovery + sandbox stance are unaddressed early
   decisions.

Severity legend: 🔴 fix before building · 🟡 decide before the relevant phase ·
🟢 cleanup / nice-to-have.

---

## 1. 🔴 The `Working/` delete-before-import step is wrong for most formats

`app-areas.md` (lifecycle steps 8→9) and `implementation-plan.md` (Phase 5) both
say: approve → **delete `Working/`** → import into Apple Music.

But I read `music_pipeline.sh`. Here's what it actually produces:

- **FLAC + ALAC conversion:** final import target is `./ALAC/` (outside
  `Working/`). Deleting `Working/` is safe. ✅
- **FLAC, no conversion:** tagged/renamed files stay in `Working/`. ❌
- **MP3:** tagged/renamed files stay in `Working/`. ❌
- **M4A:** tagged/renamed files stay in `Working/`. ❌

So for three of four paths, "delete `Working/` then import" **deletes the files
you were about to import.** The lifecycle silently assumes the ALAC path.

**Fix the model, not just the wording.** Introduce an explicit *approved output*
location that is always distinct from the scratch workspace:

- `Working/` = mutable scratch (copies, intermediates) — disposable.
- `Output/` (or the existing `ALAC/`) = the approved, import-ready artifact.

Then the rule becomes: **promote approved files to `Output/` → import from
`Output/` → verify → only then clean up `Working/` (and optionally `Output/`).**
Never delete the thing you're importing before the import + verify succeed.

---

## 2. 🔴 "Verify" is the linchpin and the file→library mapping is hand-waved

Everything in these docs — "previewable, logged, biased toward preserving
originals," the four-step Scan/Preview/Run/Verify discipline — pays off at
**Verify**. Yet:

- `open-questions.md` still asks "What counts as verified after import?"
- `technical-architecture.md` lists Music.app integration as levels 3–5, "later."
- `app-areas.md` says map Music.app items to file paths "**when possible**."

That "when possible" is the single hardest technical problem in the app, and
it's a footnote. Three candidate mechanisms, each with a real catch:

| Mechanism | Reads library? | File paths? | Catch |
|---|---|---|---|
| Exported `Library.xml` | Yes | Yes (`Location`) | Manual export, increasingly deprecated, stale the moment you import |
| AppleScript / ScriptingBridge | Yes (+write) | Sometimes | Brittle string matching; no stable identity; slow on large libraries |
| MusicKit (`MusicLibrary`) | Yes | Often **not** exposed | Entitlement; library schema ≠ file paths |

**Recommendation:** decide the verify mechanism in **Phase 1**, because it
defines `MusicLibraryScanClient`/`MusicAppClient` and gates the entire loop. My
bet for a household Mac app: **AppleScript/ScriptingBridge as the primary read
surface** (it can actually see persistent IDs, dateAdded, album, track count,
and the file `location` for local files), with `Library.xml` as a fallback
importer. Don't design around MusicKit if you need file paths.

**Give "verified" a concrete v1 definition now** so it's testable. Proposed
starting point — a show is *Verified* when:

1. An album matching the approved title exists in the library scan, **and**
2. its track count equals the setlist track count, **and**
3. (optional spot check) total duration or per-track durations are within
   tolerance of the source files.

Leave the local-model "is this mislabeled?" audit as a separate, later nicety —
don't entangle it with the hard yes/no verification.

---

## 3. 🟡 Three "areas" is the wrong top-level shape — and the docs already know it

`product-requirements.md` and `app-areas.md` present **three areas** as settled
(Phase 0 even says "confirm the three areas"). But:

- Metadata Management is described twice as "hazier"/"a working hypothesis."
- `open-questions.md` asks "What exactly belongs in Metadata Management versus
  Collection Management?"
- Apple Music Remediation is filed under Metadata Management but is really its
  own verification-loop concern.

That's the classic junk-drawer smell: two crisp areas plus a catch-all for
"everything else about tags." Committing three nav tabs now bakes in the
confusion.

**Pushback:** model the app around **durable objects + operations**, not three
parallel "areas":

- **Objects (nouns):** `LiveShow`, `CollectionPolicy`, `Track/AudioFile`, `Run`.
- **Operations (verbs) applied to tracks:** tag repair, MusicBrainz lookup,
  artwork selection, sort-field cleanup, remediation.
- **Shared services:** scanner, preview, file-plan, run log, MusicBrainz, setlist
  normalizer, ModelClient.

For v1 nav, ship **two** front doors — **Live Shows** and **Collections** — and
expose "metadata operations" as actions on tracks/selections plus a **Remediation
/ Library Health** task list backed by the shared services. "Metadata
Management" becomes the shared infrastructure made visible, not a third silo. You
can always promote it to a top-level area later once it's actually defined;
you can't easily un-ship three tabs to your future self.

---

## 4. 🟡 The plan is all horizontal layers — add a vertical slice

`implementation-plan.md` builds skeleton → scanner → file-ops → **live show
(Phase 5)** → collections → remediation. The thing that justifies the entire app
— prep one live show and get it into Music — doesn't exist until Phase 5, after
you've invested in a generic scanner and workflow catalog.

For a private, single-user app, that's backwards. **Restructure so Phase 1.5 is a
deliberately narrow end-to-end slice:**

> Pick one real FLAC show folder → ingest its setlist (paste) → preview the
> file/title/tag plan → apply to `Working/` copies → convert to ALAC → verify the
> album shows in Music → done.

Allowed to be ugly. The point is to detonate your three riskiest assumptions
early — setlist normalization quality, file-plan correctness, and **verify** —
before you build scanner/catalog scaffolding around them. Everything in Phases
3–4 gets easier (and better-specified) once one real show has gone through.

---

## 5. 🟡 Pick a side: Swift-native app vs. script-launcher console

There's a genuine contradiction running through the docs.

**Product docs say (repeatedly):** rewrite `music_pipeline.sh` early, "do not
spend product time polishing a bridge to the interactive script," move planning/
parsing/metadata into Swift.

**The architecture/data model says:** persist `Script registrations`, a generic
`WorkflowDefinition` with ~18 fields including `Script path` / `Whether the
current script is interactive`, a `ScriptClient`, and a "workflow catalog UI"
(Phase 3) before live-show work (Phase 5).

Building a script registry + generic workflow catalog **is** building the bridge
you told yourself not to build. Resolve it:

- **Keep as subprocesses (genuinely the right tool):** the audio transforms —
  FLAC→ALAC, OPUS→AAC — i.e. ffmpeg/metaflac orchestration. A thin
  `ConversionClient` over those is fine and honest.
- **Don't build in v1:** a generic `WorkflowDefinition`/script-registry
  abstraction. You have a *handful* of workflows for *one* user. Model the 2–3
  real flows as concrete typed Swift values and functions. The 18-field generic
  definition is premature generality (YAGNI) for household scale — it's
  infrastructure for a plugin system you don't have.
- **Reimplement in Swift:** scanning, setlist normalization, file-plan
  generation, preview models, metadata *policy*. (Tag read/write — see §7.)

Net: trim `ScriptClient` from "run arbitrary registered scripts" down to "run the
specific audio-conversion tools," and delete the catalog/registry concept until a
second user or a real plugin need shows up.

---

## 6. 🟡 The toolchain reality the docs skip: PATH, sandbox, and Python

Three early decisions that aren't in any doc and will block the first run:

1. **GUI apps don't inherit your shell `PATH`.** A Finder-launched `.app` gets a
   minimal environment — `which ffmpeg`/`metaflac`/`python` will *fail* even
   though they work in Terminal. The script even hardcodes
   `#!/opt/homebrew/bin/bash`. You need explicit tool-path discovery (probe
   `/opt/homebrew/bin`, `/usr/local/bin`) and a Settings screen to override
   paths. Treat "locate external tools" as a first-class, tested concern.
2. **Sandbox stance.** Since this is household / never App Store, go
   **non-sandboxed** (Developer ID + hardened runtime). Spawning Homebrew
   ffmpeg/metaflac and reading arbitrary folders from a sandboxed app is a world
   of pain (you'd be fighting security-scoped bookmarks for every subprocess).
   Decide this before Phase 2 — it affects entitlements and the whole file model.
3. **Python is a liability surface.** The scripts depend on `mutagen` /
   `musicbrainzngs` in a local `.venv`. Shipping an app that shells into the
   user's venv is fragile. For tagging, prefer the **C CLIs the app can locate**:
   `metaflac` for FLAC Vorbis comments + embedded art, `ffmpeg`/AVFoundation for
   MP3/M4A. That shrinks the Python surface to the batch/dedup utilities you may
   not even port to v1 — which also sharpens the open question "which steps truly
   need Python."

---

## 7. 🟡 The setlist normalizer is LLM-first, not deterministic-first — say so, and route it through `ModelClient`

`setlist-formatting-rules.md` is excellent (and huge — ~640 lines). But read what
it actually asks for: infer source type from prose, attach footnotes to the right
tracks, "distinguish useful musical detail from trading noise," fix spelling
"when the intended song is clear," decide cover-note usefulness. That's **80%
semantic judgment** — LLM work, not deterministic parsing.

The docs say "deterministic first, LLM when needed." In practice it's the
reverse: the LLM does the interpretation, and the **deterministic layer's real
job is validation and guardrails on the LLM output** — tag presence, the
one-blank-line-after-tags shape, track count, "no `|` inside a Grouping token,"
source label ∈ your controlled vocabulary, no invented sources. Frame it that way
so you build the validator, not a doomed deterministic parser for prose.

**Also — this is your first real AI feature, and the docs never connect it to the
house AI boundary.** `jon-platform/AGENTS.md` is explicit: AI goes through one
provider-agnostic `ModelClient` (tiered on-device → Apple cloud → BYO-key), *not*
Apple's `LanguageModel` directly. The Vinyl Fever docs only ever say "LLM
helper." Before Phase 5, state that setlist normalization (and the live-show
mislabel audit) call `ModelClient`, and read `docs/ios/ai-model-access.md`. Right
now an implementer would wire a one-off model call and violate the house stance.

---

## 8. 🟡 Persistence: the DB is operational/derived state, not the source of truth

> **Resolved (2026-06-25):** recorded as a settled decision in the Source Of
> Truth And Storage Ownership section of `metadata-policy-model.md`, with a
> pointer from the Persistence section of `technical-architecture.md`.

`technical-architecture.md` lists `Folder scans` among SQLiteData "app state"
without addressing staleness. But the *truth* lives in (a) the files on disk and
(b) Music.app — both of which change behind the app's back. Make this explicit in
the doc:

> SQLiteData holds **policies, run logs, queues, decisions, and cached/derived
> read models**. It is **not** the source of truth for file contents or library
> contents. Scans are snapshots with a timestamp; every view must tolerate "this
> is stale, rescan."

And on **CloudKit/sharing** (AGENTS.md says obey the sharing laws *before*
designing a synced schema): if sync ever happens, run logs, scans, and absolute
file paths are **machine-local and meaningless on another device.** Only
`CollectionPolicy` and durable `LiveShow` metadata are conceivably syncable.
Design the schema *now* so syncable policy/show truth is cleanly separated from
machine-local operational data — even if you never turn on CloudKit, that split
keeps the option open and prevents entangling paths into synced tables later.

---

## 9. 🟢 Grouping has two delimiters with different meanings — make it explicit

You use `::` for intra-token hierarchy (`Yacht Rock :: Remixes`) and ` | ` for
inter-token separation (`Yacht Rock :: Remixes | Great Covers`). That's fine but
needs to be stated as a two-level grammar, and watch the **substring-collision**
risk in Smart Playlists: a rule "Grouping contains `Covers`" matches both
`Power Pop :: Covers` and `Yacht Rock :: Covers`. Sometimes desired, sometimes
not. Recommend: when generating a Smart Playlist for a specific token, match the
**full token string** (`Power Pop :: Covers`), not a bare leaf, to avoid
accidental unions. Worth a sentence in `metadata-policy-model.md`.

---

## 10. 🟢 Doc & repo hygiene

- **Stale Script Inventory.** `technical-architecture.md` lists 11 scripts, but
  the folder also has `compare_compilations_to_canonical.py` and
  `strip_prefix_underscore.py` (not listed). If the inventory is meant to be
  authoritative, it's already drifting — or stop trying to enumerate and instead
  point at the folder.
- **The legacy handoff actively contradicts the new docs.**
  `MusicWorkbench_Codex_Handoff.md` recommends "SwiftData / SQLite" (§14, Option
  B) and JSON project files — both of which the new docs and AGENTS.md forbid.
  It's still linked as "related source material." Add a banner at its top:
  *"Superseded by `docs/vinyl-fever/`. Historical evidence only. Where it
  conflicts (SwiftData, JSON manifests), the vinyl-fever docs win."*
- **Not a git repo yet.** House style values drift control; `git init` early and
  add a `.gitignore`. Right now the folder has `.DS_Store`, an **empty file
  literally named `01`**, `.venv/`, `__pycache__/`, and a pile of `*.csv` reports
  (`dupe_report.csv`, `compare_dirs_report.csv`, `hiatt_*.csv`) sitting next to
  product docs. When the app repo is created, keep the legacy scripts/reports in
  a clearly separated `legacy/` (or their own repo) so they don't pollute the
  Swift project.
- **Don't over-split the SPM package on day one.** The package boundary is house
  style and right *eventually*, but for a single macOS target with no second
  consumer, multiple targets add build friction for no payoff. One core package +
  the app target, with macOS-only bits (Process, bookmarks, ScriptingBridge)
  behind protocols *in* the package, makes the future iPad split mechanical
  without paying for it now.

---

## 11. 🟢 Smaller calls and answers to a few open questions

- **Checksums (open question):** don't SHA-256 every file on every run — overkill
  at household scale. Originals are immutable and copied into `Working/` anyway.
  Checksum **only** when a workflow opts into *source mutation*, and for
  post-convert verification spot checks. That's the cheap, honest policy.
- **Source-label vocabulary (WEB/MTX/etc.):** make it a **user-editable list**,
  and constrain the LLM normalizer to *that* list rather than letting it invent
  labels. (`(unknown)` when unsure — already your instinct.)
- **`prep_release.sh` dry-run caveat is a great catch** — keep that skepticism as
  a rule: a workflow's `dry-run scope` must be *verified by reading the script*,
  never assumed. Good that the doc already says this.
- **The name.** "Vinyl Fever" is fun, but nothing in scope touches vinyl —
  it's digital live-show files, FLAC/ALAC, and Apple Music tags. Purely cosmetic;
  ignore if it's a deliberate vibe. Just flagging that a future-you might expect
  needle-drop/ripping features the name implies.

---

## What I'd do next

1. Patch the `Working/`→`Output/` lifecycle (§1) — it's a correctness bug.
2. Spike the **verify** surface (§2): a tiny throwaway that reads your Music
   library via ScriptingBridge and finds an album by title + counts tracks.
   This de-risks more than any amount of further doc writing.
3. Resolve §3 (two areas) and §5 (no generic script registry) in the docs, then
   re-cut `implementation-plan.md` around the §4 vertical slice.
4. Add the `ModelClient` routing note (§7) and the persistence/sync split (§8).

Happy to draft any of these doc edits, or write the verify spike, on request.
