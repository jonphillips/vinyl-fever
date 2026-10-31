import Foundation
import Testing
import VinylFeverNotes

@Suite("Listening log")
struct ListeningLogTests {
  private let poller = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private let secondPoller = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
  private var t0: Date { date("2026-10-17T10:00:00Z") }

  @Test("JSONL codec round-trips v1 and handover v2 records, ignores partial lines, and rejects v3")
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

    let since = ListeningSince(poller: secondPoller, fetchedAt: t0)
    let handover = ListeningFetch(
      poller: poller, host: "Laptop", fetchedAt: t0.addingTimeInterval(60), outcome: .plays,
      newCount: 1, pagesRead: 1, items: [item("handover")], since: since)
    let handoverData = try ListeningLogCodec.encode(handover)
    #expect(String(decoding: handoverData, as: UTF8.self).contains("\"version\":2"))
    #expect(try ListeningLogCodec.decodeJSONL(handoverData) == [handover])

    let future = Data(#"{"format":"vf-listening-fetch","version":3}"#.utf8)
    do {
      _ = try ListeningLogCodec.decodeJSONL(future + Data("\n".utf8))
      Issue.record("Expected newer-version error")
    } catch let error as ListeningLogCodecError {
      #expect(error == .newerVersion(3))
    }
  }

  @Test("handover plays use the old fetch window and an unrecoverable baseline reports a gap")
  func handoverWindowsAndGap() {
    let oldFetchAt = t0.addingTimeInterval(-900)
    let handoverAt = t0
    let handoverPoller = UUID()
    let recovered = ListeningFetch(
      poller: secondPoller, host: "Laptop", fetchedAt: handoverAt, outcome: .plays,
      newCount: 1, pagesRead: 1, items: [item("recovered")],
      since: ListeningSince(poller: poller, fetchedAt: oldFetchAt))
    let recoveredLog = ListeningLog(streams: [[recovered]], now: handoverAt, identity: .empty)
    #expect(recoveredLog.plays.first?.windowStart == oldFetchAt)

    let baseline = ListeningFetch(
      poller: handoverPoller, host: "Laptop", fetchedAt: handoverAt, outcome: .baseline,
      pagesRead: 1, items: [item("baseline")],
      since: ListeningSince(poller: poller, fetchedAt: oldFetchAt))
    let baselineLog = ListeningLog(streams: [[baseline]], now: handoverAt)
    #expect(baselineLog.coverage.gaps.count == 1)
    #expect(baselineLog.coverage.gaps.first?.windowStart == oldFetchAt)
    #expect(baselineLog.coverage.gaps.first?.outcome == .gap)
  }

  private func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? {
      formatter.formatOptions = [.withInternetDateTime]
      return formatter.date(from: value)!
    }()
  }

  private func item(_ id: String) -> ListeningItem {
    ListeningItem(kind: .song, id: id, title: id, artist: "Artist")
  }
}
