import Dependencies
import Foundation
import VinylFeverNotes

public struct PlaylistReviewAlertSender {
  @Dependency(\.playlistInboxClient) private var inbox
  @Dependency(\.playlistCreationClient) private var creations
  @Dependency(\.playlistAlertClient) private var alerts

  public init() {}

  public func sendPendingAlerts() async {
    let log: PlaylistCreationsReadResult
    do { log = try creations.read() }
    catch {
      NSLog("Vinyl Fever could not read playlist alerts: %@", error.localizedDescription)
      return
    }
    let latest = PlaylistCreationsCodec.latestEvents(log.events)
    let events = latest.values.filter { $0.kind == .needsReview }.sorted { $0.at < $1.at }
    let items = (try? inbox.list()) ?? []
    for event in events {
      let eventKey = alertKey(event)
      guard !alerts.hasAttempted(eventKey) else { continue }
      let itemKey = PlaylistCreationsCodec.batchKey(host: event.host, recordedAt: event.recordedAt)
      let total = items.first(where: {
        guard let host = $0.batchHost, let recordedAt = $0.recordedAt else { return false }
        return PlaylistCreationsCodec.batchKey(host: host, recordedAt: recordedAt) == itemKey
      })?.trackCount ?? (event.skipped?.count ?? 0)
      let message = Self.message(for: event, totalSongs: total)
      let phoneNumber = alerts.phoneNumber().trimmingCharacters(in: .whitespacesAndNewlines)
      guard !phoneNumber.isEmpty else {
        NSLog("Vinyl Fever alert: %@", message)
        alerts.markAttempted(eventKey)
        continue
      }
      alerts.markAttempted(eventKey)
      do { try await alerts.send(phoneNumber, message) }
      catch { NSLog("Vinyl Fever could not send a playlist alert: %@", error.localizedDescription) }
    }
  }

  public static func message(for event: PlaylistCreationEvent, totalSongs: Int) -> String {
    let firstLine: String
    if let error = event.error, event.skipped?.isEmpty != false {
      firstLine = "\(event.playlist): \(error)"
    } else {
      let skipped = event.skipped ?? []
      let found = max(0, totalSongs - skipped.count)
      let names = skipped.prefix(2).map { "\($0.title) — \($0.artist)" }.joined(separator: "; ")
      firstLine = names.isEmpty
        ? "\(event.playlist): \(found) of \(totalSongs) songs found."
        : "\(event.playlist): \(found) of \(totalSongs) songs found. Needs: \(names)."
    }
    return "\(firstLine)\nFinish it in Vinyl Fever on your phone."
  }

  private func alertKey(_ event: PlaylistCreationEvent) -> String {
    let batch = PlaylistCreationsCodec.batchKey(host: event.host, recordedAt: event.recordedAt)
    return "\(batch)|\(event.at.timeIntervalSince1970.bitPattern)"
  }
}
