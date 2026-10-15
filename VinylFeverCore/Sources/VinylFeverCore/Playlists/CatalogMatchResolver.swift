import Dependencies
import DependenciesMacros
import Foundation

public struct ResolvedPlaylistRow: Equatable, Sendable, Identifiable {
  public enum Status: Equatable, Sendable {
    case matched(CatalogSongCandidate, score: Double)
    case ambiguous([ScoredCandidate])
    case notFound(error: String?)
    case duplicate(CatalogSongCandidate, ofTrackIndex: Int)
  }

  public var request: TrackRequest
  public var status: Status
  public var id: Int { request.index }

  public init(request: TrackRequest, status: Status) {
    self.request = request
    self.status = status
  }
}

@DependencyClient
public struct CatalogMatchResolver: Sendable {
  public var resolve: @Sendable (_ request: PlaylistRequest) async -> [ResolvedPlaylistRow] = { _ in [] }
}

extension CatalogMatchResolver: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension CatalogMatchResolver {
  public static let searchResultLimit = 10
  public static let maximumConcurrentSearches = 2
  public static let maximumSearchAttempts = 3
  public static let searchRetryDelay: Duration = .seconds(1)

  public static var liveValue: Self {
    @Dependency(\.appleMusicCatalogClient) var client
    @Dependency(\.continuousClock) var clock
    return Self { request in
      await resolve(request, clock: clock, search: { term in
        try await client.searchSongs(term, searchResultLimit)
      })
    }
  }

  /// Runs one catalog search. A rate-limited or unreadable response is retried up to
  /// `maximumSearchAttempts` times, waiting `searchRetryDelay` and then double that, plus jitter.
  public static func search(
    _ term: String,
    clock: any Clock<Duration>,
    search: @Sendable (String) async throws -> [CatalogSongCandidate]
  ) async throws -> [CatalogSongCandidate] {
    var attempt = 1
    while true {
      do {
        return try await search(term)
      } catch let error where isRetryable(error) && attempt < maximumSearchAttempts {
        try await clock.sleep(for: retryDelay(afterAttempt: attempt, jitter: .milliseconds(Int.random(in: 0...250))))
        attempt += 1
      }
    }
  }

  public static func retryDelay(afterAttempt attempt: Int, jitter: Duration) -> Duration {
    searchRetryDelay * (1 << (attempt - 1)) + jitter
  }

  public static func isRetryable(_ error: any Error) -> Bool {
    switch error {
    case is AppleMusicCatalogBusyError: true
    case let error as AppleMusicAPIError: error.statusCode == 429 || (500..<600).contains(error.statusCode)
    default: false
    }
  }

  public static func resolve(
    _ request: PlaylistRequest,
    maximumConcurrentSearches: Int = Self.maximumConcurrentSearches,
    clock: any Clock<Duration> = ContinuousClock(),
    search: @escaping @Sendable (String) async throws -> [CatalogSongCandidate]
  ) async -> [ResolvedPlaylistRow] {
    let requests = request.tracks
    guard !requests.isEmpty else { return [] }
    let concurrency = max(1, min(maximumConcurrentSearches, requests.count))
    var results = Array<ResolvedPlaylistRow?>(repeating: nil, count: requests.count)
    var nextIndex = 0

    await withTaskGroup(of: (Int, ResolvedPlaylistRow.Status).self) { group in
      for _ in 0..<concurrency {
        let index = nextIndex
        nextIndex += 1
        group.addTask { (index, await match(requests[index], clock: clock, search: search)) }
      }
      while let (index, status) = await group.next() {
        results[index] = ResolvedPlaylistRow(request: requests[index], status: status)
        if nextIndex < requests.count {
          let newIndex = nextIndex
          nextIndex += 1
          group.addTask { (newIndex, await match(requests[newIndex], clock: clock, search: search)) }
        }
      }
    }

    var firstTrackIndexByCatalogID: [String: Int] = [:]
    return results.compactMap { optionalRow in
      guard var row = optionalRow else { return nil }
      if case let .matched(candidate, _) = row.status {
        if let firstIndex = firstTrackIndexByCatalogID[candidate.id] {
          row.status = .duplicate(candidate, ofTrackIndex: firstIndex)
        } else {
          firstTrackIndexByCatalogID[candidate.id] = row.request.index
        }
      }
      return row
    }
  }

  private static func match(
    _ request: TrackRequest,
    clock: any Clock<Duration>,
    search: @escaping @Sendable (String) async throws -> [CatalogSongCandidate]
  ) async -> ResolvedPlaylistRow.Status {
    do {
      let candidates = try await Self.search("\(request.artist) \(request.title)", clock: clock, search: search)
      switch CatalogMatchScorer.score(request, candidates: candidates) {
      case let .matched(candidate, score): return .matched(candidate, score: score)
      case let .ambiguous(candidates): return .ambiguous(candidates)
      case .notFound: return .notFound(error: nil)
      }
    } catch {
      return .notFound(error: error.localizedDescription)
    }
  }
}

extension DependencyValues {
  public var catalogMatchResolver: CatalogMatchResolver {
    get { self[CatalogMatchResolver.self] }
    set { self[CatalogMatchResolver.self] = newValue }
  }
}
