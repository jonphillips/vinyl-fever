# Album Cover Upload (Registry)

Status: **Design / ready to implement** · Scope: Collections registry (`CompilationAlbum`)

## Why

Registry covers today are auto-derived from the **first source file's embedded
artwork** during seeding
([`CompilationAlbumSeeding.deriveCandidate`](../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationAlbumSeeding.swift)):

```swift
let artwork = metadata.lazy.compactMap(\.1.embeddedArtwork).first
```

That is fine for a normal album, but it is unreliable for the **playlist-hack
albums**: the intended cover lives on a ~2s silent placeholder track (the one
track carrying a track number), while every real song carries its own per-track
art. `.first` grabs whatever file happens to sort first — usually a song's art,
not the cover. The cover is a **curated choice**, so it should be an explicit
input rather than something inferred from track metadata.

We are **not** reading artwork back out of Music.app over ScriptingBridge for
this. That path is technically possible (a Music `track` exposes `artworks` with
`data`/`raw data`), but it inherits the same "which track is the cover?"
ambiguity plus Apple Events flakiness. Manual upload is the source of truth;
auto-derived art stays as the prefill default.

## What already exists (no new plumbing)

- **Model:** `CompilationAlbum.displayImage: Data?` and `fallbackArtwork: Data?`
  ([`CompilationAlbum.swift`](../VinylFeverCore/Sources/VinylFeverCore/Model/CompilationAlbum.swift)).
- **DB column:** `"displayImage" BLOB`, `"fallbackArtwork" BLOB`
  ([`Schema.swift`](../VinylFeverCore/Sources/VinylFeverCore/Database/Schema.swift)).
- **Render:** `ArtworkThumbnail(data:)` → `NSImage(data:)`
  ([`CollectionsView.swift`](../VinylFever/Features/Collections/CollectionsView.swift)).
- **Upsert:** `CompilationAlbumRegistry.upsert(_:in:)` and the
  `database.write { … }` pattern in
  [`AppModel.swift`](../VinylFever/Features/AppShell/AppModel.swift)
  (`persistSelectedCompilationSeedCandidates`).
- **Image sniffing:** `AppModel.imageFileExtension(for:)` already fingerprints
  PNG/JPEG/GIF magic bytes — reuse for validation.

So this is a **UI affordance + one write method**, no schema migration.

## Field semantics: which column?

Two `Data?` fields exist:

- **`displayImage`** — what the registry list shows. The upload target.
- **`fallbackArtwork`** — the image stamped onto tracks during append
  (see `buildCompilationAppendPlan` / `applyFallback` in `AppModel`).

**Resolved: uploading a cover sets _both_ fields.** For hack albums the curated
cover *is* the album art, so the uploaded image should both update the registry
tile and become the artwork applied to appended tracks. This keeps the simplest
mental model ("this is the album's art"). Revisit only if we later want a
separate "list-only" thumbnail decoupled from the art written to files.

## UI sketch

Add a "Set Cover…" affordance to the selected-album context in
[`CollectionsView`](../VinylFever/Features/Collections/CollectionsView.swift).
The view already tracks `selectedAlbumID` and fetches `albums` via `@FetchAll`.

Placement options (pick one):
1. Button in `CompilationAppendSection`'s header for the selected album.
2. Overlay button / hover affordance on `ArtworkThumbnail` in
   `CompilationAlbumRow`.
3. Context menu on the album row (`.contextMenu { Button("Set Cover…") }`).

Recommended: **(1)** for discoverability now, optionally add **(3)** later.

Picker (mirror the existing `openFolder` helper, but for image files):

```swift
private func chooseCoverImage() -> URL? {
  let panel = NSOpenPanel()
  panel.allowsMultipleSelection = false
  panel.canChooseDirectories = false
  panel.canChooseFiles = true
  panel.allowedContentTypes = [.png, .jpeg, .gif, .image] // import UniformTypeIdentifiers
  panel.prompt = "Set Cover"
  return panel.runModal() == .OK ? panel.url : nil
}
```

Wire-up in the view:

```swift
if let selectedAlbum {
  Button("Set Cover…") {
    guard let url = chooseCoverImage() else { return }
    Task { await model.setCompilationAlbumCover(album: selectedAlbum, imageURL: url) }
  }
}
```

Nice-to-have (later): drag-and-drop an image onto the thumbnail via
`.dropDestination(for: Data.self)` / `.onDrop`, and paste-from-clipboard.

## Model method sketch

Add to `AppModel` (matches the existing `database.write` + state pattern). The
repo's established write pattern is **read-modify-`upsert` of the whole record**
(`CompilationAlbum.upsert { album }.execute(db)`), not a targeted `.update {}` —
there is no `.update {}` call site in the codebase, so mirror `upsert`.
There is also **no `readData` on `fileOperationClient`** (it only exposes
`writeData`), so read the picked file directly with `Data(contentsOf:)`.

```swift
func setCompilationAlbumCover(album: CompilationAlbum, imageURL: URL) async {
  do {
    let data = try Data(contentsOf: imageURL)
    guard let normalized = Self.normalizedCoverData(data) else {
      runLogErrorMessage = "That file isn't a readable image."
      return
    }
    var updated = album                 // struct copy; id is the primary key
    updated.displayImage = normalized
    updated.fallbackArtwork = normalized // see field-semantics decision
    try database.write { db in
      try CompilationAlbum.upsert { updated }.execute(db)
    }
    runLogErrorMessage = nil
  } catch {
    runLogErrorMessage = error.localizedDescription
  }
}
```

Passing the whole `album` (the view already has it via `@FetchAll` +
`selectedAlbumID`) avoids a separate read. If you'd rather pass just the ID,
`database.read` the row first, mutate, then `upsert`.

`normalizedCoverData`: validate the file decodes as an image, then **re-encode to
JPEG and downscale** so the BLOB stays small (covers are stored inline in
SQLite). **Resolved encoding policy: re-encode to JPEG (~quality 0.9), cap the
longest edge at ~1000px.** Reject anything that doesn't decode.

```swift
private static func normalizedCoverData(_ data: Data) -> Data? {
  guard let image = NSImage(data: data) else { return nil }   // reject non-images
  let maxEdge: CGFloat = 1000
  let downscaled = image.downscaled(longestEdge: maxEdge)      // no-op if already smaller
  return downscaled.jpegData(quality: 0.9)                     // via NSBitmapImageRep
}
```

Implementation note: `NSImage` has no built-in `jpegData`/`downscaled`; go
through `NSBitmapImageRep` — draw into a rep sized to the capped dimensions, then
`representation(using: .jpeg, properties: [.compressionFactor: 0.9])`. Add these
as small private helpers (or inline). Downscale only when the source exceeds the
cap so already-small covers pass through untouched aside from the JPEG re-encode.

Confirm the exact StructuredQueries update syntax against a sibling call site
(`.where { … }.update { … }.execute(db)`); `CompilationAlbumRegistry.upsert`
uses `CompilationAlbum.upsert { … }`. Either a targeted `update` or a
read-modify-`upsert` works.

## Storage note

Covers live inline as BLOBs. Keep them modest (re-encode + downscale on import)
so the SQLite file and `@FetchAll` payloads stay small. If we later want full-res
originals, move to file storage + a path column — out of scope here.

## Implementation checklist

- [ ] Add `setCompilationAlbumCover(album:imageURL:)` to `AppModel` — sets **both**
      `displayImage` and `fallbackArtwork`, read-modify-`upsert`,
      `Data(contentsOf:)`.
- [ ] Add `normalizedCoverData` — reject non-images, **re-encode JPEG q0.9,
      downscale longest edge → ~1000px** via `NSBitmapImageRep`.
- [ ] Add image `NSOpenPanel` picker + "Set Cover…" button in `CollectionsView`
      (selected-album context).
- [ ] Manual verify: pick PNG/JPEG → tile updates; pick non-image → clean error.
- [ ] (Optional) drag-drop + paste affordances on `ArtworkThumbnail`.

## Explicitly out of scope

- Reading artwork back from Music.app over ScriptingBridge.
- Auto-detecting the placeholder ("silent track with a track number") to
  auto-grab its art. Could be a *best-effort prefill* later, but manual upload
  is the reliable primary and ships first.
- Schema migration (none needed — columns exist).
