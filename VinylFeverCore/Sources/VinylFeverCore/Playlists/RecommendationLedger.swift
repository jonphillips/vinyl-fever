import Foundation
import VinylFeverListening
import VinylFeverNotes

public struct RecommendationEvidence: Codable, Equatable, Sendable {
  public var count: Int
  public var latestRecordedAt: Date
  public var latestWhy: String?
  public var latestOutcome: String?
  public init(count: Int, latestRecordedAt: Date, latestWhy: String? = nil, latestOutcome: String? = nil) {
    self.count = count; self.latestRecordedAt = latestRecordedAt
    self.latestWhy = latestWhy; self.latestOutcome = latestOutcome
  }
  private enum CodingKeys: String, CodingKey { case count, latestRecordedAt, latestWhy, latestOutcome }
  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(count, forKey: .count); try values.encode(latestRecordedAt, forKey: .latestRecordedAt)
    try values.encodeIfPresent(latestWhy, forKey: .latestWhy)
    try values.encodeIfPresent(latestOutcome, forKey: .latestOutcome)
  }
}

/// One-pass index of unfamiliar songs in the recommendation ledger.
public struct RecommendationLedgerEvidenceIndex: Sendable {
  public let identity: ArtistIdentity
  private let evidenceBySong: [String: RecommendationEvidence]

  public init(ledger: RecommendationLedgerReadResult, identity: ArtistIdentity) {
    self.identity = identity
    var evidence: [String: RecommendationEvidence] = [:]
    for batch in ledger.batches where batch.kind == "staged-playlist" {
      // A batch contributes at most once per song, even if its input repeats a row.
      let keys = Set(batch.tracks.lazy.filter { !$0.familiar }.map {
        TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity)
      })
      for key in keys {
        if let current = evidence[key] {
          let latest = batch.recordedAt >= current.latestRecordedAt
          let why = batch.tracks.first(where: { !$0.familiar && TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) == key })?.why
          evidence[key] = RecommendationEvidence(count: current.count + 1,
            latestRecordedAt: max(current.latestRecordedAt, batch.recordedAt), latestWhy: latest ? why : current.latestWhy)
        } else {
          let why = batch.tracks.first(where: { !$0.familiar && TasteIntelligence.songKey(artist: $0.artist, title: $0.title, identity: identity) == key })?.why
          evidence[key] = RecommendationEvidence(count: 1, latestRecordedAt: batch.recordedAt, latestWhy: why)
        }
      }
    }
    evidenceBySong = evidence
  }

  public func forSong(artist: String, title: String) -> RecommendationEvidence? {
    evidenceBySong[TasteIntelligence.songKey(artist: artist, title: title, identity: identity)]
  }
}

/// Immutable lookups shared by every row in one stage request.
public struct RecommendationFamiliarityIndex: Sendable {
  private let identity: ArtistIdentity
  private let libraryIndex: LibraryIndex
  private let playlistIndex: PlaylistIndex
  private let tasteNoteKeys: Set<String>
  private let recommendationEvidence: RecommendationLedgerEvidenceIndex
  private let knownArtistKeys: Set<String>
  private let heardArtistsByTitle: [String: Set<String>]
  private let heardArtistKeys: Set<String>
  private let recordedAt: Date

  public init(snapshot: LibrarySnapshot, index: LibraryIndex, playlistIndex: PlaylistIndex,
    listeningLog: ListeningLog?, tasteNoteKeys: Set<String>, ledger: RecommendationLedgerReadResult,
    recordedAt: Date) {
    self.init(snapshot: snapshot, index: index, playlistIndex: playlistIndex,
      listeningLog: listeningLog, tasteNoteKeys: tasteNoteKeys,
      recommendationEvidence: RecommendationLedgerEvidenceIndex(ledger: ledger, identity: index.artistIdentity),
      recordedAt: recordedAt)
  }

  public init(snapshot: LibrarySnapshot, index: LibraryIndex, playlistIndex: PlaylistIndex,
    listeningLog: ListeningLog?, tasteNoteKeys: Set<String>, recommendationEvidence: RecommendationLedgerEvidenceIndex,
    recordedAt: Date) {
    let identity = index.artistIdentity
    self.identity = identity
    self.libraryIndex = index
    self.playlistIndex = playlistIndex
    self.tasteNoteKeys = tasteNoteKeys
    self.recommendationEvidence = recommendationEvidence
    self.recordedAt = recordedAt

    let uniqueLibraryArtists = Set(snapshot.tracks.lazy.map(\.artist))
    knownArtistKeys = Set(uniqueLibraryArtists.map { identity.key($0) })

    var artistsByTitle: [String: Set<String>] = [:]
    var heardArtists = Set<String>()
    for play in listeningLog?.plays ?? [] where play.windowStart < recordedAt {
      let credits = identity.credits(play.item.artist)
      heardArtists.formUnion(credits)
      let title = SongTextNormalizer.libraryTitle(play.item.title)
      for credit in credits { artistsByTitle["\(credit)\u{0}\(title)", default: []].formUnion(credits) }
    }
    heardArtistsByTitle = artistsByTitle
    heardArtistKeys = heardArtists
  }

  public func evaluate(artist: String, title: String, album: String? = nil, year: Int? = nil) -> RecommendationTrack {
    let credits = identity.credits(artist)
    let titleKey = SongTextNormalizer.libraryTitle(title)
    let key = TasteIntelligence.songKey(artist: artist, title: title, identity: identity)
    let heard = credits.contains { heardArtistsByTitle["\($0)\u{0}\(titleKey)"] != nil }
    let memberships = playlistIndex.membershipsBySong[key, default: []].filter {
      $0.role != .ignore && $0.role != .followed
    }
    let playlistReasons = Set(memberships.map { "playlist:\($0.role?.rawValue ?? "unlabeled")" }).sorted()
    let noted = tasteNoteKeys.contains(key)
    let recommended = recommendationEvidence.forSong(artist: artist, title: title) != nil
    var reasons: [String] = []
    if libraryIndex.checkTracks([(artist: artist, title: title)]).first?.owned == true { reasons.append("owned") }
    if heard { reasons.append("heard") }
    reasons += playlistReasons
    if noted { reasons.append("noted") }
    if recommended { reasons.append("recommended") }
    let artistKnown = knownArtistKeys.contains(identity.key(artist)) || credits.contains { heardArtistKeys.contains($0) }
    return RecommendationTrack(artist: artist, title: title, album: album, year: year,
      familiar: !reasons.isEmpty, reasons: reasons, artistKnown: artistKnown)
  }
}

public enum RecommendationLedgerEvidence {
  public static func forSong(artist: String, title: String, identity: ArtistIdentity,
    ledger: RecommendationLedgerReadResult) -> RecommendationEvidence? {
    RecommendationLedgerEvidenceIndex(ledger: ledger, identity: identity).forSong(artist: artist, title: title)
  }
}
