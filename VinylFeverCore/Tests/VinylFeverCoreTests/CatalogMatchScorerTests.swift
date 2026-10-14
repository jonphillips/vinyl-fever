import Foundation
import Testing
import VinylFeverCore

@Suite("Catalog match scorer")
struct CatalogMatchScorerTests {
  @Test("an exact match is accepted")
  func exactMatch() {
    let candidate = song("The Records", "Starry Eyes")
    let outcome = CatalogMatchScorer.score(request("The Records", "Starry Eyes"), candidates: [candidate])
    #expect(outcome == .matched(candidate, score: 0.9))
  }

  @Test("the studio original beats unrequested karaoke, tribute, and live versions")
  func studioOriginalWins() {
    let original = song("The Records", "Starry Eyes")
    let candidates = [
      song("The Records", "Starry Eyes (Karaoke Version)"),
      song("The Records", "Starry Eyes (Tribute)"),
      song("The Records", "Starry Eyes (Live at the Fillmore)"),
      original,
    ]
    #expect(CatalogMatchScorer.score(request("The Records", "Starry Eyes"), candidates: candidates) == .matched(original, score: 0.9))
  }

  @Test("a requested live version wins over the studio original")
  func requestedLiveWins() {
    let live = song("The Records", "Starry Eyes (Live at the Fillmore)")
    let outcome = CatalogMatchScorer.score(request("The Records", "Starry Eyes (Live at the Fillmore)"), candidates: [
      song("The Records", "Starry Eyes"), live,
    ])
    #expect(outcome == .matched(live, score: 0.9))
  }

  @Test("album and year hints break a same-title tie")
  func hintsBreakTie() throws {
    let wrong = song("Shoes", "Too Late", album: "Present Tense", year: 1979)
    let hinted = song("Shoes", "Too Late", album: "Black Vinyl Shoes", year: 1977)
    let outcome = CatalogMatchScorer.score(request("Shoes", "Too Late", album: "Black Vinyl Shoes", year: 1977), candidates: [wrong, hinted])
    guard case let .matched(candidate, score) = outcome else {
      Issue.record("Expected hinted catalog song to be matched")
      return
    }
    #expect(candidate == hinted)
    #expect(score == 1)
  }

  @Test("two close candidates remain ambiguous")
  func ambiguous() {
    let first = song("The Shoes", "Too Late")
    let second = song("Shoe", "Too Late")
    let outcome = CatalogMatchScorer.score(request("Shoes", "Too Late"), candidates: [first, second])
    guard case let .ambiguous(candidates) = outcome else {
      Issue.record("Expected similar candidates to remain ambiguous")
      return
    }
    #expect(candidates.count == 2)
    #expect(candidates.first?.candidate.id == "Shoe-Too Late")
  }

  @Test("nothing close is not found")
  func notFound() {
    #expect(CatalogMatchScorer.score(request("Nirvana", "Lithium"), candidates: [song("The Records", "Starry Eyes")]) == .notFound)
  }

  private func request(_ artist: String, _ title: String, album: String? = nil, year: Int? = nil) -> TrackRequest {
    TrackRequest(index: 1, artist: artist, title: title, album: album, year: year)
  }

  private func song(_ artist: String, _ title: String, album: String? = nil, year: Int? = nil) -> CatalogSongCandidate {
    CatalogSongCandidate(
      id: "\(artist)-\(title)",
      title: title,
      artistName: artist,
      albumTitle: album,
      releaseDate: year.flatMap { Calendar(identifier: .gregorian).date(from: DateComponents(year: $0, month: 1, day: 1)) }
    )
  }
}
