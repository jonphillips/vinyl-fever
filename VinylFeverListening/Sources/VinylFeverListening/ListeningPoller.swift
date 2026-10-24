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
  public var clearLastList: @Sendable () throws -> Void
  public var readHandoverMarker: @Sendable () throws -> ListeningHandoverMarker?
  public var writeHandoverMarker: @Sendable (ListeningHandoverMarker) throws -> Void
  public var clearHandoverMarker: @Sendable () throws -> Void
  public var readRecentFetches: @Sendable (Date) throws -> [ListeningFetch]
  public var appendFetch: @Sendable (ListeningFetch) throws -> Void
  public var readFetches: @Sendable () throws -> [ListeningFetch]
  public var readLastPollError: @Sendable () throws -> String?
  public var writeLastPollError: @Sendable (String?) throws -> Void
  public var listeningFolder: @Sendable () -> URL
  public var hostName: @Sendable () -> String
  public var readNewMusicExposure: @Sendable () throws -> [NewMusicExposureRecord]
  public var appendNewMusicWeek: @Sendable (NewMusicWeek) throws -> Void
  public var appendNewMusicGap: @Sendable (NewMusicExposureGap) throws -> Void
  public var readNewMusicAttemptAt: @Sendable () throws -> Date?
  public var writeNewMusicAttemptAt: @Sendable (Date) throws -> Void

  public init(
    pollerID: @escaping @Sendable () throws -> UUID,
    readLease: @escaping @Sendable () throws -> ListeningLease?,
    writeLease: @escaping @Sendable (ListeningLease) throws -> Void,
    readLastList: @escaping @Sendable () throws -> [ListeningItem]?,
    writeLastList: @escaping @Sendable ([ListeningItem]) throws -> Void,
    clearLastList: @escaping @Sendable () throws -> Void = {},
    readHandoverMarker: @escaping @Sendable () throws -> ListeningHandoverMarker? = { nil },
    writeHandoverMarker: @escaping @Sendable (ListeningHandoverMarker) throws -> Void = { _ in },
    clearHandoverMarker: @escaping @Sendable () throws -> Void = {},
    readRecentFetches: @escaping @Sendable (Date) throws -> [ListeningFetch] = { _ in [] },
    appendFetch: @escaping @Sendable (ListeningFetch) throws -> Void,
    readFetches: @escaping @Sendable () throws -> [ListeningFetch] = { [] },
    readLastPollError: @escaping @Sendable () throws -> String? = { nil },
    writeLastPollError: @escaping @Sendable (String?) throws -> Void = { _ in },
    listeningFolder: @escaping @Sendable () -> URL,
    readNewMusicExposure: @escaping @Sendable () throws -> [NewMusicExposureRecord] = { [] },
    appendNewMusicWeek: @escaping @Sendable (NewMusicWeek) throws -> Void = { _ in },
    appendNewMusicGap: @escaping @Sendable (NewMusicExposureGap) throws -> Void = { _ in },
    readNewMusicAttemptAt: @escaping @Sendable () throws -> Date? = { nil },
    writeNewMusicAttemptAt: @escaping @Sendable (Date) throws -> Void = { _ in },
    hostName: @escaping @Sendable () -> String = { "Mac" }
  ) {
    self.pollerID = pollerID
    self.readLease = readLease
    self.writeLease = writeLease
    self.readLastList = readLastList
    self.writeLastList = writeLastList
    self.clearLastList = clearLastList
    self.readHandoverMarker = readHandoverMarker
    self.writeHandoverMarker = writeHandoverMarker
    self.clearHandoverMarker = clearHandoverMarker
    self.readRecentFetches = readRecentFetches
    self.appendFetch = appendFetch
    self.readFetches = readFetches
    self.readLastPollError = readLastPollError
    self.writeLastPollError = writeLastPollError
    self.listeningFolder = listeningFolder
    self.hostName = hostName
    self.readNewMusicExposure = readNewMusicExposure
    self.appendNewMusicWeek = appendNewMusicWeek
    self.appendNewMusicGap = appendNewMusicGap
    self.readNewMusicAttemptAt = readNewMusicAttemptAt
    self.writeNewMusicAttemptAt = writeNewMusicAttemptAt
  }
}

extension ListeningStore: TestDependencyKey, DependencyKey {
  public static var testValue: Self {
    Self(
      pollerID: { UUID() }, readLease: { nil }, writeLease: { _ in },
      readLastList: { nil }, writeLastList: { _ in }, clearLastList: {},
      readHandoverMarker: { nil }, writeHandoverMarker: { _ in }, clearHandoverMarker: {},
      readRecentFetches: { _ in [] },
      appendFetch: { _ in }, readFetches: { [] },
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
  @Dependency(\.newMusicCatalogClient) private var newMusic
  @Dependency(\.date) private var date

  public init() {}

  public func pollOnce() async throws -> ListeningPollResult {
    do {
      let result = try await performPollOnce()
      try store.writeLastPollError(nil)
      return result
    } catch {
      try? store.writeLastPollError(ListeningErrorDescription.describe(error))
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

    let marker = try store.readHandoverMarker()
    let previous: [ListeningItem]?
    let since: ListeningSince?
    if let marker {
      let fetches = (try? store.readRecentFetches(now)) ?? []
      let resolution = Self.resolveHandover(fetches)
      previous = resolution.items
      since = resolution.since ?? ListeningSince(
        poller: marker.previousPoller, fetchedAt: marker.fallbackSince)
    } else {
      previous = try store.readLastList()
      since = nil
    }
    let diff: ListeningDiffResult
    do {
      diff = try await withDependencies({ $0.recentlyPlayedClient = recentlyPlayed }) {
        try await ListeningDiff().fetch(previous: previous)
      }
    } catch {
      let failed = ListeningFetch(
        poller: poller, host: host, fetchedAt: now, outcome: .failed,
        pagesRead: 0, error: ListeningErrorDescription.describe(error)
      )
      try store.appendFetch(failed)
      return .fetched(failed)
    }

    let fetch = ListeningFetch(
      poller: poller, host: host, fetchedAt: now, outcome: diff.outcome,
      newCount: diff.newCount, pagesRead: diff.pagesRead, items: diff.items,
      since: diff.outcome == .failed ? nil : since,
      error: diff.error
    )
    try store.appendFetch(fetch)
    if fetch.outcome != .failed {
      try store.writeLastList(diff.currentList)
      if marker != nil { try store.clearHandoverMarker() }
      await recordNewMusicExposure(at: now, host: host)
    }
    return .fetched(fetch)
  }

  private func recordNewMusicExposure(at now: Date, host: String) async {
    let latestAttempt: Date?
    do { latestAttempt = try store.readNewMusicAttemptAt() }
    catch { return }
    if let latestAttempt, now.timeIntervalSince(latestAttempt) < 6 * 60 * 60 { return }
    let existing: [NewMusicExposureRecord]
    do { existing = try store.readNewMusicExposure() }
    catch {
      try? store.writeNewMusicAttemptAt(now)
      try? store.appendNewMusicGap(NewMusicExposureGap(
        fetchedAt: now, host: host,
        detail: "The existing New Music exposure log could not be read: \(ListeningErrorDescription.describe(error))"))
      return
    }
    do { try store.writeNewMusicAttemptAt(now) }
    catch {
      try? store.appendNewMusicGap(NewMusicExposureGap(
        fetchedAt: now, host: host, detail: "The New Music exposure throttle could not be saved."))
      return
    }
    do {
      let week = try await newMusic.fetch()
      guard !existing.contains(where: { $0.lastModifiedDate == week.lastModifiedDate }) else { return }
      try store.appendNewMusicWeek(NewMusicWeek(
        lastModifiedDate: week.lastModifiedDate, fetchedAt: now, host: host, tracks: week.tracks))
    } catch {
      try? store.appendNewMusicGap(NewMusicExposureGap(
        fetchedAt: now, host: host, detail: ListeningErrorDescription.describe(error)))
    }
  }

  private static func resolveHandover(
    _ fetches: [ListeningFetch]
  ) -> (items: [ListeningItem]?, since: ListeningSince?) {
    let successful = fetches.filter { $0.outcome != .failed }
    guard let latest = successful.max(by: { $0.fetchedAt < $1.fetchedAt }) else {
      return (nil, nil)
    }
    let since = ListeningSince(poller: latest.poller, fetchedAt: latest.fetchedAt)
    let streams = Dictionary(grouping: fetches, by: \.poller).mapValues {
      $0.sorted { $0.fetchedAt < $1.fetchedAt }
    }
    var current: ListeningFetch? = latest
    var hops = 0

    while let fetch = current {
      if [.baseline, .plays, .gap].contains(fetch.outcome), !fetch.items.isEmpty {
        return (fetch.items, since)
      }

      if let target = fetch.since {
        guard hops < 4 else { return (nil, since) }
        hops += 1
        current = streams[target.poller]?.first { $0.fetchedAt == target.fetchedAt }
      } else {
        current = streams[fetch.poller]?.last { $0.fetchedAt < fetch.fetchedAt }
      }
    }
    return (nil, since)
  }
}
