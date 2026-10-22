import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
@testable import VinylFeverListening

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
      0: .init(items: Array(new[0..<30]), hasNext: true),
      30: .init(items: Array(new[30..<60]), hasNext: true),
      60: .init(items: Array(new[60..<65] + old[0..<25]), hasNext: false),
    ])
    let result = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: old)
    }
    #expect(result.outcome == .plays)
    #expect(result.newCount == 65)
    #expect(result.pagesRead == 3)
    #expect(result.items.count == 75)
    #expect(result.currentList.count == 90)
    #expect(result.items.suffix(10).map(\.id) == old.prefix(10).map(\.id))
    #expect(await pages.offsets == [0, 30, 60])
  }

  @Test("the diff stops fetching immediately after overlap resolves")
  func stopsReadingOnceOverlapResolves() async throws {
    let old = (0..<30).map { item("old-\($0)") }
    let pages = CannedPages(
      [0: .init(items: [item("new"), .init(kind: .song, id: old[0].id, title: old[0].title, artist: old[0].artist)] + old.dropFirst().prefix(9), hasNext: true)],
      failingOffset: 30)
    let result = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: old)
    }
    #expect(result.outcome == .plays)
    #expect(result.newCount == 1)
    #expect(result.pagesRead == 1)
    #expect(await pages.offsets == [0])
  }

  @Test("a short page with a next link continues reading for overlap")
  func shortPageWithNextKeepsReading() async throws {
    let old = (0..<30).map { item("old-\($0)") }
    let pages = CannedPages([
      0: .init(items: (0..<28).map { item("new-\($0)") }, hasNext: true),
      30: .init(items: Array(old.prefix(10)), hasNext: false),
    ])
    let result = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: old)
    }
    #expect(result.outcome == .plays)
    #expect(result.newCount == 28)
    #expect(result.pagesRead == 2)
    #expect(await pages.offsets == [0, 30])
  }

  @Test("a live request specifies both resource types, the maximum limit, and offset")
  func liveRequestAsksForTypesLimitAndOffset() throws {
    let request = try RecentlyPlayedClient.request(offset: 60)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = try #require(components.queryItems)
    #expect(components.path == "/v1/me/recent/played/tracks")
    #expect(queryItems.map(\.name) == ["types", "limit", "offset"])
    #expect(queryItems.map(\.value) == ["songs,library-songs", String(ListeningDiff.pageSize), "60"])
  }

  @Test("HTTP errors include Apple's title and detail when available")
  func httpErrorIncludesAppleDetail() {
    let response = Data(
      #"{"errors":[{"status":"401","code":"40100","title":"Unauthorized","detail":"A valid Apple Music user token is required."}]}"#.utf8
    )
    let error = RecentlyPlayedClient.httpError(status: 401, body: response)
    #expect(
      error.errorDescription ==
        "Apple Music returned HTTP 401 (Unauthorized: A valid Apple Music user token is required.)."
    )

    let invalidResponse = RecentlyPlayedClient.httpError(status: 401, body: Data("not JSON".utf8))
    #expect(invalidResponse.errorDescription == "Apple Music returned HTTP 401.")
  }

  @Test("baseline, empty feed, distinct catalog and library identities, and page-cap gap")
  func baselineEmptyKindsAndGap() async throws {
    let baselinePages = CannedPages([0: .init(items: [item("one")], hasNext: false)])
    let baseline = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await baselinePages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: nil)
    }
    #expect(baseline.outcome == .baseline)
    #expect(baseline.newCount == 0)

    let empty = try await withDependencies {
      $0.recentlyPlayedClient.page = { _ in .init(items: [], hasNext: false) }
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
      (index * ListeningDiff.pageSize, .init(
        items: (0..<ListeningDiff.pageSize).map { item("unrelated-\(index)-\($0)") },
        hasNext: index < 9))
    }))
    let gap = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await pages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: [item("missing")])
    }
    #expect(gap.outcome == .gap)
    #expect(gap.pagesRead == ListeningDiff.pageCap)
    #expect(gap.newCount == ListeningDiff.pageCap * ListeningDiff.pageSize)
  }

  @Test("empty feed after a baseline fails and preserves the previous list for recovery")
  func emptyFeedAfterListIsFailedAndKeepsPreviousList() async throws {
    let previous = (0..<30).map { item("old-\($0)") }
    let emptyPages = CannedPages([0: .init(items: [], hasNext: false)])
    let failed = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await emptyPages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: previous)
    }
    #expect(failed.outcome == .failed)
    #expect(failed.currentList == previous)
    #expect(failed.error == "Apple Music returned an empty recently-played list.")

    let recoveryPages = CannedPages([0: .init(items: previous, hasNext: false)])
    let recovered = try await withDependencies {
      $0.recentlyPlayedClient.page = { offset in try await recoveryPages.page(offset) }
    } operation: {
      try await ListeningDiff().fetch(previous: failed.currentList)
    }
    #expect(recovered.outcome == .none)
    #expect(recovered.newCount == 0)
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

  @Test("a failure before the first baseline is not a coverage gap")
  func initialFailureDoesNotStartCoverage() {
    let failed = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0, outcome: .failed, pagesRead: 0, error: "HTTP 401")
    let baseline = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(12 * 60), outcome: .baseline, pagesRead: 1)
    let plays = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(24 * 60), outcome: .plays, newCount: 1, pagesRead: 1, items: [item("one")])
    let log = ListeningLog(streams: [[failed, baseline, plays]], now: plays.fetchedAt)
    #expect(log.coverage.firstFetchAt == baseline.fetchedAt)
    #expect(log.coverage.gaps.isEmpty)
  }

  @Test("Settings status line reports setup pointer, coverage age, and only recent gaps")
  func listeningStatusLine() {
    #expect(ListeningStatusLine.make(fetches: [], now: t0) == ListeningStatusLine.setupPointer)
    let baseline = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(-70 * 86_400), outcome: .baseline, pagesRead: 1)
    let oldFailure = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(-60 * 86_400), outcome: .failed, pagesRead: 0, error: "network")
    let recentGap = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(-2 * 86_400), outcome: .gap, pagesRead: 10)
    let line = ListeningStatusLine.make(
      fetches: [baseline, oldFailure, recentGap], now: t0,
      timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US_POSIX"))
    #expect(line.contains("Polling Mac: Mini"))
    #expect(line.contains("Last fetch 2 days ago"))
    #expect(line.contains("Coverage since Aug 8 at 10:00"))
    #expect(line.contains("1 gap in 30 days"))
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

  @Test("top counts include every play even when recent plays are capped")
  func topCountsUseEveryPlayInPeriod() {
    let baseline = ListeningFetch(
      poller: poller, host: "Mini", fetchedAt: t0, outcome: .baseline, pagesRead: 1)
    let fetches = (0..<100).map { index in
      let artist = index < 60 ? "Old Fave" : "New Thing"
      let title = index < 60 ? "Old Fave Song" : "New Thing Song"
      return ListeningFetch(
        poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(Double(index + 1) * 3_600),
        outcome: .plays, newCount: 1, pagesRead: 1,
        items: [item("track-\(index)", title: title, artist: artist)])
    }
    let now = t0.addingTimeInterval(101 * 3_600)
    let log = ListeningLog(streams: [[baseline] + fetches], now: now)

    #expect(log.recentPlays(period: .week, now: now).count == ListeningQueryLimit.default)
    let topArtists = log.topArtists(period: .week, now: now)
    #expect(topArtists.map(\.artist) == ["Old Fave", "New Thing"])
    #expect(topArtists.map(\.plays) == [60, 40])
    let topTracks = log.topTracks(period: .week, now: now)
    #expect(topTracks.map(\.title) == ["Old Fave Song", "New Thing Song"])
    #expect(topTracks.map(\.plays) == [60, 40])
  }

  @Test("the normalizer fast path matches the regex rules")
  func normalizerFastPathMatchesRegexRules() {
    #expect(ListeningTextNormalizer.artist("Artist ft Guest") == "artist")
    #expect(ListeningTextNormalizer.artist("Artist FT Guest") == "artist")
    #expect(ListeningTextNormalizer.libraryTitle("Song ft Guest") == "song")
    #expect(ListeningTextNormalizer.libraryTitle("Song FT Guest") == "song")
    #expect(ListeningTextNormalizer.artist("Artist feat. Guest") == "artist")
    #expect(ListeningTextNormalizer.libraryTitle("Song featuring Guest") == "song")
    #expect(ListeningTextNormalizer.libraryTitle("Song (with Guest)") == "song")
    #expect(ListeningTextNormalizer.title("Song (2005 Remaster)") == "song")
    #expect(ListeningTextNormalizer.artist("Withered Hand") == "withered hand")
    #expect(ListeningTextNormalizer.artist("Daft Punk") == "daft punk")
  }

  @Test("artist identity groups band variants while keeping duet rows distinct")
  func artistIdentityGrouping() {
    let baseline = ListeningFetch(poller: poller, host: "Mini", fetchedAt: t0, outcome: .baseline, pagesRead: 1)
    let plays = [
      item("springsteen", title: "Thunder Road", artist: "Bruce Springsteen & The E Street Band (Live)"),
      item("springsteen-plain", title: "Born to Run", artist: "Bruce Springsteen"),
      item("duet", title: "The Boxer", artist: "Paul Simon & Sting"),
    ].enumerated().map { index, value in
      ListeningFetch(
        poller: poller, host: "Mini", fetchedAt: t0.addingTimeInterval(Double(index + 1)),
        outcome: .plays, newCount: 1, pagesRead: 1, items: [value])
    }
    let identity = ArtistIdentity(knownArtists: ["Bruce Springsteen", "Paul Simon", "Sting"])
    let log = ListeningLog(streams: [[baseline] + plays], now: plays.last!.fetchedAt, identity: identity)
    let artists = log.topArtists(period: .month, now: plays.last!.fetchedAt)
    #expect(artists.count == 2)
    #expect(artists.map(\.plays).sorted() == [1, 2])
    #expect(artists.contains(where: { $0.artist == "Paul Simon & Sting" && $0.plays == 1 }))
  }

  @Test("a year of JSONL log files loads quickly with one or two pollers")
  func yearOfLogLoadsCorrectly() throws {
    let now = date("2026-10-18T00:00:00Z")
    let singlePollerFiles = yearOfJSONLFiles(pollers: [poller])
    let singlePollerLog = try ListeningLog(jsonlStreams: singlePollerFiles, now: now)
    #expect(singlePollerLog.plays.count == 8_760 * 2)
    let twoPollerFiles = yearOfJSONLFiles(pollers: [poller, secondPoller])
    let twoPollerLog = try ListeningLog(jsonlStreams: twoPollerFiles, now: now)
    #expect(twoPollerLog.coverage.collapsedOverlappingPlays > 0)
  }

  @Test(
    "a year of JSONL log files loads quickly with one or two pollers",
    .enabled(if: ProcessInfo.processInfo.environment["VF_PERF_TESTS"] == "1"))
  func yearOfLogPerformance() throws {
    let now = date("2026-10-18T00:00:00Z")
    let clock = ContinuousClock()
    let singlePollerFiles = yearOfJSONLFiles(pollers: [poller])
    let twoPollerFiles = yearOfJSONLFiles(pollers: [poller, secondPoller])
    var singleDurations: [Double] = []
    var twoDurations: [Double] = []
    for _ in 0..<3 {
      let singleStart = clock.now
      let singlePollerLog = try ListeningLog(jsonlStreams: singlePollerFiles, now: now)
      singleDurations.append(seconds(singleStart.duration(to: clock.now)))
      #expect(singlePollerLog.plays.count == 8_760 * 2)
      let twoStart = clock.now
      let twoPollerLog = try ListeningLog(jsonlStreams: twoPollerFiles, now: now)
      twoDurations.append(seconds(twoStart.duration(to: clock.now)))
      #expect(twoPollerLog.coverage.collapsedOverlappingPlays > 0)
    }
    let singleDuration = singleDurations.min()!
    let twoDuration = twoDurations.min()!
    print("Listening JSONL load best of 3: one poller \(singleDuration)s, two pollers \(twoDuration)s")
    #expect(twoDuration < 2)
    #expect(singleDuration < 2)
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

  private func yearOfJSONLFiles(pollers: [UUID]) -> [Data] {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let start = date("2025-10-18T00:00:00Z")
    var monthly = Array(repeating: Array(repeating: [String](), count: 12), count: pollers.count)
    for hour in 0..<8_760 {
      let month = hour / 730
      let pollerIndex = pollers.count == 1 ? 0 : hour % pollers.count
      let fetchedAt = formatter.string(from: start.addingTimeInterval(Double(hour + 1) * 3_600))
      let poller = pollers[pollerIndex].uuidString
      let line = #"{"format":"vf-listening-fetch","version":1,"poller":"\#(poller)","host":"Bench","fetchedAt":"\#(fetchedAt)","outcome":"plays","newCount":2,"pagesRead":1,"items":[{"kind":"song","id":"song-a","title":"Song A","artist":"Artist"},{"kind":"song","id":"song-b","title":"Song B","artist":"Artist"}]}"#
      monthly[pollerIndex][month].append(line)
    }
    return monthly.flatMap { files in
      files.map { Data(($0.joined(separator: "\n") + "\n").utf8) }
    }
  }

  private func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}

private actor CannedPages {
  private let pages: [Int: RecentlyPlayedPage]
  private let failingOffset: Int?
  private(set) var offsets: [Int] = []

  init(_ pages: [Int: RecentlyPlayedPage], failingOffset: Int? = nil) {
    self.pages = pages
    self.failingOffset = failingOffset
  }

  func page(_ offset: Int) throws -> RecentlyPlayedPage {
    offsets.append(offset)
    if offset == failingOffset { throw PageError.expectedFailure }
    return pages[offset] ?? .init(items: [], hasNext: false)
  }
}

private enum PageError: Error {
  case expectedFailure
}
