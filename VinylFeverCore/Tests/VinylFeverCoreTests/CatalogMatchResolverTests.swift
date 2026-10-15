import Dependencies
import Foundation
import Testing
import VinylFeverCore

@Suite("Catalog match resolver")
struct CatalogMatchResolverTests {
  @Test("search concurrency is capped and request order is preserved")
  func concurrencyAndOrder() async {
    let requests = playlist((1...9).map { TrackRequest(index: $0, artist: "Artist", title: "Song \($0)") })
    let tracker = SearchTracker()
    let rows = await CatalogMatchResolver.resolve(requests, maximumConcurrentSearches: 3) { term in
      await tracker.started()
      try? await Task.sleep(for: .milliseconds(10))
      await tracker.finished()
      let title = term.replacingOccurrences(of: "Artist ", with: "")
      return [song(id: title, title: title)]
    }
    #expect(await tracker.maximum == 3)
    #expect(rows.map(\.request.index) == Array(1...9))
    #expect(rows.allSatisfy { if case .matched = $0.status { true } else { false } })
  }

  @Test("duplicate catalog IDs keep their first row and mark later occurrences")
  func duplicatesAreMarked() async {
    let same = song(id: "same", title: "Shared Song")
    let rows = await CatalogMatchResolver.resolve(playlist([
      TrackRequest(index: 4, artist: "Artist", title: "Shared Song"),
      TrackRequest(index: 9, artist: "Artist", title: "Shared Song"),
    ])) { _ in [same] }
    #expect(rows.count == 2)
    #expect(rows[0].status == .matched(same, score: 0.9))
    #expect(rows[1].status == .duplicate(same, ofTrackIndex: 4))
  }

  @Test("a row search failure becomes a not-found row and leaves the batch intact")
  func searchErrorIsContained() async {
    struct SearchFailure: LocalizedError {
      var errorDescription: String? { "Temporary catalog outage" }
    }
    let rows = await CatalogMatchResolver.resolve(playlist([
      TrackRequest(index: 1, artist: "Artist", title: "Bad"),
      TrackRequest(index: 2, artist: "Artist", title: "Good"),
    ])) { term in
      if term.hasSuffix("Bad") { throw SearchFailure() }
      return [song(id: "good", title: "Good")]
    }
    #expect(rows.count == 2)
    #expect(rows[0].status == .notFound(error: "Temporary catalog outage"))
    #expect(rows[1].status == .matched(song(id: "good", title: "Good"), score: 0.9))
  }

  @Test("the default search concurrency is two")
  func defaultConcurrencyIsTwo() async {
    let requests = playlist((1...6).map { TrackRequest(index: $0, artist: "Artist", title: "Song \($0)") })
    let tracker = SearchTracker()
    _ = await CatalogMatchResolver.resolve(requests) { _ in
      await tracker.started()
      try? await Task.sleep(for: .milliseconds(10))
      await tracker.finished()
      return []
    }
    #expect(await tracker.maximum == 2)
  }

  @Test("a rate-limited search is retried and then matches")
  func busySearchIsRetried() async {
    let attempts = AttemptCounter()
    let rows = await CatalogMatchResolver.resolve(
      playlist([TrackRequest(index: 1, artist: "Artist", title: "Good")]),
      clock: ImmediateClock()
    ) { _ in
      if await attempts.next() < 3 { throw AppleMusicCatalogBusyError() }
      return [song(id: "good", title: "Good")]
    }
    #expect(await attempts.count == 3)
    #expect(rows[0].status == .matched(song(id: "good", title: "Good"), score: 0.9))
  }

  @Test("a search that stays rate-limited gives up after the attempt limit with a readable error")
  func busySearchGivesUp() async {
    let attempts = AttemptCounter()
    let rows = await CatalogMatchResolver.resolve(
      playlist([TrackRequest(index: 1, artist: "Artist", title: "Busy")]),
      clock: ImmediateClock()
    ) { _ in
      _ = await attempts.next()
      throw AppleMusicCatalogBusyError()
    }
    #expect(await attempts.count == CatalogMatchResolver.maximumSearchAttempts)
    #expect(rows[0].status == .notFound(error: AppleMusicCatalogBusyError().localizedDescription))
  }

  @Test("retries wait a doubling delay plus jitter")
  func retryDelayDoubles() {
    #expect(CatalogMatchResolver.retryDelay(afterAttempt: 1, jitter: .zero) == .seconds(1))
    #expect(CatalogMatchResolver.retryDelay(afterAttempt: 2, jitter: .zero) == .seconds(2))
    #expect(CatalogMatchResolver.retryDelay(afterAttempt: 2, jitter: .milliseconds(120)) == .milliseconds(2120))
  }

  @Test("only rate-limit and server errors are retried")
  func retryableErrors() async {
    #expect(CatalogMatchResolver.isRetryable(AppleMusicCatalogBusyError()))
    #expect(CatalogMatchResolver.isRetryable(AppleMusicAPIError(statusCode: 429, detail: "")))
    #expect(CatalogMatchResolver.isRetryable(AppleMusicAPIError(statusCode: 503, detail: "")))
    #expect(!CatalogMatchResolver.isRetryable(AppleMusicAPIError(statusCode: 401, detail: "")))
    #expect(!CatalogMatchResolver.isRetryable(CancellationError()))

    let attempts = AttemptCounter()
    _ = try? await CatalogMatchResolver.search("term", clock: ImmediateClock()) { _ in
      _ = await attempts.next()
      throw AppleMusicAPIError(statusCode: 401, detail: "Unauthorized")
    }
    #expect(await attempts.count == 1)
  }

  private func playlist(_ tracks: [TrackRequest]) -> PlaylistRequest {
    PlaylistRequest(name: "Test", tracks: tracks)
  }

  private func song(id: String, title: String) -> CatalogSongCandidate {
    CatalogSongCandidate(id: id, title: title, artistName: "Artist")
  }
}

private actor SearchTracker {
  private var active = 0
  private(set) var maximum = 0

  func started() {
    active += 1
    maximum = max(maximum, active)
  }

  func finished() { active -= 1 }
}

private actor AttemptCounter {
  private(set) var count = 0

  func next() -> Int {
    count += 1
    return count
  }
}
