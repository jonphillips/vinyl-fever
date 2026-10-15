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
    #expect(rows[1].status == .duplicate(ofTrackIndex: 4))
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
