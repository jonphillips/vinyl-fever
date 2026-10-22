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

  /// Transfers polling to a Mac and preserves the old holder as a one-time recovery baseline.
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
    try store.writeHandoverMarker(ListeningHandoverMarker(
      previousPoller: previousLease.poller, fallbackSince: previousLease.takenAt))
    let lease = ListeningLease(poller: poller, host: host, takenAt: now)
    do {
      try store.writeLease(lease)
      try store.clearLastList()
    } catch {
      try? store.writeLease(previousLease)
      try? store.clearHandoverMarker()
      throw error
    }
  }
}

public enum ListeningLeaseTakeoverError: Error, Equatable {
  case noOtherLeaseholder
}
