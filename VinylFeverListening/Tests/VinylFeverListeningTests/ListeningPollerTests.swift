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

  @Test("taking over and handing back recovers each holder's handover window")
  func takeoverAndHandbackRecovery() async throws {
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
    #expect(fetch(laptopBaseline)?.outcome == ListeningFetch.Outcome.none)
    #expect(fetch(laptopBaseline)?.since?.fetchedAt == fetch(miniPlay)?.fetchedAt)
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
    #expect(fetch(miniHandback)?.outcome == .plays)
    #expect(fetch(miniHandback)?.newCount == 1)
    let fetches = try mini.readFetches()
    let streams = Dictionary(grouping: fetches, by: \.poller).values.map { $0 }
    #expect(ListeningLog(streams: streams, now: t0.addingTimeInterval(480)).coverage.collapsedOverlappingPlays == 0)
  }

  @Test("takeover recovers plays from the old stream's item head and consumes the marker once")
  func takeoverRecoversHandoverPlays() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let mini = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("mini", isDirectory: true), hostName: { "Mini" })
    let laptop = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("laptop", isDirectory: true), hostName: { "Laptop" })
    let oldPoller = try mini.pollerID()
    let newPoller = try laptop.pollerID()
    let baseline = (0..<173).map { item("song-\($0)") }
    let t0 = date("2026-10-22T14:00:00Z")

    _ = try await poll(store: mini, now: t0) { offset in
      let page = Array(baseline.dropFirst(offset).prefix(ListeningDiff.pageSize))
      return RecentlyPlayedPage(items: page, hasNext: offset + page.count < baseline.count)
    }

    let oldHeadPlay = item("old-head-play")
    let oldPlays = [oldHeadPlay] + Array(baseline.prefix(10))
    _ = try await poll(store: mini, now: t0.addingTimeInterval(3_600)) { _ in
      RecentlyPlayedPage(items: oldPlays, hasNext: false)
    }
    let oldPlaysFetch = try #require(try mini.readFetches().last(where: { $0.outcome == .plays }))
    #expect(oldPlaysFetch.items.count == 11)

    // The newest old-stream heartbeat has no items; recovery walks back to the item-bearing line.
    try mini.appendFetch(ListeningFetch(
      poller: oldPoller, host: "Mini", fetchedAt: t0.addingTimeInterval(5_400),
      outcome: .none, pagesRead: 1))
    try ListeningLeaseRules.takeOver(
      store: laptop, poller: newPoller, host: "Laptop", now: t0.addingTimeInterval(5_500))

    let replays = (50..<62).map { baseline[$0] }
    let newPrefix = (0..<7).map { item("new-\($0)") } + replays
    let current = newPrefix + oldPlays + Array(baseline.dropFirst(10).prefix(143))
    #expect(current.count == 173)
    let handover = try await poll(store: laptop, now: t0.addingTimeInterval(5_600)) { offset in
      let page = Array(current.dropFirst(offset).prefix(ListeningDiff.pageSize))
      return RecentlyPlayedPage(items: page, hasNext: offset + page.count < current.count)
    }

    guard case let .fetched(fetch) = handover else { Issue.record("Expected handover fetch"); return }
    #expect(fetch.outcome == .plays)
    #expect(fetch.newCount == 19)
    #expect(fetch.since == ListeningSince(poller: oldPoller, fetchedAt: oldPlaysFetch.fetchedAt))
    #expect(fetch.version == 2)
    #expect(try laptop.readHandoverMarker() == nil)
    #expect(try laptop.readLastList() == Array(current.prefix(30)))
  }

  @Test("missing old stream writes a baseline with a visible handover gap")
  func missingOldStreamIsLoud() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let laptop = ListeningStore.live(iCloudFolder: folders.cloud, localFolder: folders.local)
    let oldPoller = UUID()
    let poller = try laptop.pollerID()
    let takenAt = date("2026-10-22T10:00:00Z")
    try laptop.writeLease(ListeningLease(poller: oldPoller, host: "Mini", takenAt: takenAt))
    try ListeningLeaseRules.takeOver(
      store: laptop, poller: poller, host: "Laptop", now: takenAt.addingTimeInterval(1))

    let result = try await poll(store: laptop, now: takenAt.addingTimeInterval(60)) { _ in
      RecentlyPlayedPage(items: [item("one")], hasNext: false)
    }
    guard case let .fetched(fetch) = result else { Issue.record("Expected baseline"); return }
    #expect(fetch.outcome == .baseline)
    #expect(fetch.since == ListeningSince(poller: oldPoller, fetchedAt: takenAt))
    #expect(try laptop.readHandoverMarker() == nil)
    let log = ListeningLog(streams: [[fetch]], now: fetch.fetchedAt)
    #expect(log.coverage.gaps.count == 1)
    #expect(log.coverage.gaps.first?.windowStart == takenAt)
  }

  @Test("an old baseline equal to the new feed becomes none with a since window")
  func matchingOldBaselineIsNone() async throws {
    let folders = try TemporaryListeningFolders()
    defer { folders.remove() }
    let mini = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("mini", isDirectory: true), hostName: { "Mini" })
    let laptop = ListeningStore.live(
      iCloudFolder: folders.cloud,
      localFolder: folders.root.appendingPathComponent("laptop", isDirectory: true), hostName: { "Laptop" })
    let oldPoller = try mini.pollerID()
    let poller = try laptop.pollerID()
    let list = [item("a"), item("b"), item("c")]
    let now = date("2026-10-22T10:00:00Z")
    let baseline = try await poll(store: mini, now: now) { _ in
      RecentlyPlayedPage(items: list, hasNext: false)
    }
    let oldFetch = try #require(fetch(baseline))
    try ListeningLeaseRules.takeOver(
      store: laptop, poller: poller, host: "Laptop", now: now.addingTimeInterval(60))

    let result = try await poll(store: laptop, now: now.addingTimeInterval(120)) { _ in
      RecentlyPlayedPage(items: list, hasNext: false)
    }
    let recovered = try #require(fetch(result))
    #expect(recovered.outcome == ListeningFetch.Outcome.none)
    #expect(recovered.since == ListeningSince(poller: oldPoller, fetchedAt: oldFetch.fetchedAt))
  }

  @Test("shared takeover kickstarts after writing the lease and skips registration when enabled")
  func takeoverKickstartsAfterLeaseWrite() throws {
    let previous = ListeningLease(poller: UUID(), host: "Mini", takenAt: Date())
    let poller = UUID()
    let state = ListeningTakeoverFixture(lease: previous)
    let store = state.store(poller: poller)
    var registered = false

    try ListeningTakeover.perform(
      store: store, poller: poller, host: "Laptop", now: Date(),
      isAgentEnabled: { true }, register: { registered = true },
      kickstart: {
        #expect(state.lease?.poller == poller)
        #expect(state.marker != nil)
        state.events.append("kickstart")
      })

    #expect(!registered)
    #expect(state.events == ["marker", "lease", "clear-list", "kickstart"])
  }

  @Test("shared takeover restores the lease and clears the marker when registration fails")
  func takeoverRegistrationFailureRollsBack() throws {
    let previous = ListeningLease(poller: UUID(), host: "Mini", takenAt: Date())
    let poller = UUID()
    let state = ListeningTakeoverFixture(lease: previous)
    let store = state.store(poller: poller)

    #expect(throws: ListeningTakeoverFixtureError.registration) {
      try ListeningTakeover.perform(
        store: store, poller: poller, host: "Laptop", now: Date(),
        isAgentEnabled: { false }, register: { throw ListeningTakeoverFixtureError.registration },
        kickstart: { Issue.record("A failed registration must not kickstart") })
    }
    #expect(state.lease == previous)
    #expect(state.marker == nil)
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

private final class ListeningTakeoverFixture: @unchecked Sendable {
  var lease: ListeningLease?
  var marker: ListeningHandoverMarker?
  var lastList: [ListeningItem]? = [ListeningItem(kind: .song, id: "old", title: "Old", artist: "Artist")]
  var events: [String] = []

  init(lease: ListeningLease?) {
    self.lease = lease
  }

  func store(poller: UUID) -> ListeningStore {
    ListeningStore(
      pollerID: { poller }, readLease: { self.lease },
      writeLease: { self.lease = $0; self.events.append("lease") },
      readLastList: { self.lastList }, writeLastList: { self.lastList = $0 },
      clearLastList: { self.lastList = nil; self.events.append("clear-list") },
      readHandoverMarker: { self.marker },
      writeHandoverMarker: { self.marker = $0; self.events.append("marker") },
      clearHandoverMarker: { self.marker = nil },
      appendFetch: { _ in },
      listeningFolder: { URL(fileURLWithPath: "/tmp/Listening") })
  }
}

private enum ListeningTakeoverFixtureError: Error, Equatable {
  case registration
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
