import Dependencies
import Foundation
import Testing
import VinylFeverListening

@Suite("Listening poller")
struct ListeningPollerTests {
  @Test("first run claims the lease, writes a baseline, and uses the UTC month")
  func baselineAndUTCMonth() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let store = ListeningStore.live(
      iCloudFolder: folders.cloud, localFolder: folders.local, hostName: { "Test mini" })
    let now = date("2026-11-01T04:30:00Z") // 2026-10-31 23:30 at UTC-05:00.
    let expected = [item("one")]

    let result = try await poll(store: store, now: now) { _ in
      RecentlyPlayedPage(items: expected, hasNext: false)
    }

    guard case let .fetched(fetch) = result else { Issue.record("Expected a fetch"); return }
    #expect(fetch.outcome == .baseline)
    #expect(try store.readLease()?.poller == store.pollerID())
    #expect(try store.readLastList() == expected)
    let monthURL = folders.cloud
      .appendingPathComponent("fetches/\(fetch.poller.uuidString)/2026-11.jsonl")
    #expect(FileManager.default.fileExists(atPath: monthURL.path))
    #expect(try ListeningLogCodec.decodeJSONL(Data(contentsOf: monthURL)) == [fetch])
  }

  @Test("later run appends exactly one fetch and replaces the saved list")
  func laterRunUpdatesState() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let store = ListeningStore.live(iCloudFolder: folders.cloud, localFolder: folders.local)
    let now = date("2026-10-18T12:00:00Z")
    let first = item("one")
    _ = try await poll(store: store, now: now) { _ in
      RecentlyPlayedPage(items: [first], hasNext: false)
    }

    let second = item("two")
    let result = try await poll(store: store, now: now.addingTimeInterval(3_600)) { offset in
      #expect(offset == 0)
      return RecentlyPlayedPage(items: [second, first], hasNext: false)
    }

    guard case let .fetched(fetch) = result else { Issue.record("Expected a fetch"); return }
    #expect(fetch.outcome == .plays)
    #expect(fetch.newCount == 1)
    #expect(try store.readLastList() == [second, first])
    #expect(try store.readFetches().count == 2)
  }

  @Test("non-leaseholder writes nothing to iCloud")
  func skipsNonLeaseholder() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let store = ListeningStore.live(iCloudFolder: folders.cloud, localFolder: folders.local)
    let owner = try store.pollerID()
    try store.writeLease(ListeningLease(poller: UUID(), host: "Other Mac", takenAt: Date()))
    let result = try await poll(store: store, now: Date()) { _ in
      RecentlyPlayedPage(items: [item("one")], hasNext: false)
    }

    #expect(result == .skipped)
    #expect(try store.readLease()?.poller != owner)
    #expect(try store.readFetches().isEmpty)
  }

  @Test("taking over and handing back starts a baseline for each holder")
  func takeoverAndHandbackBaseline() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let mini = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("mini", isDirectory: true),
      hostName: { "Mini" })
    let laptop = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("laptop", isDirectory: true),
      hostName: { "Laptop" })
    let miniPoller = try mini.pollerID()
    let laptopPoller = try laptop.pollerID()
    let a = item("a")
    let b = item("b")
    let c = item("c")
    let d = item("d")
    let e = item("e")
    let t0 = date("2026-10-21T10:00:00Z")

    let initial = try await poll(store: mini, now: t0) { _ in
      RecentlyPlayedPage(items: [a, b], hasNext: false)
    }
    #expect(fetch(initial)?.outcome == .baseline)
    let miniPlay = try await poll(store: mini, now: t0.addingTimeInterval(60)) { _ in
      RecentlyPlayedPage(items: [c, a, b], hasNext: false)
    }
    #expect(fetch(miniPlay)?.outcome == .plays)

    try ListeningLeaseRules.takeOver(
      store: laptop, poller: laptopPoller, host: "Laptop", now: t0.addingTimeInterval(120))
    let miniCountBeforeSkip = try mini.readFetches().count
    #expect(try await poll(store: mini, now: t0.addingTimeInterval(180)) { _ in
      Issue.record("The former holder must not request a page")
      return RecentlyPlayedPage(items: [], hasNext: false)
    } == .skipped)
    #expect(try mini.readFetches().count == miniCountBeforeSkip)

    let laptopBaseline = try await poll(store: laptop, now: t0.addingTimeInterval(240)) { _ in
      RecentlyPlayedPage(items: [c, a, b], hasNext: false)
    }
    #expect(fetch(laptopBaseline)?.outcome == .baseline)
    let laptopPlay = try await poll(store: laptop, now: t0.addingTimeInterval(300)) { _ in
      RecentlyPlayedPage(items: [d, c, a, b], hasNext: false)
    }
    #expect(fetch(laptopPlay)?.outcome == .plays)

    try ListeningLeaseRules.takeOver(
      store: mini, poller: miniPoller, host: "Mini", now: t0.addingTimeInterval(360))
    let laptopCountBeforeSkip = try laptop.readFetches().count
    #expect(try await poll(store: laptop, now: t0.addingTimeInterval(420)) { _ in
      Issue.record("The former holder must not request a page")
      return RecentlyPlayedPage(items: [], hasNext: false)
    } == .skipped)
    #expect(try laptop.readFetches().count == laptopCountBeforeSkip)

    let miniHandback = try await poll(store: mini, now: t0.addingTimeInterval(480)) { _ in
      RecentlyPlayedPage(items: [e, d, c, a, b], hasNext: false)
    }
    #expect(fetch(miniHandback)?.outcome == .baseline)
    let fetches = try mini.readFetches()
    let streams = Dictionary(grouping: fetches, by: \.poller).values.map { $0 }
    #expect(ListeningLog(streams: streams, now: t0.addingTimeInterval(480)).coverage.collapsedOverlappingPlays == 0)
  }

  @Test("unauthorized and failed fetches are logged without replacing last-list")
  func failedFetchesPreservePreviousList() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let store = ListeningStore.live(iCloudFolder: folders.cloud, localFolder: folders.local)
    let previous = [item("saved")]
    _ = try await poll(store: store, now: date("2026-10-18T10:00:00Z")) { _ in
      RecentlyPlayedPage(items: previous, hasNext: false)
    }

    let unauthorized = try await poll(
      store: store, now: date("2026-10-18T11:00:00Z"), authorization: .denied
    ) { _ in Issue.record("Unauthorized polling must not request a page"); return .init(items: [], hasNext: false) }
    #expect(fetch(unauthorized)?.outcome == .failed)
    #expect(try store.readLastList() == previous)

    let thrown = try await poll(store: store, now: date("2026-10-18T12:00:00Z")) { _ in
      throw PollerFixtureError.network
    }
    #expect(fetch(thrown)?.outcome == .failed)
    #expect(try store.readLastList() == previous)

    let empty = try await poll(store: store, now: date("2026-10-18T13:00:00Z")) { _ in
      RecentlyPlayedPage(items: [], hasNext: false)
    }
    #expect(fetch(empty)?.outcome == .failed)
    #expect(try store.readLastList() == previous)
    #expect(try store.readFetches().filter { $0.outcome == .failed }.count == 3)
  }

  private func poll(
    store: ListeningStore,
    now: Date,
    authorization: ListeningAuthorizationStatus = .authorized,
    page: @escaping @Sendable (Int) async throws -> RecentlyPlayedPage
  ) async throws -> ListeningPollResult {
    try await withDependencies {
      $0.listeningStore = store
      $0.listeningAuthorizationClient = ListeningAuthorizationClient(status: { authorization })
      $0.recentlyPlayedClient.page = page
      $0.date = .constant(now)
    } operation: {
      try await ListeningPoller().pollOnce()
    }
  }

  private func fetch(_ result: ListeningPollResult) -> ListeningFetch? {
    guard case let .fetched(value) = result else { return nil }
    return value
  }

  private func item(_ id: String) -> ListeningItem {
    ListeningItem(kind: .song, id: id, title: id, artist: "Artist")
  }

  private func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value)!
  }
}

private struct TemporaryListeningFolders {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var cloud: URL { root.appendingPathComponent("iCloud", isDirectory: true) }
  var local: URL { root.appendingPathComponent("local", isDirectory: true) }

  init() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum PollerFixtureError: Error {
  case network
}
