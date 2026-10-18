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
          set: { enabled in Task { await model.setPollingEnabled(enabled) } }
        ))
        if model.serviceStatus == .requiresApproval {
          Text("Approve VF Listening Poller in Login Items to let it run in the background.")
            .foregroundStyle(.secondary)
          Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
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

  var pollingEnabled: Bool {
    serviceStatus == .enabled || serviceStatus == .requiresApproval
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

  func setPollingEnabled(_ enabled: Bool) async {
    let service = SMAppService.agent(plistName: agentPlistName)
    do {
      if enabled {
        try service.register()
      } else {
        try await service.unregister()
      }
      serviceStatus = service.status
      errorMessage = nil
    } catch {
      serviceStatus = service.status
      errorMessage = error.localizedDescription
    }
    await refresh()
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
