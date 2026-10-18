import Dependencies
import Foundation
import MusicKit

public enum ListeningAuthorizationStatus: Equatable, Sendable {
  case authorized
  case notDetermined
  case denied
  case restricted
  case unknown
}

public struct ListeningAuthorizationClient: Sendable {
  public var status: @Sendable () async -> ListeningAuthorizationStatus

  public init(status: @escaping @Sendable () async -> ListeningAuthorizationStatus) {
    self.status = status
  }
}

extension ListeningAuthorizationClient: TestDependencyKey {
  public static var testValue: Self { Self(status: { .notDetermined }) }
}

extension ListeningAuthorizationClient: DependencyKey {
  public static var liveValue: Self {
    Self(status: {
      switch MusicAuthorization.currentStatus {
      case .authorized: .authorized
      case .notDetermined: .notDetermined
      case .denied: .denied
      case .restricted: .restricted
      @unknown default: .unknown
      }
    })
  }
}

extension DependencyValues {
  public var listeningAuthorizationClient: ListeningAuthorizationClient {
    get { self[ListeningAuthorizationClient.self] }
    set { self[ListeningAuthorizationClient.self] = newValue }
  }
}

public struct ListeningStore: Sendable {
  public var pollerID: @Sendable () throws -> UUID
  public var readLease: @Sendable () throws -> ListeningLease?
  public var writeLease: @Sendable (ListeningLease) throws -> Void
  public var readLastList: @Sendable () throws -> [ListeningItem]?
  public var writeLastList: @Sendable ([ListeningItem]) throws -> Void
  public var appendFetch: @Sendable (ListeningFetch) throws -> Void
  public var readFetches: @Sendable () throws -> [ListeningFetch]
  public var readLastPollError: @Sendable () throws -> String?
  public var writeLastPollError: @Sendable (String?) throws -> Void
  public var listeningFolder: @Sendable () -> URL
  public var hostName: @Sendable () -> String

  public init(
    pollerID: @escaping @Sendable () throws -> UUID,
    readLease: @escaping @Sendable () throws -> ListeningLease?,
    writeLease: @escaping @Sendable (ListeningLease) throws -> Void,
    readLastList: @escaping @Sendable () throws -> [ListeningItem]?,
    writeLastList: @escaping @Sendable ([ListeningItem]) throws -> Void,
    appendFetch: @escaping @Sendable (ListeningFetch) throws -> Void,
    readFetches: @escaping @Sendable () throws -> [ListeningFetch] = { [] },
    readLastPollError: @escaping @Sendable () throws -> String? = { nil },
    writeLastPollError: @escaping @Sendable (String?) throws -> Void = { _ in },
    listeningFolder: @escaping @Sendable () -> URL,
    hostName: @escaping @Sendable () -> String = { "Mac" }
  ) {
    self.pollerID = pollerID
    self.readLease = readLease
    self.writeLease = writeLease
    self.readLastList = readLastList
    self.writeLastList = writeLastList
    self.appendFetch = appendFetch
    self.readFetches = readFetches
    self.readLastPollError = readLastPollError
    self.writeLastPollError = writeLastPollError
    self.listeningFolder = listeningFolder
    self.hostName = hostName
  }
}

extension ListeningStore: TestDependencyKey, DependencyKey {
  public static var testValue: Self {
    Self(
      pollerID: { UUID() }, readLease: { nil }, writeLease: { _ in },
      readLastList: { nil }, writeLastList: { _ in }, appendFetch: { _ in }, readFetches: { [] },
      readLastPollError: { nil }, writeLastPollError: { _ in },
      listeningFolder: { URL(fileURLWithPath: "/tmp/Listening") }, hostName: { "Test Mac" }
    )
  }

}

extension DependencyValues {
  public var listeningStore: ListeningStore {
    get { self[ListeningStore.self] }
    set { self[ListeningStore.self] = newValue }
  }
}

public enum ListeningPollResult: Equatable, Sendable {
  case skipped
  case fetched(ListeningFetch)
}

public struct ListeningPoller {
  @Dependency(\.listeningStore) private var store
  @Dependency(\.listeningAuthorizationClient) private var authorization
  @Dependency(\.recentlyPlayedClient) private var recentlyPlayed
  @Dependency(\.date) private var date

  public init() {}

  public func pollOnce() async throws -> ListeningPollResult {
    do {
      let result = try await performPollOnce()
      try store.writeLastPollError(nil)
      return result
    } catch {
      try? store.writeLastPollError(error.localizedDescription)
      throw error
    }
  }

  private func performPollOnce() async throws -> ListeningPollResult {
    let poller = try store.pollerID()
    let host = store.hostName()
    let now = date()
    let lease = try store.readLease()
    switch ListeningLeaseRules.decision(current: lease, poller: poller) {
    case .skip:
      return .skipped
    case .claimIfEmpty:
      try store.writeLease(ListeningLease(poller: poller, host: host, takenAt: now))
    case .write:
      break
    }

    guard await authorization.status() == .authorized else {
      let failed = ListeningFetch(
        poller: poller, host: host, fetchedAt: now, outcome: .failed,
        pagesRead: 0, error: "Apple Music isn't authorized on this Mac."
      )
      try store.appendFetch(failed)
      return .fetched(failed)
    }

    let previous = try store.readLastList()
    let diff: ListeningDiffResult
    do {
      diff = try await withDependencies({ $0.recentlyPlayedClient = recentlyPlayed }) {
        try await ListeningDiff().fetch(previous: previous)
      }
    } catch {
      let failed = ListeningFetch(
        poller: poller, host: host, fetchedAt: now, outcome: .failed,
        pagesRead: 0, error: error.localizedDescription
      )
      try store.appendFetch(failed)
      return .fetched(failed)
    }

    let fetch = ListeningFetch(
      poller: poller, host: host, fetchedAt: now, outcome: diff.outcome,
      newCount: diff.newCount, pagesRead: diff.pagesRead, items: diff.items,
      error: diff.error
    )
    try store.appendFetch(fetch)
    if fetch.outcome != .failed {
      try store.writeLastList(diff.currentList)
    }
    return .fetched(fetch)
  }
}
