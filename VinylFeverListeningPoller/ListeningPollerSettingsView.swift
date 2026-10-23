import Foundation
import MusicKit
import Observation
import ServiceManagement
import SwiftUI
import VinylFeverListening

private let agentPlistName = "VFListeningPollerAgent.plist"

struct ListeningPollerSettingsView: View {
  @State private var model = ListeningPollerSettingsModel()

  var body: some View {
    Form {
      Section("Apple Music") {
        LabeledContent("Authorization", value: model.authorizationLabel)
        if model.authorizationStatus != .authorized {
          Button("Authorize") { Task { await model.authorize() } }
        }
      }

      Section("Background polling") {
        Toggle("Poll every hour on this Mac", isOn: Binding(
          get: { model.pollingEnabled },
          set: { enabled in
            Task {
              if enabled { await model.enablePolling() }
              else { await model.disablePolling() }
            }
          }
        ))
        if let idleMessage = model.idleAgentMessage {
          Text(idleMessage).foregroundStyle(.secondary)
        }
        if model.serviceStatus == .requiresApproval {
          Text("Approve VF Listening Poller in Login Items to let it run in the background.")
            .foregroundStyle(.secondary)
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
        }
        if model.canPollNow {
          Button("Poll now") { Task { await model.pollNow() } }
            .disabled(model.isPollingNow)
        }
        LabeledContent("Last fetch", value: model.lastFetchLabel)
        LabeledContent("Plays logged today", value: String(model.playsToday))
      }

      Section("Listening folder") {
        Text(model.folderPath)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
        LabeledContent("Lease", value: model.leaseLabel)
      }

      if let error = model.errorMessage {
        Section {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .task { await model.refresh() }
    .alert("Make this Mac the poller?", isPresented: $model.isConfirmingTakeover) {
      Button("Make This Mac the Poller") { Task { await model.confirmTakeover() } }
      Button("Cancel", role: .cancel) { model.cancelTakeover() }
    } message: {
      Text(model.takeoverMessage)
    }
  }
}

@MainActor
@Observable
private final class ListeningPollerSettingsModel {
  private(set) var authorizationStatus = MusicAuthorization.currentStatus
  private(set) var serviceStatus = SMAppService.agent(plistName: agentPlistName).status
  private(set) var lastFetch: ListeningFetch?
  private(set) var playsToday = 0
  private(set) var holdsLease = false
  private(set) var leaseExists = false
  private(set) var errorMessage: String?
  private(set) var isPollingNow = false
  var isConfirmingTakeover = false
  private var pendingTakeoverPoller: UUID?
  private var pendingLease: ListeningLease?
  private var leaseHost: String?

  var pollingEnabled: Bool {
    (serviceStatus == .enabled || serviceStatus == .requiresApproval)
      && !(leaseExists && !holdsLease)
  }

  var canPollNow: Bool { holdsLease && serviceStatus == .enabled }

  var idleAgentMessage: String? {
    let agentRegistered = serviceStatus == .enabled || serviceStatus == .requiresApproval
    guard agentRegistered, leaseExists, !holdsLease else { return nil }
    return "\(leaseHost ?? "Another Mac") is polling. This Mac's agent is idle until you turn polling back on here."
  }

  var authorizationLabel: String {
    switch authorizationStatus {
    case .authorized: "Authorized"
    case .notDetermined: "Not authorized"
    case .denied: "Denied"
    case .restricted: "Restricted"
    @unknown default: "Unknown"
    }
  }

  var lastFetchLabel: String {
    guard let lastFetch else { return "None yet" }
    return "\(lastFetch.fetchedAt.formatted(date: .abbreviated, time: .shortened)) · \(lastFetch.outcome.rawValue)"
  }

  var leaseLabel: String {
    if holdsLease { "This Mac holds the lease" }
    else if leaseExists { "Another Mac holds the lease" }
    else { "No lease yet" }
  }

  var folderPath: String {
    "~/Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Listening/"
  }

  func authorize() async {
    authorizationStatus = await MusicAuthorization.request()
    await refresh()
  }

  var takeoverMessage: String {
    "\(pendingLease?.host ?? "Another Mac") is polling now. Make this Mac the poller?"
  }

  func enablePolling() async {
    do {
      let store = ListeningStore.liveValue
      let poller = try store.pollerID()
      let lease = try store.readLease()
      if let lease, lease.poller != poller {
        pendingTakeoverPoller = poller
        pendingLease = lease
        isConfirmingTakeover = true
        return
      }
      try registerAgentIfNeeded()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    await refresh()
  }

  func confirmTakeover() async {
    guard let poller = pendingTakeoverPoller, pendingLease != nil else { return }
    do {
      let store = ListeningStore.liveValue
      let service = SMAppService.agent(plistName: agentPlistName)
      try ListeningTakeover.perform(
        store: store, poller: poller, host: store.hostName(), now: Date(),
        isAgentEnabled: { service.status == .enabled || service.status == .requiresApproval },
        register: { try registerAgentIfNeeded() },
        kickstart: {
          try ListeningLaunchAgentKickstarter.kickstart(
            label: "com.jonphillips.vinylfever.listeningpoller.agent")
        })
      serviceStatus = service.status
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    cancelTakeover()
    await refresh()
  }

  func cancelTakeover() {
    pendingTakeoverPoller = nil
    pendingLease = nil
    isConfirmingTakeover = false
  }

  func disablePolling() async {
    let service = SMAppService.agent(plistName: agentPlistName)
    do {
      try await service.unregister()
      serviceStatus = service.status
      errorMessage = nil
    } catch {
      serviceStatus = service.status
      errorMessage = error.localizedDescription
    }
    await refresh()
  }

  func pollNow() async {
    guard canPollNow, !isPollingNow else { return }
    isPollingNow = true
    defer { isPollingNow = false }
    do {
      let store = ListeningStore.liveValue
      let previousFetchAt = try store.readFetches().last?.fetchedAt
      try ListeningLaunchAgentKickstarter.kickstart(
        label: "com.jonphillips.vinylfever.listeningpoller.agent")
      for attempt in 0...30 {
        try Task.checkCancellation()
        let newestFetchAt = try store.readFetches().last?.fetchedAt
        if let newestFetchAt, newestFetchAt != previousFetchAt { break }
        if attempt < 30 { try await Task.sleep(for: .seconds(1)) }
      }
      await refresh()
    } catch is CancellationError {
      await refresh()
    } catch {
      await refresh()
      errorMessage = error.localizedDescription
    }
  }

  private func registerAgentIfNeeded() throws {
    let service = SMAppService.agent(plistName: agentPlistName)
    if service.status != .enabled { try service.register() }
    serviceStatus = service.status
  }

  func refresh() async {
    authorizationStatus = MusicAuthorization.currentStatus
    let service = SMAppService.agent(plistName: agentPlistName)
    serviceStatus = service.status
    do {
      let store = ListeningStore.liveValue
      let poller = try store.pollerID()
      let lease = try store.readLease()
      leaseExists = lease != nil
      holdsLease = lease?.poller == poller
      leaseHost = lease?.host
      let fetches = try store.readFetches()
      lastFetch = fetches.last
      let startOfDay = Calendar.current.startOfDay(for: Date())
      playsToday = fetches.filter {
        $0.fetchedAt >= startOfDay && ($0.outcome == .plays || $0.outcome == .gap)
      }.reduce(0) { $0 + $1.newCount }
      errorMessage = try store.readLastPollError()
        ?? (lastFetch?.outcome == .failed ? lastFetch?.error : nil)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
