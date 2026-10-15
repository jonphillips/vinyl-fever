import Dependencies
import DependenciesMacros
import Foundation

public struct ResolvedPlaylistRow: Equatable, Sendable, Identifiable {
  public enum Status: Equatable, Sendable {
    case matched(CatalogSongCandidate, score: Double)
    case ambiguous([ScoredCandidate])
    case notFound(error: String?)
    case duplicate(ofTrackIndex: Int)
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
  public static let maximumConcurrentSearches = 4

  public static var liveValue: Self {
    @Dependency(\.appleMusicCatalogClient) var client
    return Self { request in
      await resolve(request, search: { term in
        try await client.searchSongs(term, searchResultLimit)
      })
    }
  }

  public static func resolve(
    _ request: PlaylistRequest,
    maximumConcurrentSearches: Int = Self.maximumConcurrentSearches,
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
        group.addTask { (index, await match(requests[index], search: search)) }
      }
      while let (index, status) = await group.next() {
        results[index] = ResolvedPlaylistRow(request: requests[index], status: status)
        if nextIndex < requests.count {
          let newIndex = nextIndex
          nextIndex += 1
          group.addTask { (newIndex, await match(requests[newIndex], search: search)) }
        }
      }
    }

    var firstTrackIndexByCatalogID: [String: Int] = [:]
    return results.compactMap { optionalRow in
      guard var row = optionalRow else { return nil }
      if case let .matched(candidate, _) = row.status {
        if let firstIndex = firstTrackIndexByCatalogID[candidate.id] {
          row.status = .duplicate(ofTrackIndex: firstIndex)
        } else {
          firstTrackIndexByCatalogID[candidate.id] = row.request.index
        }
      }
      return row
    }
  }

  private static func match(
    _ request: TrackRequest,
    search: @escaping @Sendable (String) async throws -> [CatalogSongCandidate]
  ) async -> ResolvedPlaylistRow.Status {
    do {
      let candidates = try await search("\(request.artist) \(request.title)")
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
