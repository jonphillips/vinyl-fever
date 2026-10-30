import Foundation

public enum WhyThisSongAnswer: Equatable, Sendable {
  case withReason(batch: RecommendationBatch, track: RecommendationTrack)
  case stagedWithoutReason(batch: RecommendationBatch, track: RecommendationTrack)
  case notPicked(batch: RecommendationBatch, track: RecommendationTrack)
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
        MusicFeedback.matches(
          FeedbackSong(title: $0.title, artist: $0.artist),
          FeedbackSong(title: song.title, artist: song.artist)
        )
      }.map { (batch, $0) }
    }
    let recommendations = matches.filter { $0.1.picked != false }
    let unpicked = matches.filter { $0.0.kind == "new-music-picks" && $0.1.picked == false }
    let newestWithWhy = recommendations.filter { nonempty($0.1.why) != nil }
      .max { $0.0.recordedAt < $1.0.recordedAt }
    if let (batch, track) = newestWithWhy {
      return .withReason(batch: batch, track: track)
    }
    if let (batch, track) = recommendations.max(by: { $0.0.recordedAt < $1.0.recordedAt }) {
      return .stagedWithoutReason(batch: batch, track: track)
    }
    if let (batch, track) = unpicked.max(by: { $0.0.recordedAt < $1.0.recordedAt }) {
      return .notPicked(batch: batch, track: track)
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
      let date = RecommendationDatePhrase.format(batch.recordedAt, relativeTo: now, calendar: calendar, timeZone: timeZone)
      let intro: String
      if batch.kind == "new-music-picks" {
        intro = "\(song.title) by \(song.artist) was one of the chat's New Music picks on \(date)."
      } else {
        intro = "\(song.title) by \(song.artist) was in \(playlistPhrase(batch)), staged \(date)."
      }
      var text = "\(intro) \(nonempty(track.why) ?? "")"
      let likes = Array((track.like ?? []).prefix(3))
      if !likes.isEmpty {
        let names = likes.map { "\($0.title) by \($0.artist)" }
        text += " The chat compared it with \(joined(names))."
      }
      return text
    case let .stagedWithoutReason(batch, _):
      let date = RecommendationDatePhrase.format(batch.recordedAt, relativeTo: now, calendar: calendar, timeZone: timeZone)
      if batch.kind == "new-music-picks" {
        return "\(song.title) by \(song.artist) was one of the chat's New Music picks on \(date), without a reason."
      }
      return "\(song.title) by \(song.artist) was in \(playlistPhrase(batch)), staged \(date), without a reason."
    case let .notPicked(batch, _):
      let date = RecommendationDatePhrase.format(batch.recordedAt, relativeTo: now, calendar: calendar, timeZone: timeZone)
      return "The chat saw \(song.title) by \(song.artist) in New Music on \(date) and didn't pick it."
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

  private static func joined(_ values: [String]) -> String {
    switch values.count {
    case 0: ""
    case 1: values[0]
    case 2: "\(values[0]) and \(values[1])"
    default: "\(values.dropLast().joined(separator: ", ")) and \(values[values.count - 1])"
    }
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
