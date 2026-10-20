import Foundation
import VinylFeverListening

public struct CatalogSongCandidate: Equatable, Sendable {
  public enum Source: String, Equatable, Sendable { case catalog, libraryUpload }
  public let id: String
  public let title: String
  public let artistName: String
  public let albumTitle: String?
  public let releaseDate: Date?
  public let durationSeconds: Double?
  public let isrc: String?
  public let source: Source

  public init(
    id: String,
    title: String,
    artistName: String,
    albumTitle: String? = nil,
    releaseDate: Date? = nil,
    durationSeconds: Double? = nil,
    isrc: String? = nil,
    source: Source = .catalog
  ) {
    self.id = id
    self.title = title
    self.artistName = artistName
    self.albumTitle = albumTitle
    self.releaseDate = releaseDate
    self.durationSeconds = durationSeconds
    self.isrc = isrc
    self.source = source
  }
}

public struct ScoredCandidate: Equatable, Sendable {
  public let candidate: CatalogSongCandidate
  public let score: Double

  public init(candidate: CatalogSongCandidate, score: Double) {
    self.candidate = candidate
    self.score = score
  }
}

public enum MatchOutcome: Equatable, Sendable {
  case matched(CatalogSongCandidate, score: Double)
  case ambiguous([ScoredCandidate])
  case notFound
}

public enum CatalogMatchScorer {
  public static let autoMatchThreshold = 0.90
  public static let autoMatchLead = 0.10
  public static let ambiguousFloor = 0.60
  public static let versionPenalty = 0.30
  public static let hintBoost = 0.05
  public static let ambiguousCandidateLimit = 3

  private static let versionTerms = [
    "originally performed", "karaoke", "instrumental", "tribute", "live", "cover",
    "remix", "acoustic", "demo", "sped up", "slowed",
  ]

  public static func score(
    _ request: TrackRequest, candidates: [CatalogSongCandidate], identity: ArtistIdentity = .empty
  )
    -> MatchOutcome
  {
    let ranked =
      candidates
      .map { candidate in
        ScoredCandidate(candidate: candidate, score: score(request, candidate, identity: identity))
      }
      .sorted(by: orderedBefore)
    guard let first = ranked.first, first.score >= ambiguousFloor else { return .notFound }
    let firstTitle = SongTextNormalizer.title(first.candidate.title)
    let firstArtist = identity.key(first.candidate.artistName)
    let bestDifferentSong = ranked.dropFirst().first {
      SongTextNormalizer.title($0.candidate.title) != firstTitle
        || identity.key($0.candidate.artistName) != firstArtist
    }
    let lead = first.score - (bestDifferentSong?.score ?? 0)
    if first.score >= autoMatchThreshold && lead + 1e-9 >= autoMatchLead {
      return .matched(first.candidate, score: first.score)
    }
    return .ambiguous(Array(ranked.prefix(ambiguousCandidateLimit)))
  }

  public static func score(
    _ request: TrackRequest, _ candidate: CatalogSongCandidate, identity: ArtistIdentity = .empty
  ) -> Double {
    let titleScore = similarity(
      SongTextNormalizer.title(request.title), SongTextNormalizer.title(candidate.title))
    let artistScore = identity.matches(request: request.artist, track: candidate.artistName)
      ? 1
      : similarity(
        SongTextNormalizer.artist(request.artist), SongTextNormalizer.artist(candidate.artistName))
    // The base match tops out at 0.90 so the two hint boosts remain useful when
    // otherwise-identical catalog entries need to be separated.
    var score = (titleScore * 0.55) + (artistScore * 0.35)

    let requestedVersionText = " \(SongTextNormalizer.title(request.title)) "
    let candidateVersionText = " \(SongTextNormalizer.title(candidate.title)) "
    for term in versionTerms {
      let normalizedTerm = " \(SongTextNormalizer.text(term)) "
      if candidateVersionText.contains(normalizedTerm)
        && !requestedVersionText.contains(normalizedTerm)
      {
        score -= versionPenalty
      }
    }

    if let requestedAlbum = request.album, let candidateAlbum = candidate.albumTitle,
      SongTextNormalizer.album(requestedAlbum) == SongTextNormalizer.album(candidateAlbum)
    {
      score += hintBoost
    }
    if let requestedYear = request.year, let releaseDate = candidate.releaseDate,
      releaseYear(releaseDate) == requestedYear
    {
      score += hintBoost
    }
    return min(1, max(0, score))
  }

  private static func similarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return lhs == rhs ? 1 : 0 }
    if lhs == rhs { return 1 }
    let left = Array(lhs)
    let right = Array(rhs)
    var previous = Array(0...right.count)
    for (leftIndex, leftCharacter) in left.enumerated() {
      var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
      for (rightIndex, rightCharacter) in right.enumerated() {
        let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
        current[rightIndex + 1] = min(
          previous[rightIndex + 1] + 1, min(current[rightIndex] + 1, substitution))
      }
      previous = current
    }
    let distance = previous[right.count]
    return 1 - (Double(distance) / Double(max(left.count, right.count)))
  }

  private static func releaseYear(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar.component(.year, from: date)
  }

  private static func orderedBefore(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    switch (lhs.candidate.releaseDate, rhs.candidate.releaseDate) {
    case (let left?, let right?): return left < right
    case (_?, nil): return true
    case (nil, _?): return false
    case (nil, nil): return lhs.candidate.id < rhs.candidate.id
    }
  }
}
