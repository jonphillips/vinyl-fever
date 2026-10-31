import Dependencies
import Foundation
import VinylFeverNotes

public struct ListeningDiffResult: Equatable, Sendable {
  /// A `.failed` result must not replace the poller's saved `last-list.json` value.
  public var outcome: ListeningFetch.Outcome
  public var items: [ListeningItem]
  public var newCount: Int
  public var pagesRead: Int
  public var currentList: [ListeningItem]
  public var error: String?

  public init(
    outcome: ListeningFetch.Outcome, items: [ListeningItem], newCount: Int,
    pagesRead: Int, currentList: [ListeningItem], error: String? = nil
  ) {
    self.outcome = outcome
    self.items = items
    self.newCount = newCount
    self.pagesRead = pagesRead
    self.currentList = currentList
    self.error = error
  }
}

public struct ListeningDiff {
  /// The API's page size, page cap, and retained overlap evidence are fixed by the M13 probe and
  /// build order: 30 per page, ten pages (300 items), and ten items of evidence.
  public static let pageSize = 30
  public static let pageCap = 10
  public static let overlapEvidenceCount = 10

  @Dependency(\.recentlyPlayedClient) private var recentlyPlayedClient

  public init() {}

  /// Fetches enough pages to find overlap with the previous newest-first feed. The initial fetch
  /// is a baseline. If overlap is absent within the page cap, all fetched items are returned as a
  /// loud gap.
  public func fetch(previous: [ListeningItem]?) async throws -> ListeningDiffResult {
    var current: [ListeningItem] = []
    var pagesRead = 0
    var resolvedMatch: ListeningDiffMatch?

    for pageIndex in 0..<Self.pageCap {
      let page = try await recentlyPlayedClient.page(pageIndex * Self.pageSize)
      pagesRead += 1
      if pageIndex == 0, let previous, !previous.isEmpty, page.items.isEmpty {
        return ListeningDiffResult(
          outcome: .failed, items: [], newCount: 0, pagesRead: pagesRead,
          currentList: previous, error: "Apple Music returned an empty recently-played list."
        )
      }
      current.append(contentsOf: page.items)
      let reachedEnd = !page.hasNext

      if let previous, resolvedMatch == nil {
        resolvedMatch = Self.resolve(previous: previous, current: current, reachedEnd: reachedEnd)
      }

      if case let .match(newCount, evidence)? = resolvedMatch {
        let newItems = Array(current.prefix(newCount))
        let outcome: ListeningFetch.Outcome = newCount == 0 ? .none : .plays
        let loggedItems = newCount == 0 ? [] : newItems + evidence
        return ListeningDiffResult(
          outcome: outcome, items: loggedItems, newCount: newCount,
          pagesRead: pagesRead, currentList: current
        )
      }

      if reachedEnd || pageIndex == Self.pageCap - 1 {
        if previous == nil {
          return ListeningDiffResult(
            outcome: .baseline, items: current, newCount: 0,
            pagesRead: pagesRead, currentList: current
          )
        }
        return ListeningDiffResult(
          outcome: .gap, items: current, newCount: current.count,
          pagesRead: pagesRead, currentList: current
        )
      }
    }

    return ListeningDiffResult(
      outcome: .gap, items: current, newCount: current.count,
      pagesRead: pagesRead, currentList: current
    )
  }

  /// Returns a result once enough of the old stream is visible to establish overlap. A nil result
  /// means the caller should read another page (or emit `gap` after reaching the cap).
  public static func resolve(
    previous: [ListeningItem], current: [ListeningItem], reachedEnd: Bool
  ) -> ListeningDiffMatch? {
    for newCount in 0...current.count {
      let newIdentities = Set(current.prefix(newCount).map(\.identity))
      let remainingPrevious = previous.filter { !newIdentities.contains($0.identity) }
      let currentSuffix = current.dropFirst(newCount)
      let expectedEvidence = min(overlapEvidenceCount, remainingPrevious.count)
      let availableEvidence = min(expectedEvidence, currentSuffix.count)

      if availableEvidence == 0 {
        if reachedEnd && remainingPrevious.isEmpty && currentSuffix.isEmpty {
          return .match(newCount: newCount, evidence: [])
        }
        continue
      }
      if availableEvidence < expectedEvidence && !reachedEnd {
        continue
      }
      guard zip(currentSuffix.prefix(availableEvidence), remainingPrevious.prefix(availableEvidence))
        .allSatisfy({ $0.0.identity == $0.1.identity })
      else { continue }

      let evidence = Array(currentSuffix.prefix(overlapEvidenceCount))
      return .match(newCount: newCount, evidence: evidence)
    }
    return nil
  }
}

public enum ListeningDiffMatch: Equatable, Sendable {
  case match(newCount: Int, evidence: [ListeningItem])
}
