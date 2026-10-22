import Dependencies
import Foundation
import Testing
import VinylFeverListening

@testable import VinylFever

@MainActor
@Suite
struct ListeningPollingSettingsTests {
  @Test
  func registeredIdleAgentCanTakeOverWithoutReregisteringAndRetainsLeaseWhenDisabled() async {
    let now = date("2026-10-21T12:00:00Z")
    let localPoller = UUID()
    let miniLease = ListeningLease(
      poller: UUID(), host: "Mac mini", takenAt: now.addingTimeInterval(-3_600))
    let state = ListeningSettingsState(poller: localPoller, lease: miniLease)
    state.fetches = [
      ListeningFetch(
        poller: miniLease.poller, host: miniLease.host,
        fetchedAt: now.addingTimeInterval(-120), outcome: .baseline, pagesRead: 1)
    ]
    let agentState = ListeningAgentState(isEnabled: true)
    let model = withDependencies {
      $0.listeningStore = Self.store(state)
      $0.listeningAgentClient = agentState.client
      $0.listeningAuthorizationClient = ListeningAuthorizationClient(status: { .authorized })
      $0.recentlyPlayedClient.page = { _ in
        RecentlyPlayedPage(items: [ListeningItem(kind: .song, id: "takeover", title: "Takeover", artist: "Artist")], hasNext: false)
      }
      $0.date = .constant(now)
    } operation: {
      ListeningPollingSettingsModel()
    }

    await model.refresh()

    #expect(!model.pollingEnabled)
    #expect(model.idleAgentMessage == "Mac mini is polling. This Mac's agent is idle until you turn polling back on here.")
    #expect(model.statusLine.contains("Polling Mac: Mac mini · Last fetch 2 minutes ago"))
    #expect(model.statusLine.contains("0 gaps in 30 days"))

    await model.enablePolling()

    #expect(model.isConfirmingTakeover)
    #expect(model.takeoverMessage == "Mac mini is polling now. Make this Mac the poller?")
    #expect(state.writeCount == 0)
    #expect(agentState.registerCount == 0)

    await model.confirmTakeover()

    #expect(!model.isConfirmingTakeover)
    #expect(state.lease?.poller == localPoller)
    #expect(state.lease?.host == "This Mac")
    #expect(state.clearLastListCount == 1)
    #expect(agentState.registerCount == 0)
    #expect(model.pollingEnabled)
    #expect(state.fetches.last?.poller == localPoller)
    #expect(state.fetches.last?.outcome == .baseline)

    await model.disablePolling()

    #expect(agentState.didUnregister)
    #expect(state.lease?.poller == localPoller)
  }

  private static func store(_ state: ListeningSettingsState) -> ListeningStore {
    ListeningStore(
      pollerID: { state.poller },
      readLease: { state.lease },
      writeLease: { state.lease = $0; state.writeCount += 1 },
      readLastList: { state.lastList },
      writeLastList: { state.lastList = $0 },
      clearLastList: { state.lastList = nil; state.clearLastListCount += 1 },
      appendFetch: { state.fetches.append($0) },
      readFetches: { state.fetches },
      readLastPollError: { nil },
      listeningFolder: { URL(fileURLWithPath: "/tmp/Listening") },
      hostName: { "This Mac" }
    )
  }

  private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }
}

private final class ListeningSettingsState: @unchecked Sendable {
  let poller: UUID
  var lease: ListeningLease?
  var lastList: [ListeningItem]?
  var fetches: [ListeningFetch] = []
  var writeCount = 0
  var clearLastListCount = 0

  init(poller: UUID, lease: ListeningLease?) {
    self.poller = poller
    self.lease = lease
  }
}

private final class ListeningAgentState: @unchecked Sendable {
  var isEnabled: Bool
  var requiresApproval = false
  var registerCount = 0
  var didUnregister = false

  init(isEnabled: Bool) {
    self.isEnabled = isEnabled
  }

  var client: ListeningAgentClient {
    ListeningAgentClient(
      isEnabled: { self.isEnabled },
      requiresApproval: { self.requiresApproval },
      register: { self.registerCount += 1; self.isEnabled = true },
      unregister: { self.didUnregister = true; self.isEnabled = false }
    )
  }
}
