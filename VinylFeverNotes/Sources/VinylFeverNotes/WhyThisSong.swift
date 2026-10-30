import Foundation

public enum WhyThisSongAnswer: Equatable, Sendable {
  case withReason(batch: RecommendationBatch, track: RecommendationTrack)
  case stagedWithoutReason(batch: RecommendationBatch, track: RecommendationTrack)
  case notRecommended
  case recommendationsUnavailable
}

public enum WhyThisSong {
  public static func answer(
    for song: FeedbackSong,
    ledger: RecommendationLedgerReadResult,
    unreadableFileCount: Int
  ) -> WhyThisSongAnswer {
    let matches = ledger.batches.flatMap { batch in
      batch.tracks.filter {
        normalized($0.title) == normalized(song.title) && normalized($0.artist) == normalized(song.artist)
      }.map { (batch, $0) }
    }
    let newestWithWhy = matches.filter { nonempty($0.1.why) != nil }
      .max { $0.0.recordedAt < $1.0.recordedAt }
    if let (batch, track) = newestWithWhy {
      return .withReason(batch: batch, track: track)
    }
    if let (batch, track) = matches.max(by: { $0.0.recordedAt < $1.0.recordedAt }) {
      return .stagedWithoutReason(batch: batch, track: track)
    }
    return unreadableFileCount == 0 ? .notRecommended : .recommendationsUnavailable
  }

  public static func spokenText(
    for song: FeedbackSong,
    answer: WhyThisSongAnswer,
    now: Date,
    calendar: Calendar,
    timeZone: TimeZone
  ) -> String {
    switch answer {
    case let .withReason(batch, track):
      let playlist = playlistPhrase(batch)
      let date = datePhrase(batch.recordedAt, now: now, calendar: calendar, timeZone: timeZone)
      var text = "\(song.title) by \(song.artist) was in \(playlist), staged \(date). \(nonempty(track.why) ?? "")"
      let likes = Array((track.like ?? []).prefix(3))
      if !likes.isEmpty {
        let names = likes.map { "\($0.title) by \($0.artist)" }
        text += " The chat compared it with \(joined(names))."
      }
      return text
    case let .stagedWithoutReason(batch, _):
      let playlist = playlistPhrase(batch)
      let date = datePhrase(batch.recordedAt, now: now, calendar: calendar, timeZone: timeZone)
      return "\(song.title) by \(song.artist) was in \(playlist), staged \(date), without a reason."
    case .notRecommended:
      return "Vinyl Fever didn't recommend \(song.title) by \(song.artist)."
    case .recommendationsUnavailable:
      return "I can't read the recommendations yet. Try again in a minute."
    }
  }

  private static func playlistPhrase(_ batch: RecommendationBatch) -> String {
    guard let playlist = nonempty(batch.playlist) else { return "a staged batch" }
    return playlist
  }

  private static func datePhrase(_ date: Date, now: Date, calendar: Calendar, timeZone: TimeZone) -> String {
    var calendar = calendar
    calendar.timeZone = timeZone
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
      ? "MMMM d" : "MMMM d, yyyy"
    return formatter.string(from: date)
  }

  private static func joined(_ values: [String]) -> String {
    switch values.count {
    case 0: ""
    case 1: values[0]
    case 2: "\(values[0]) and \(values[1])"
    default: "\(values.dropLast().joined(separator: ", ")) and \(values[values.count - 1])"
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
