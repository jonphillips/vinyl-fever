import Foundation
import VinylFeverNotes

public enum ListeningStatusLine {
  public static let setupPointer = "Not set up yet. Follow the setup instructions to start collecting history."

  public static func make(
    fetches: [ListeningFetch],
    now: Date,
    timeZone: TimeZone = .current,
    locale: Locale = .current
  ) -> String {
    guard !fetches.isEmpty else { return setupPointer }
    let streams = Dictionary(grouping: fetches, by: \.poller).values.map { $0 }
    let coverage = ListeningLog(streams: streams, now: now).coverage
    let host = coverage.host ?? "Unknown"
    let sinceStyle = Date.FormatStyle(
      date: .omitted, time: .omitted, locale: locale, calendar: .current, timeZone: timeZone
    ).month(.abbreviated).day().hour().minute()
    let since = coverage.firstFetchAt.map { $0.formatted(sinceStyle) } ?? "Unknown"
    let age = coverage.lastFetchAt.map { relativeAge(max(0, now.timeIntervalSince($0))) } ?? "Unknown"
    let recentGapCount = coverage.gaps.filter { $0.windowEnd >= now.addingTimeInterval(-30 * 24 * 60 * 60) }.count
    let gapLabel = recentGapCount == 1 ? "1 gap" : "\(recentGapCount) gaps"
    return "Polling Mac: \(host) · Last fetch \(age) · Coverage since \(since) · \(gapLabel) in 30 days"
  }

  private static func relativeAge(_ interval: TimeInterval) -> String {
    if interval < 60 { return "less than a minute ago" }
    let minutes = Int(interval / 60)
    if minutes < 60 { return "\(minutes) minutes ago" }
    let hours = minutes / 60
    if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
    let days = hours / 24
    return days == 1 ? "1 day ago" : "\(days) days ago"
  }
}
