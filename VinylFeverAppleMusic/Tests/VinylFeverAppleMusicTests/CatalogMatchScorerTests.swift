import Testing
import VinylFeverAppleMusic

struct CatalogMatchScorerTests {
  @Test func exactSongMatchIsAutomatic() {
    let request = TrackRequest(index: 1, artist: "The Records", title: "Starry Eyes")
    let candidate = CatalogSongCandidate(id: "1", title: "Starry Eyes", artistName: "The Records")
    #expect(CatalogMatchScorer.score(request, candidates: [candidate]) == .matched(candidate, score: 0.9))
  }
}
