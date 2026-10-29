import Foundation
import VinylFeverListening
@_exported import VinylFeverNotes

public enum TasteNotePeriod: String, Sendable {
  case day = "24h"
  case week = "7d"
  case month = "30d"
  case quarter = "90d"
  case allTime = "all_time"

  public func contains(_ date: Date, now: Date) -> Bool {
    switch self {
    case .day: date >= now.addingTimeInterval(-86_400)
    case .week: date >= now.addingTimeInterval(-7 * 86_400)
    case .month: date >= now.addingTimeInterval(-30 * 86_400)
    case .quarter: date >= now.addingTimeInterval(-90 * 86_400)
    case .allTime: true
    }
  }
}

public struct TasteNoteSongCandidate: Codable, Equatable, Sendable {
  public var artist: String
  public var title: String
  public var album: String?
  public var playedAt: Date

  public init(artist: String, title: String, album: String?, playedAt: Date) {
    self.artist = artist
    self.title = title
    self.album = album
    self.playedAt = playedAt
  }
}

public enum TasteNoteCandidates {
  public static func forNote(_ note: TasteNote, log: ListeningLog, limit: Int = 5) -> [TasteNoteSongCandidate] {
    guard note.isTimeOnly else { return [] }
    return log.plays.compactMap { play -> (Double, TasteNoteSongCandidate)? in
      let delta: Double
      if note.notedAt < play.windowStart {
        delta = play.windowStart.timeIntervalSince(note.notedAt)
      } else if note.notedAt > play.windowEnd {
        delta = note.notedAt.timeIntervalSince(play.windowEnd)
      } else {
        delta = 0
      }
      guard delta <= 10 * 60 else { return nil }
      return (delta, TasteNoteSongCandidate(artist: play.item.artist, title: play.item.title,
        album: play.item.album, playedAt: play.windowEnd))
    }.sorted { $0.0 < $1.0 }
      .prefix(max(1, limit)).map(\.1)
  }
}
