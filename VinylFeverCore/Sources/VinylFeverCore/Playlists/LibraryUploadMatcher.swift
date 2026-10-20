import Foundation

public enum LibraryUploadMatcher {
  // The S0 picker is capped at the three most-played uploads in its brief.
  public static let uploadPickerLimit = 3

  public enum Outcome: Equatable, Sendable {
    case matched(CatalogSongCandidate)
    case ambiguous([CatalogSongCandidate])
    case notFound(reason: String)
    case failed(String)
  }

  public static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
    let left = SongTextNormalizer.artist(lhs)
    let right = SongTextNormalizer.artist(rhs)
    return left == right || left.hasPrefix(right + " ") || right.hasPrefix(left + " ")
  }

  public static func match(
    _ request: TrackRequest,
    albumHint: String? = nil,
    clock: any Clock<Duration> = ContinuousClock(),
    searchAlbums: @escaping @Sendable (String) async throws -> [LibraryAlbumCandidate],
    albumTracks: @escaping @Sendable (String) async throws -> [LibrarySongCandidate],
    searchSongs: @escaping @Sendable (String, Int) async throws -> [LibrarySongCandidate]
  ) async -> Outcome {
    let album = albumHint ?? request.album
    if let album, !album.isEmpty {
      do {
        for term in terms(album) {
          let albums = try await CatalogMatchResolver.retryingSearch(
            term, clock: clock, search: searchAlbums)
          guard !albums.isEmpty else { continue }
          let albumKey = SongTextNormalizer.album(album)
          let exact = albums.filter { SongTextNormalizer.album($0.title) == albumKey }
          var candidates: [LibrarySongCandidate] = []
          for value in exact {
            candidates += try await CatalogMatchResolver.retryingSearch(
              value.id, clock: clock, search: albumTracks)
          }
          let matching = exactMatches(candidates, request: request, album: album)
          if !matching.isEmpty { return outcome(matching) }
          break
        }
      } catch {
        return .failed(error.localizedDescription)
      }
    }

    do {
      for term in terms(request.title) {
        let first = try await CatalogMatchResolver.retryingSearch(term, clock: clock) {
          try await searchSongs($0, 0)
        }
        var candidates = first
        var page = first
        while candidates.count < AppleMusicCatalogClient.librarySongSearchCap,
          page.count == AppleMusicCatalogClient.librarySearchPageSize
        {
          let offset = candidates.count
          page = try await CatalogMatchResolver.retryingSearch(term, clock: clock) {
            try await searchSongs($0, offset)
          }
          candidates += page
        }
        let matching = exactMatches(candidates, request: request, album: album)
          .prefix(AppleMusicCatalogClient.librarySongSearchCap).map { $0 }
        if !matching.isEmpty { return outcome(matching) }
        if candidates.count >= AppleMusicCatalogClient.librarySongSearchCap { break }
      }
      return .notFound(reason: "Apple Music's library search couldn't reach this upload.")
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  private static func exactMatches(
    _ values: [LibrarySongCandidate], request: TrackRequest, album: String?
  ) -> [CatalogSongCandidate] {
    values.filter { value in
      let albumMatches = album.map {
        SongTextNormalizer.album(value.album) == SongTextNormalizer.album($0)
      } ?? true
      return !value.hasCatalogID
        && SongTextNormalizer.title(value.title) == SongTextNormalizer.title(request.title)
        && artistsMatch(value.artist, request.artist)
        && albumMatches
    }.map(\.candidate)
  }

  private static func outcome(_ values: [CatalogSongCandidate]) -> Outcome {
    var seen: Set<String> = []
    let unique = values.filter { seen.insert($0.id).inserted }
    return unique.count == 1 ? .matched(unique[0]) : .ambiguous(unique)
  }

  private static func terms(_ value: String) -> [String] {
    let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.count > 2 else { return [value] }
    return (2...words.count).reversed().map { words.prefix($0).joined(separator: " ") }
  }
}
