import Darwin
import Foundation

public enum ListeningTakeover {
  /// Transfers the lease, registers the poller when needed, and asks launchd to start it.
  /// Registration failure rolls back the lease and removes the unconsumed recovery marker.
  /// A kickstart failure leaves the lease in place so an approved agent can recover on its next run.
  public static func perform(
    store: ListeningStore,
    poller: UUID,
    host: String,
    now: Date,
    isAgentEnabled: () -> Bool,
    register: () throws -> Void,
    kickstart: () throws -> Void
  ) throws {
    let previousLease = try store.readLease()
    try ListeningLeaseRules.takeOver(store: store, poller: poller, host: host, now: now)
    do {
      if !isAgentEnabled() { try register() }
    } catch {
      if let previousLease { try? store.writeLease(previousLease) }
      try? store.clearHandoverMarker()
      throw error
    }
    try kickstart()
  }
}

public enum ListeningLaunchAgentKickstarter {
  public static func kickstart(label: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ListeningLaunchAgentKickstartError(label: label, status: process.terminationStatus)
    }
  }
}

public struct ListeningLaunchAgentKickstartError: Error, LocalizedError, Equatable, Sendable {
  public var label: String
  public var status: Int32

  public init(label: String, status: Int32) {
    self.label = label
    self.status = status
  }

  public var errorDescription: String? {
    "launchd could not start \(label) (status \(status))."
  }
}
