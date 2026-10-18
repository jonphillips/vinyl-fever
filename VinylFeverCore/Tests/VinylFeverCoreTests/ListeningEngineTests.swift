import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import VinylFeverListening

@Suite("Listening engine")
struct ListeningEngineTests {
  private let poller = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private let secondPoller = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
  private var t0: Date { date("2026-10-17T10:00:00Z") }

  @Test("JSONL codec round-trips records, ignores a trailing partial line, and rejects newer versions")
  func codec() throws {
    let fetch = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: date("2026-10-17T11:00:00.125Z"),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [item("one")])
    let encoded = try ListeningLogCodec.encode(fetch)
    #expect(try ListeningLogCodec.decodeJSONL(encoded) == [fetch])
    let readLog = try ListeningLog(jsonlStreams: [encoded], now: fetch.fetchedAt)
    #expect(readLog.coverage.firstFetchAt == fetch.fetchedAt)
    #expect(readLog.plays.count == 1)
    let heartbeat = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0, outcome: .none, pagesRead: 1)
    let heartbeatData = try ListeningLogCodec.encode(heartbeat)
    #expect(!String(decoding: heartbeatData, as: UTF8.self).contains("\"items\""))
    #expect(try ListeningLogCodec.decodeJSONL(heartbeatData).first?.items.isEmpty == true)
    let partial = Data(#"{"format":"vf-listening-fetch","version":1"#.utf8)
    #expect(try ListeningLogCodec.decodeJSONL(encoded + partial) == [fetch])

    let future = Data(#"{"format":"vf-listening-fetch","version":2}"#.utf8)
    do {
      _ = try ListeningLogCodec.decodeJSONL(future + Data("\n".utf8))
      Issue.record("Expected newer-version error")
    } catch let error as ListeningLogCodecError {
      #expect(error == .newerVersion(2))
    }
  }

  @Test("diff recognizes front additions, moved replays, and unchanged feeds")
  func simpleDiffs() throws {
    let a = item("a")
    let b = item("b")
    let c = item("c")
    #expect(ListeningDiff.resolve(previous: [a, b], current: [item("x"), a, b], reachedEnd: true)
      == .match(newCount: 1, evidence: [a, b]))
    #expect(ListeningDiff.resolve(previous: [a, b, c], current: [c, a, b], reachedEnd: true)
      == .match(newCount: 1, evidence: [a, b]))
    #expect(ListeningDiff.resolve(previous: [a, b], current: [a, b], reachedEnd: true)
      == .match(newCount: 0, evidence: [a, b]))
  }

  @Test("paged diff crosses more than thirty new plays and requests overlap evidence")
  func pagedDiff() async throws {
    let old = (0..<40).map { item("old-\($0)") }
    let new = (0..<65).map { item("new-\($0)") }
    let pages = CannedPages([
      0: Array(new[0..<30]),
      30: Array(new[30..<60]),
      60: Array(new[60..<65] + old[0..<25]),
    ])
    let result = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: old)
    }
    #expect(result.outcome == .plays)
    #expect(result.newCount == 65)
    #expect(result.pagesRead == 4)
    #expect(result.items.count == 75)
    #expect(result.currentList.count == 90)
    #expect(result.items.suffix(10).map(\.id) == old.prefix(10).map(\.id))
    #expect(await pages.offsets == [0, 30, 60, 90])
  }

  @Test("baseline, empty feed, distinct catalog and library identities, and page-cap gap")
  func baselineEmptyKindsAndGap() async throws {
    let baselinePages = CannedPages([0: [item("one")]])
    let baseline = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in await baselinePages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: nil)
    }
    #expect(baseline.outcome == .baseline)
    #expect(baseline.newCount == 0)

    let empty = try await withDependencies {
      $0.recentlyPlayedClient.page = { _ in [] }
    } operation: {
      try await ListeningDiff().fetch(previous: nil)
    }
    #expect(empty.outcome == .baseline)
    #expect(empty.currentList.isEmpty)

    let catalog = item("same", kind: .song)
    let library = item("same", kind: .librarySong)
    let distinct = ListeningDiff.resolve(
      previous: [catalog], current: [library, catalog], reachedEnd: true)
    #expect(distinct == .match(newCount: 1, evidence: [catalog]))

    let pages = CannedPages(Dictionary(uniqueKeysWithValues: (0..<10).map { index in
      (index * ListeningDiff.pageSize, (0..<ListeningDiff.pageSize).map { item("unrelated-\(index)-\($0)") })
    }))
    let gap = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: [item("missing")])
    }
    #expect(gap.outcome == .gap)
    #expect(gap.pagesRead == ListeningDiff.pageCap)
    #expect(gap.newCount == ListeningDiff.pageCap * ListeningDiff.pageSize)
  }

  @Test("log windows use the last successful fetch and surface failed and gap lines")
  func logWindowsAndCoverage() {
    let failed = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(60),
      outcome: .failed, pagesRead: 0, error: "network")
    let plays = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(120),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [item("one")])
    let gap = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(180),
      outcome: .gap, newCount: 1, pagesRead: 10, items: [item("two")])
    let log = ListeningLog(streams: [[
      ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0, outcome: .baseline, pagesRead: 1),
      failed, plays, gap,
    ]], now: t0.addingTimeInterval(240))
    #expect(log.plays.first(where: { $0.item.id == "one" })?.windowStart == t0)
    #expect(log.plays.first(where: { $0.item.id == "two" })?.windowStart == t0.addingTimeInterval(120))
    #expect(log.coverage.gaps.map(\.outcome) == [.failed, .gap])
    #expect(log.coverage.lastFetchAge == 60)
  }

  @Test("overlapping poller streams collapse duplicate plays and period queries sort and cap")
  func overlappingStreamsAndQueries() {
    let baselineOne = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0, outcome: .baseline, pagesRead: 1)
    let baselineTwo = ListeningFetch(poller: secondPoller, host: "Laptop", fetchedAt: t0, outcome: .baseline, pagesRead: 1)
    let repeated = item("repeat", title: "Starry Eyes (2005 Remaster)", artist: "The Records")
    let other = item("other", title: "Blue Song", artist: "Beyonce")
    let firstPlay = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(300),
      outcome: .plays, newCount: 2, pagesRead: 1, items: [repeated, other])
    let duplicatePlay = ListeningFetch(
      poller: secondPoller, host: "Laptop", fetchedAt: t0.addingTimeInterval(360),
      outcome: .plays, newCount: 1, pagesRead: 1,
      items: [item("library-repeat", kind: .librarySong, title: "Starry Eyes", artist: "The Records")])
    let repeatedAgain = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(600),
      outcome: .plays, newCount: 2, pagesRead: 1,
      items: [item("repeat", title: "Starry Eyes", artist: "The Records"),
        item("other", title: "Blue Song", artist: "Beyoncé")])
    let late = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(40 * 24 * 60 * 60),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [item("late", title: "New", artist: "New Artist")])
    let log = ListeningLog(
      streams: [[baselineOne, firstPlay, repeatedAgain, late], [baselineTwo, duplicatePlay]],
      now: late.fetchedAt)
    #expect(log.coverage.collapsedOverlappingPlays == 1)
    #expect(log.recentPlays(period: .month, now: late.fetchedAt, limit: 1).map { $0.item.id } == ["late"])
    let topTracks = log.topTracks(period: .quarter, now: late.fetchedAt)
    #expect(topTracks.map(\.plays) == [2, 2, 1])
    #expect(topTracks.prefix(2).map(\.artist) == ["Beyoncé", "The Records"])
    let topArtists = log.topArtists(period: .quarter, now: late.fetchedAt, limit: 2)
    #expect(topArtists.map(\.plays) == [2, 2])
    #expect(ListeningQueryLimit.cap(999) == ListeningQueryLimit.maximum)
    #expect(ListeningTextNormalizer.title("Starry Eyes (2005 Remaster)") == "starry eyes")
    #expect(ListeningTextNormalizer.artist("Beyoncé") == ListeningTextNormalizer.artist("Beyonce"))
  }

  @Test("a non-holder cannot write and only an absent lease may be claimed")
  func leaseRules() {
    let lease = ListeningLease(poller: poller, host: "Mini", takenAt: t0)
    #expect(ListeningLeaseRules.decision(current: nil, poller: secondPoller) == .claimIfEmpty)
    #expect(ListeningLeaseRules.decision(current: lease, poller: poller) == .write)
    #expect(ListeningLeaseRules.decision(current: lease, poller: secondPoller) == .skip)
  }

  private func item(
    _ id: String, kind: ListeningItem.Kind = .song, title: String? = nil, artist: String = "Artist"
  ) -> ListeningItem {
    ListeningItem(kind: kind, id: id, title: title ?? id, artist: artist)
  }

  private func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)!
  }
}

private actor CannedPages {
  private let pages: [Int: [ListeningItem]]
  private(set) var offsets: [Int] = []

  init(_ pages: [Int: [ListeningItem]]) {
    self.pages = pages
  }

  func page(_ offset: Int) -> [ListeningItem] {
    offsets.append(offset)
    return pages[offset] ?? []
  }
}
