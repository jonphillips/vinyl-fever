import Foundation
import Testing
import VinylFeverListening

@testable import VinylFever

@MainActor
@Suite
struct ListeningPollingSettingsTests {
  @Test
  func takeoverRequiresConfirmationThenRegistersAndKeepsLeaseWhenDisabled() async {
    let localPoller = UUID()
    let miniLease = ListeningLease(poller: UUID(), host: "Mac mini", takenAt: Date(timeIntervalSince1970: 1))
    let state = ListeningSettingsState(poller: localPoller, lease: miniLease)
    let agentState = ListeningAgentState()
    let model = ListeningPollingSettingsModel(
      store: Self.store(state),
      agent: ListeningAgentClient(
        isEnabled: { agentState.isEnabled },
        requiresApproval: { false },
        register: { agentState.isEnabled = true },
        unregister: { agentState.isEnabled = false; agentState.didUnregister = true }
      ),
      now: { Date(timeIntervalSince1970: 2) }
    )

    await model.enablePolling()

    #expect(model.isConfirmingTakeover)
    #expect(model.takeoverMessage.contains("Mac mini"))
    #expect(state.writeCount == 0)
    #expect(!agentState.isEnabled)

    await model.confirmTakeover()

    #expect(!model.isConfirmingTakeover)
    #expect(state.lease?.poller == localPoller)
    #expect(state.lease?.host == "This Mac")
    #expect(agentState.isEnabled)

    await model.disablePolling()

    #expect(agentState.didUnregister)
    #expect(state.lease?.poller == localPoller)
  }

  private static func store(_ state: ListeningSettingsState) -> ListeningStore {
    ListeningStore(
      pollerID: { state.poller },
      readLease: { state.lease },
      writeLease: { state.lease = $0; state.writeCount += 1 },
      readLastList: { nil },
      writeLastList: { _ in },
      appendFetch: { _ in },
      listeningFolder: { URL(fileURLWithPath: "/tmp/Listening") },
      hostName: { "This Mac" }
    )
  }
}

private final class ListeningSettingsState: @unchecked Sendable {
  let poller: UUID
  var lease: ListeningLease?
  var writeCount = 0

  init(poller: UUID, lease: ListeningLease?) {
    self.poller = poller
    self.lease = lease
  }
}

private final class ListeningAgentState: @unchecked Sendable {
  var isEnabled = false
  var didUnregister = false
}
