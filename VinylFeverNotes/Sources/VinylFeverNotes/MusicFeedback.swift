import Foundation

public struct FeedbackSong: Codable, Equatable, Sendable, Identifiable {
  public var title: String
  public var artist: String
  public var album: String?
  public var catalogID: String?
  public var playCount: Int?
  public var releaseDate: String?
  public var duration: String?

  public var id: String { "\(title)|\(artist)|\(catalogID ?? "")" }

  public init(title: String, artist: String, album: String? = nil, catalogID: String? = nil,
              playCount: Int? = nil, releaseDate: String? = nil, duration: String? = nil) {
    self.title = title
    self.artist = artist
    self.album = album
    self.catalogID = catalogID
    self.playCount = playCount
    self.releaseDate = releaseDate
    self.duration = duration
  }
}

public enum FeedbackStaleReason: String, Codable, Equatable, Sendable {
  case missingEntry
  case blankTitle
  case notPlaying
  case belowNewerSong
}

public struct FeedbackIdentification: Equatable, Sendable {
  public var entry: FeedbackSong?
  public var staleReason: FeedbackStaleReason?
  public var choices: [FeedbackSong]

  public var isTrusted: Bool { staleReason == nil }
}

public enum MusicFeedback {
  public static func identify(
    entry: FeedbackSong?, playbackStatus: String, recentlyPlayed: [FeedbackSong]
  ) -> FeedbackIdentification {
    let reason: FeedbackStaleReason?
    if entry == nil {
      reason = .missingEntry
    } else if entry!.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      reason = .blankTitle
    } else if playbackStatus.lowercased() != "playing" {
      reason = .notPlaying
    } else if let entry, let index = recentlyPlayed.firstIndex(where: { matches(entry, $0) }), index > 0 {
      reason = .belowNewerSong
    } else {
      reason = nil
    }

    let includeEntry = reason != .belowNewerSong
    var songs = includeEntry ? entry.map { [$0] } ?? [] : []
    for song in recentlyPlayed where !songs.contains(where: { matches($0, song) }) {
      songs.append(song)
      if songs.count == 4 { break }
    }
    return FeedbackIdentification(entry: entry, staleReason: reason, choices: Array(songs.prefix(4)))
  }

  public static func matches(_ lhs: FeedbackSong, _ rhs: FeedbackSong) -> Bool {
    normalized(lhs.title) == normalized(rhs.title) && normalized(lhs.artist) == normalized(rhs.artist)
  }

  public static func makeNote(
    _ text: String, selected: FeedbackSong?, source: String, at date: Date, device: String
  ) -> TasteNote? {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return TasteNote(
      notedAt: date,
      note: text,
      source: source,
      title: selected?.title,
      artist: selected?.artist,
      album: selected?.album,
      playCount: selected?.playCount,
      releaseDate: selected?.releaseDate,
      duration: selected?.duration,
      device: device,
      catalogID: selected?.catalogID
    )
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}
