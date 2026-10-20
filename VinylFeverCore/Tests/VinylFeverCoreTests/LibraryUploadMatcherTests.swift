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

  @Test("the album route never chooses a catalog-linked library song")
  func albumRouteSkipsCatalogLinkedSong() async {
    let result = await LibraryUploadMatcher.match(
      request,
      searchAlbums: { _ in [LibraryAlbumCandidate(id: "a", title: "Live at the Hall")] },
      albumTracks: { _ in [song("catalog", album: "Live at the Hall", catalog: true)] },
      searchSongs: { _, _ in [] })
    #expect(result == .notFound(reason: "Apple Music's library search couldn't reach this upload."))
  }

  @Test("without an album hint the matcher searches songs instead of albums")
  func noAlbumHintUsesSongSearch() async {
    let albumCalls = IntRecorder()
    let songCalls = IntRecorder()
    let noAlbumRequest = TrackRequest(index: 1, artist: "The Records", title: "Night Drive")
    _ = await LibraryUploadMatcher.match(
      noAlbumRequest,
      searchAlbums: { _ in await albumCalls.append(1); return [] },
      albumTracks: { _ in [] },
      searchSongs: { _, _ in await songCalls.append(1); return [] })
    #expect(await albumCalls.values.isEmpty)
    #expect(await songCalls.values == [1])
  }

  @Test("identical upload resources are deduplicated by ID")
  func duplicateUploadID() async {
    let upload = song("upload", album: "Live at the Hall").candidate
    let result = await LibraryUploadMatcher.match(
      request,
      searchAlbums: { _ in [LibraryAlbumCandidate(id: "a", title: "Live at the Hall")] },
      albumTracks: { _ in [song("upload", album: "Live at the Hall"), song("upload", album: "Live at the Hall")] },
      searchSongs: { _, _ in [] })
    #expect(result == .matched(upload))
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
    let result = await LibraryUploadMatcher.match(
      request, searchAlbums: { _ in [] }, albumTracks: { _ in [] },
      searchSongs: { _, offset in
        await offsets.append(offset)
        return (0..<AppleMusicCatalogClient.librarySearchPageSize).map {
          song("other-\(offset)-\($0)", title: "Other", album: "Live at the Hall")
        }
      })
    #expect(await offsets.values == [0, 25, 50, 75])
    #expect(result == .notFound(reason: "Apple Music's library search couldn't reach this upload."))
  }

  @Test("only a matching uploaded row and album hint selects library routing")
  func routingRule() {
    let upload = LibraryTrack(persistentID: "u", name: "Night Drive", artist: "The Records", album: "Live at the Hall", availability: .uploaded)
    let catalog = LibraryTrack(persistentID: "c", name: "Night Drive", artist: "The Records", album: "Studio", availability: .matched)
    let snapshot = LibrarySnapshot(generatedAt: .now, tracks: [upload, catalog])
    let index = LibraryIndex(snapshot: snapshot)
    #expect(index.shouldUseLibraryRoute(request))
    #expect(!index.shouldUseLibraryRoute(TrackRequest(index: 2, artist: "The Records", title: "Night Drive", album: "Studio")))
    #expect(!index.shouldUseLibraryRoute(TrackRequest(index: 3, artist: "The Records", title: "Night Drive")))
  }

  @Test("whole-word artist prefixes route uploads, but partial words do not")
  func artistPrefixRouting() {
    let live = LibraryTrack(
      persistentID: "u", name: "Thunder Road",
      artist: "Bruce Springsteen & The E Street Band (Live)",
      album: "6/22/03 - Disc 2 - Midsummer Second Night", availability: .uploaded)
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: .now, tracks: [live]))
    let request = TrackRequest(
      index: 1, artist: "Bruce Springsteen", title: "Thunder Road",
      album: "6/22/03 - Disc 2 - Midsummer Second Night")
    #expect(index.shouldUseLibraryRoute(request))
    #expect(LibraryUploadMatcher.artistsMatch("Bruce Springsteen", live.artist))
    #expect(!LibraryUploadMatcher.artistsMatch("Bruce SpringsteenX", live.artist))
  }

  @Test("catalog-route fallbacks offer the three most-played uploads")
  func uploadPickerCandidates() {
    let tracks = (1...4).map { index in
      LibraryTrack(persistentID: "u\(index)", name: "Night Drive", artist: "The Records", album: "Show \(index)", playCount: index, availability: .uploaded)
    }
    let candidates = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: .now, tracks: tracks))
      .uploadedCandidates(request)
    #expect(candidates.map(\.id) == ["u4", "u3", "u2"])
    #expect(candidates.allSatisfy { $0.source == .libraryUpload })
  }

  @Test("the prebuilt upload index routes 30 rows under one second for a library-sized snapshot")
  func uploadRoutingPerformance() {
    let tracks = (0..<87_100).map { index in
      let target = index < 30
      return LibraryTrack(
        persistentID: "id-\(index)",
        name: target ? "Target Track \(index)" : "Track \(index % 18_000)",
        artist: target ? "Artist \(index) and the band" : "Artist \(index % 9_000)",
        album: target ? "Show \(index)" : "Album \(index % 12_000)",
        playCount: index % 80,
        availability: target || index.isMultiple(of: 6) ? .uploaded : .matched)
    }
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: .now, tracks: tracks))
    let requests = (0..<30).map {
      TrackRequest(index: $0 + 1, artist: "Artist \($0)", title: "Target Track \($0)", album: "Show \($0)")
    }
    let clock = ContinuousClock()
    let start = clock.now
    for request in requests {
      #expect(index.shouldUseLibraryRoute(request))
      #expect(index.uploadedCandidates(request).count == 1)
    }
    #expect(clock.now - start < .seconds(1))
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
