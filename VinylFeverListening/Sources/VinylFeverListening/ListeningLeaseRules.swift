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
}
