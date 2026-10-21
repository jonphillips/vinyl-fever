import Foundation

public enum ListeningLeaseDecision: Equatable, Sendable {
  case claimIfEmpty
  case write
  case skip
}

public enum ListeningLeaseRules {
  /// Before S3, the first poller may establish the lease. Existing leases are never silently
  /// taken over; only the current holder may append to its stream.
  public static func decision(current: ListeningLease?, poller: UUID) -> ListeningLeaseDecision {
    guard let current else { return .claimIfEmpty }
    return current.permitsWrites(by: poller) ? .write : .skip
  }

  /// Transfers polling to a Mac and clears its previous diff baseline so its first fetch starts
  /// a new stream instead of replaying plays from its last time as leaseholder.
  public static func takeOver(
    store: ListeningStore,
    poller: UUID,
    host: String,
    now: Date
  ) throws {
    let previousLease = try store.readLease()
    guard let previousLease, previousLease.poller != poller else {
      throw ListeningLeaseTakeoverError.noOtherLeaseholder
    }
    let lease = ListeningLease(poller: poller, host: host, takenAt: now)
    try store.writeLease(lease)
    do {
      try store.clearLastList()
    } catch {
      try? store.writeLease(previousLease)
      throw error
    }
  }
}

public enum ListeningLeaseTakeoverError: Error, Equatable {
  case noOtherLeaseholder
}
