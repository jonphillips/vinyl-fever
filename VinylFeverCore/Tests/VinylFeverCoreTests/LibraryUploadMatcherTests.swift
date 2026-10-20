import Testing
import VinylFeverCore

@Suite("Library upload matching")
struct LibraryUploadMatcherTests {
  private let request = TrackRequest(index: 1, artist: "The Records", title: "Night Drive", album: "Live at the Hall")

  @Test("an exact upload on the hinted album uses the album route")
  func albumRouteHit() async {
    let result = await LibraryUploadMatcher.match(
      request,
      searchAlbums: { _ in [LibraryAlbumCandidate(id: "a", title: "Live at the Hall")] },
      albumTracks: { _ in [song("upload", album: "Live at the Hall")] },
      searchSongs: { _, _ in Issue.record("song search should not run"); return [] })
    #expect(result == .matched(song("upload", album: "Live at the Hall").candidate))
  }

  @Test("the album route searches every same-name album")
  func duplicateAlbums() async {
    let result = await LibraryUploadMatcher.match(
      request,
      searchAlbums: { _ in [LibraryAlbumCandidate(id: "first", title: "Live at the Hall"), LibraryAlbumCandidate(id: "second", title: "Live at the Hall")] },
      albumTracks: { id in id == "first" ? [] : [song("upload", album: "Live at the Hall")] },
      searchSongs: { _, _ in [] })
    #expect(result == .matched(song("upload", album: "Live at the Hall").candidate))
  }

  @Test("an empty album search shortens its term")
  func shortenedAlbumTerm() async {
    let terms = StringRecorder()
    let result = await LibraryUploadMatcher.match(
      TrackRequest(index: 1, artist: "The Records", title: "Night Drive", album: "Live at the Hall"),
      searchAlbums: { term in await terms.append(term); return term == "Live at" ? [LibraryAlbumCandidate(id: "a", title: "Live at the Hall")] : [] },
      albumTracks: { _ in [song("upload", album: "Live at the Hall")] },
      searchSongs: { _, _ in [] })
    #expect(await terms.values == ["Live at the Hall", "Live at the", "Live at"])
    #expect(result == .matched(song("upload", album: "Live at the Hall").candidate))
  }

  @Test("song search is the fallback and skips catalog-linked resources")
  func songFallback() async {
    let result = await LibraryUploadMatcher.match(
      request,
      searchAlbums: { _ in [] }, albumTracks: { _ in [] },
      searchSongs: { _, _ in [song("catalog", album: "Live at the Hall", catalog: true), song("upload", album: "Live at the Hall")] })
    #expect(result == .matched(song("upload", album: "Live at the Hall").candidate))
  }

  @Test("the library song search stops at 100 results with a not-found reason")
  func resultCap() async {
    let offsets = IntRecorder()
    let values = (0..<100).map { song("other-\($0)", title: "Other", album: "Live at the Hall") }
    let result = await LibraryUploadMatcher.match(
      request, searchAlbums: { _ in [] }, albumTracks: { _ in [] },
      searchSongs: { _, offset in await offsets.append(offset); return offset == 0 ? values : [] })
    #expect(await offsets.values == [0])
    #expect(result == .notFound(reason: "Apple Music's library search couldn't reach this upload."))
  }

  @Test("only a matching uploaded row and album hint selects library routing")
  func routingRule() {
    let upload = LibraryTrack(persistentID: "u", name: "Night Drive", artist: "The Records", album: "Live at the Hall", availability: .uploaded)
    let catalog = LibraryTrack(persistentID: "c", name: "Night Drive", artist: "The Records", album: "Studio", availability: .matched)
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [upload, catalog])
    #expect(LibraryUploadMatcher.shouldUseLibraryRoute(request, snapshot: snapshot))
    #expect(!LibraryUploadMatcher.shouldUseLibraryRoute(TrackRequest(index: 2, artist: "The Records", title: "Night Drive", album: "Studio"), snapshot: snapshot))
    #expect(!LibraryUploadMatcher.shouldUseLibraryRoute(request, snapshot: nil))
  }

  @Test("catalog-route fallbacks offer the three most-played uploads")
  func uploadPickerCandidates() {
    let tracks = (1...4).map { index in
      LibraryTrack(persistentID: "u\(index)", name: "Night Drive", artist: "The Records", album: "Show \(index)", playCount: index, availability: .uploaded)
    }
    let candidates = LibraryUploadMatcher.uploadedCandidates(request, snapshot: LibrarySnapshot(generatedAt: .now, tracks: tracks))
    #expect(candidates.map(\.id) == ["u4", "u3", "u2"])
    #expect(candidates.allSatisfy { $0.source == .libraryUpload })
  }

  private func song(_ id: String, title: String = "Night Drive", album: String, catalog: Bool = false) -> LibrarySongCandidate {
    LibrarySongCandidate(id: id, title: title, artist: "The Records", album: album, hasCatalogID: catalog)
  }
}

private actor StringRecorder {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
}

private actor IntRecorder {
  private(set) var values: [Int] = []
  func append(_ value: Int) { values.append(value) }
}
