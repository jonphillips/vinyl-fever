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

  @Test("same song across albums auto-matches the earliest release without hints")
  func sameSongUsesEarliestRelease() {
    let original = song("Eagles", "Hotel California", album: "Hotel California", year: 1976)
    let compilation = song("Eagles", "Hotel California", album: "The Very Best Of", year: 2003)
    #expect(CatalogMatchScorer.score(request("Eagles", "Hotel California"), candidates: [compilation, original]) == .matched(original, score: 0.9))
  }

  @Test("a year hint alone can select another album for the same song")
  func yearHintSelectsAlbum() {
    let original = song("Eagles", "Hotel California", album: "Hotel California", year: 1976)
    let compilation = song("Eagles", "Hotel California", album: "The Very Best Of", year: 2003)
    let outcome = CatalogMatchScorer.score(request("Eagles", "Hotel California", year: 2003), candidates: [original, compilation])
    guard case let .matched(candidate, score) = outcome else {
      Issue.record("Expected the year-hinted album to be matched")
      return
    }
    #expect(candidate == compilation)
    #expect(abs(score - 0.95) < 1e-9)
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

  @Test("ordinary uses of with remain part of a title")
  func withIsNotAFeatureUnlessBracketed() {
    let shout = CatalogMatchScorer.score(request("U2", "With or Without You"), candidates: [song("U2", "With a Shout")])
    let devil = CatalogMatchScorer.score(request("Billy Idol", "Dancing with Myself"), candidates: [song("Billy Idol", "Dancing with the Devil")])
    #expect(isNotMatched(shout))
    #expect(isNotMatched(devil))
  }

  @Test("featuring credits inside a title parenthetical are ignored")
  func titleFeatureCredit() {
    let request = request("Artist", "Song (feat. Guest)")
    let candidate = song("Artist", "Song")
    #expect(CatalogMatchScorer.score(request, candidate) == 0.9)
  }

  @Test("a bracketed with-credit is ignored")
  func bracketedWithCredit() {
    #expect(CatalogMatchScorer.score(request("Artist", "Song [with Guest]"), song("Artist", "Song")) == 0.9)
  }

  @Test("a studio request does not match a live version whose parenthetical contains with")
  func studioRequestSkipsLiveWith() {
    let studio = song("Eagles", "Hotel California", year: 1976)
    let live = song("Eagles", "Hotel California (Live with the Orchestra)", year: 1975)
    let outcome = CatalogMatchScorer.score(request("Eagles", "Hotel California"), candidates: [studio, live])
    #expect(outcome == .matched(studio, score: 0.9))
  }

  @Test("a requested live-with version beats the studio original")
  func liveWithRequestWins() {
    let studio = song("Eagles", "Hotel California", year: 1974)
    let live = song("Eagles", "Hotel California (Live with the Orchestra)", year: 1994)
    let outcome = CatalogMatchScorer.score(
      request("Eagles", "Hotel California (Live with the Orchestra)"),
      candidates: [studio, live]
    )
    #expect(outcome == .matched(live, score: 0.9))
  }

  @Test("parenthetical, bracketed, and dash remaster suffixes are ignored")
  func remasterSuffixes() {
    let request = request("Artist", "Song")
    #expect(CatalogMatchScorer.score(request, song("Artist", "Song (Remastered)")) == 0.9)
    #expect(CatalogMatchScorer.score(request, song("Artist", "Song [2011 Remaster]")) == 0.9)
    #expect(CatalogMatchScorer.score(request, song("Artist", "Song - Remastered 2009")) == 0.9)
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

  private func isNotMatched(_ outcome: MatchOutcome) -> Bool {
    if case .matched = outcome { return false }
    return true
  }
}
