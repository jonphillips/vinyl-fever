import Dependencies
import Foundation
import Testing
import VinylFeverCore

@testable import VinylFever

@MainActor
@Suite("Playlist builder model")
struct PlaylistBuilderModelTests {
  @Test("a valid paste resolves rows; malformed paste makes no catalog searches")
  func validAndMalformedPaste() async {
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(search: { term, _ in
        [Self.candidate(id: term, title: "Starry Eyes")]
      })
      $0.catalogMatchResolver.resolve = { request in
        request.tracks.map { ResolvedPlaylistRow(request: $0, status: .matched(Self.candidate(id: "song", title: $0.title), score: 0.9)) }
      }
    } operation: { PlaylistBuilderModel() }
    model.pastedText = validPaste
    await model.resolve()
    #expect(model.playlistName == "Test Mix")
    #expect(model.rows.count == 1)
    #expect(model.decodeError == nil)

    let searchCounter = SearchCallCounter()
    let malformed = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(search: { _, _ in
        await searchCounter.record()
        return []
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    malformed.pastedText = "not a playlist"
    await malformed.resolve()
    #expect(malformed.decodeError != nil)
    #expect(await searchCounter.count == 0)
  }

  @Test("candidate selection resolves an ambiguous row")
  func candidateSelection() {
    let first = Self.candidate(id: "one", title: "Song")
    let second = Self.candidate(id: "two", title: "Song")
    let track = TrackRequest(index: 1, artist: "The Records", title: "Song")
    let model = PlaylistBuilderModel()
    model.rows = [ResolvedPlaylistRow(request: track, status: .ambiguous([
      ScoredCandidate(candidate: first, score: 0.8), ScoredCandidate(candidate: second, score: 0.7),
    ]))]
    model.selectCandidate(second, for: 1)
    #expect(model.rows[0].status == .matched(second, score: 0.9))
  }

  @Test("create requires a match and sends the edited name and only matched IDs in order")
  func createUsesMatchedRows() async {
    let capture = PlaylistCreateCapture()
    let first = Self.candidate(id: "first", title: "First")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(create: { name, description, ids in
        await capture.record(name: name, description: description, ids: ids)
        return CreatedPlaylistRef(id: "playlist-1", name: name, trackCount: ids.count)
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let firstRow = TrackRequest(index: 1, artist: "Artist", title: "First")
    let secondRow = TrackRequest(index: 2, artist: "Artist", title: "Second")
    model.rows = [
      ResolvedPlaylistRow(request: firstRow, status: .matched(first, score: 0.9)),
      ResolvedPlaylistRow(request: secondRow, status: .notFound(error: nil)),
    ]
    #expect(model.canCreate)
    model.playlistName = "Edited name"
    model.playlistDescription = "  "
    await model.createPlaylist()
    let received = await capture.value
    #expect(received?.0 == "Edited name")
    #expect(received?.1 == nil)
    #expect(received?.2 == ["first"])
    #expect(model.createdTrackIndexes == [1])
    #expect(model.visibleRows.map(\.request.index) == [2])
    #expect(model.matchedCount == 0)
    #expect(model.unresolvedCount == 1)
  }

  @Test("choosing an earlier match reconciles a later matched row and creates one ID")
  func earlierPickDeduplicatesCreateIDs() async {
    let capture = PlaylistCreateCapture()
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(create: { name, _, ids in
        await capture.record(name: name, description: nil, ids: ids)
        return CreatedPlaylistRef(id: "p", name: name, trackCount: ids.count)
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let first = TrackRequest(index: 1, artist: "The Records", title: "Song")
    let second = TrackRequest(index: 2, artist: "The Records", title: "Song")
    model.rows = [
      ResolvedPlaylistRow(request: first, status: .notFound(error: nil)),
      ResolvedPlaylistRow(request: second, status: .matched(song, score: 0.9)),
    ]

    model.selectCandidate(song, for: 1)

    #expect(model.rows[1].status == .duplicate(song, ofTrackIndex: 1))
    await model.createPlaylist()
    #expect(await capture.value?.2 == ["X"])
  }

  @Test("removing a duplicate's original promotes the duplicate back to matched")
  func removingOriginalPromotesDuplicate() {
    let song = Self.candidate(id: "X", title: "Song")
    let model = PlaylistBuilderModel()
    model.rows = [
      ResolvedPlaylistRow(request: TrackRequest(index: 1, artist: "The Records", title: "Song"), status: .matched(song, score: 0.9)),
      ResolvedPlaylistRow(request: TrackRequest(index: 2, artist: "The Records", title: "Song"), status: .duplicate(song, ofTrackIndex: 1)),
    ]

    model.remove(trackIndex: 1)

    #expect(model.rows[1].status == .matched(song, score: 0.9))
    #expect(model.visibleRows.map(\.request.index) == [2])
  }

  @Test("a picked match stays eligible when the previous matching row was removed")
  func pickMatchingRemovedRow() async {
    let capture = PlaylistCreateCapture()
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(create: { name, _, ids in
        await capture.record(name: name, description: nil, ids: ids)
        return CreatedPlaylistRef(id: "p", name: name, trackCount: ids.count)
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.rows = [
      ResolvedPlaylistRow(request: TrackRequest(index: 1, artist: "The Records", title: "Song"), status: .matched(song, score: 0.9)),
      ResolvedPlaylistRow(request: TrackRequest(index: 3, artist: "The Records", title: "Song"), status: .notFound(error: nil)),
    ]

    model.remove(trackIndex: 1)
    model.selectCandidate(song, for: 3)
    await model.createPlaylist()

    #expect(model.rows[1].status == .matched(song, score: 0.9))
    #expect(await capture.value?.2 == ["X"])
  }

  @Test("a leftover pick matching a created song becomes a duplicate")
  func leftoverCannotDuplicateCreatedSong() async {
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient()
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.rows = [
      ResolvedPlaylistRow(request: TrackRequest(index: 1, artist: "The Records", title: "Song"), status: .matched(song, score: 0.9)),
      ResolvedPlaylistRow(request: TrackRequest(index: 2, artist: "The Records", title: "Song"), status: .notFound(error: nil)),
    ]
    await model.createPlaylist()

    model.selectCandidate(song, for: 2)

    #expect(model.rows[1].status == .duplicate(song, ofTrackIndex: 1))
    #expect(model.visibleRows.map(\.request.index) == [2])
    #expect(!model.canAddToCreatedPlaylist(trackIndex: 2))
  }

  @Test("a leftover before a created match cannot append that song again")
  func earlierLeftoverCannotDuplicateCreatedSong() async {
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient()
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.rows = [
      ResolvedPlaylistRow(
        request: TrackRequest(index: 1, artist: "The Records", title: "Song"),
        status: .ambiguous([ScoredCandidate(candidate: song, score: 0.9)])
      ),
      ResolvedPlaylistRow(
        request: TrackRequest(index: 2, artist: "The Records", title: "Song"),
        status: .matched(song, score: 0.9)
      ),
    ]
    await model.createPlaylist()

    model.selectCandidate(song, for: 1)

    #expect(model.rows[0].status == .duplicate(song, ofTrackIndex: 2))
    #expect(model.rows[1].status == .matched(song, score: 0.9))
    #expect(!model.canAddToCreatedPlaylist(trackIndex: 1))
  }

  @Test("only matched leftover rows can be added to a created playlist")
  func canAddOnlyMatchedLeftover() async {
    let song = Self.candidate(id: "X", title: "Song")
    let first = TrackRequest(index: 1, artist: "The Records", title: "Song")
    let second = TrackRequest(index: 2, artist: "The Records", title: "Other")
    let third = TrackRequest(index: 3, artist: "The Records", title: "Missing")
    let fourth = TrackRequest(index: 4, artist: "The Records", title: "Duplicate")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient()
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.rows = [
      ResolvedPlaylistRow(request: first, status: .matched(song, score: 0.9)),
      ResolvedPlaylistRow(request: second, status: .ambiguous([])),
      ResolvedPlaylistRow(request: third, status: .notFound(error: nil)),
      ResolvedPlaylistRow(request: fourth, status: .duplicate(song, ofTrackIndex: 1)),
    ]
    await model.createPlaylist()
    #expect(!model.canAddToCreatedPlaylist(trackIndex: 2))
    #expect(!model.canAddToCreatedPlaylist(trackIndex: 3))
    #expect(!model.canAddToCreatedPlaylist(trackIndex: 4))

    model.selectCandidate(Self.candidate(id: "Y", title: "Other"), for: 2)

    #expect(model.canAddToCreatedPlaylist(trackIndex: 2))
  }

  @Test("two concurrent add requests append a row only once")
  func duplicateAddRequestsAreSingleFlight() async {
    let barrier = PlaylistAppendBarrier()
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(append: { _, _ in await barrier.append() })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.createdPlaylist = CreatedPlaylistRef(id: "p", name: "Mix", trackCount: 0)
    model.rows = [ResolvedPlaylistRow(
      request: TrackRequest(index: 1, artist: "The Records", title: "Song"),
      status: .matched(song, score: 0.9)
    )]

    async let firstAdd: Void = model.addToCreatedPlaylist(trackIndex: 1)
    await barrier.waitUntilStarted()
    await model.addToCreatedPlaylist(trackIndex: 1)
    await barrier.release()
    await firstAdd

    #expect(await barrier.callCount == 1)
    #expect(model.createdPlaylist?.trackCount == 1)
  }

  @Test("reopening a match removes it from Create until a new search resolves it")
  func reopensAndResolvesMatch() async {
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(search: { _, _ in [song] })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    model.rows = [ResolvedPlaylistRow(
      request: TrackRequest(index: 1, artist: "The Records", title: "Song"),
      status: .matched(song, score: 0.9)
    )]
    model.searchTerms[1] = "The Records Song"

    model.reopen(trackIndex: 1)
    #expect(model.matchedCount == 0)
    #expect(!model.canCreate)
    await model.reSearch(trackIndex: 1)

    #expect(model.rows[0].status == .matched(song, score: 0.9))
    #expect(model.canCreate)
  }

  @Test("a row fixed after creation appends to the new playlist and leaves the table")
  func addsPreviouslyUnresolvedRow() async {
    let appendCapture = PlaylistAppendCapture()
    let client = authorizedClient(append: { id, ids in await appendCapture.record(id: id, ids: ids) })
    let model = withDependencies {
      $0.appleMusicCatalogClient = client
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let track = TrackRequest(index: 8, artist: "Artist", title: "Recovered")
    model.rows = [ResolvedPlaylistRow(request: track, status: .matched(Self.candidate(id: "recovered", title: "Recovered"), score: 0.9))]
    model.createdPlaylist = CreatedPlaylistRef(id: "library-id", name: "Mix", trackCount: 1)
    await model.addToCreatedPlaylist(trackIndex: 8)
    let appended = await appendCapture.value
    #expect(appended?.0 == "library-id")
    #expect(appended?.1 == ["recovered"])
    #expect(model.visibleRows.isEmpty)
    #expect(model.createdPlaylist?.trackCount == 2)
  }

  @Test("authorization, subscription, and Sync Library gates block resolve")
  func gatesBlockResolution() async {
    for (client, expected) in [
      (authorizedClient(authorization: .denied), PlaylistGate.notAuthorized),
      (authorizedClient(subscription: .init(canPlayCatalogContent: false, hasCloudLibraryEnabled: true)), .noSubscription),
      (authorizedClient(subscription: .init(canPlayCatalogContent: true, hasCloudLibraryEnabled: false)), .cloudLibraryOff),
    ] {
      let model = withDependencies {
        $0.appleMusicCatalogClient = client
        $0.catalogMatchResolver.resolve = { _ in [] }
      } operation: { PlaylistBuilderModel() }
      model.pastedText = validPaste
      await model.resolve()
      #expect(model.gate == expected)
      #expect(model.rows.isEmpty)
    }
  }

  @Test("a re-search that is rate-limited retries and then matches")
  func reSearchRetriesBusySearch() async {
    let attempts = SearchCallCounter()
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.continuousClock = ImmediateClock()
      $0.appleMusicCatalogClient = authorizedClient(search: { _, _ in
        await attempts.record()
        if await attempts.count < 3 { throw AppleMusicCatalogBusyError() }
        return [song]
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let track = TrackRequest(index: 1, artist: "The Records", title: "Song")
    model.rows = [ResolvedPlaylistRow(request: track, status: .notFound(error: "busy"))]
    model.searchTerms = [1: "The Records Song"]

    await model.reSearch(trackIndex: 1)

    #expect(await attempts.count == 3)
    #expect(model.rows[0].status == .matched(song, score: 0.9))
  }

  @Test("retrying failed searches re-runs only rows whose search errored")
  func retryFailedSearchesOnlyErroredRows() async {
    let searchedTerms = SearchTermLog()
    let song = Self.candidate(id: "X", title: "Song")
    let model = withDependencies {
      $0.continuousClock = ImmediateClock()
      $0.appleMusicCatalogClient = authorizedClient(search: { term, _ in
        await searchedTerms.record(term)
        return [song]
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let failed = TrackRequest(index: 1, artist: "The Records", title: "Song")
    let unmatched = TrackRequest(index: 2, artist: "Other", title: "Missing")
    let removed = TrackRequest(index: 3, artist: "Gone", title: "Removed")
    model.rows = [
      ResolvedPlaylistRow(request: failed, status: .notFound(error: "busy")),
      ResolvedPlaylistRow(request: unmatched, status: .notFound(error: nil)),
      ResolvedPlaylistRow(request: removed, status: .notFound(error: "busy")),
    ]
    model.searchTerms = [1: "The Records Song", 2: "Other Missing", 3: "Gone Removed"]
    model.remove(trackIndex: 3)
    #expect(model.failedSearchCount == 1)

    await model.retryFailedSearches()

    #expect(await searchedTerms.terms == ["The Records Song"])
    #expect(model.rows[0].status == .matched(song, score: 0.9))
    #expect(model.rows[1].status == .notFound(error: nil))
    #expect(model.failedSearchCount == 0)
    #expect(!model.isRetryingSearches)
  }

  private var validPaste: String {
    "VF-PLAYLIST: v1\n{\"name\":\"Test Mix\",\"tracks\":[{\"artist\":\"The Records\",\"title\":\"Starry Eyes\"}]}"
  }

  private func authorizedClient(
    authorization: MusicKitAuthorization = .authorized,
    subscription: AppleMusicSubscriptionStatus = .init(canPlayCatalogContent: true, hasCloudLibraryEnabled: true),
    search: @escaping @Sendable (String, Int) async throws -> [CatalogSongCandidate] = { _, _ in [] },
    create: @escaping @Sendable (String, String?, [String]) async throws -> CreatedPlaylistRef = { name, _, ids in
      CreatedPlaylistRef(id: "playlist", name: name, trackCount: ids.count)
    },
    append: @escaping @Sendable (String, [String]) async throws -> Void = { _, _ in }
  ) -> AppleMusicCatalogClient {
    AppleMusicCatalogClient(
      authorizationStatus: { authorization },
      requestAuthorization: { authorization },
      subscriptionStatus: { subscription },
      searchSongs: search,
      createLibraryPlaylist: create,
      appendToLibraryPlaylist: append
    )
  }

  nonisolated private static func candidate(id: String, title: String) -> CatalogSongCandidate {
    CatalogSongCandidate(id: id, title: title, artistName: "The Records")
  }
}

private actor SearchCallCounter {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor PlaylistCreateCapture {
  private(set) var value: (String, String?, [String])?
  func record(name: String, description: String?, ids: [String]) {
    value = (name, description, ids)
  }
}

private actor PlaylistAppendCapture {
  private(set) var value: (String, [String])?
  func record(id: String, ids: [String]) { value = (id, ids) }
}

private actor PlaylistAppendBarrier {
  private(set) var callCount = 0
  private var startedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func append() async {
    callCount += 1
    if callCount == 1 {
      startedContinuation?.resume()
      await withCheckedContinuation { releaseContinuation = $0 }
    }
  }

  func waitUntilStarted() async {
    guard callCount == 0 else { return }
    await withCheckedContinuation { startedContinuation = $0 }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor SearchTermLog {
  private(set) var terms: [String] = []
  func record(_ term: String) { terms.append(term) }
}
