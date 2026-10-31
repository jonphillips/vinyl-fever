import Foundation

public struct PlaylistTrackIdentity: Equatable, Sendable {
  public var title: String
  public var artist: String

  public init(title: String, artist: String) {
    self.title = title
    self.artist = artist
  }
}

public struct PlaylistKeeperTracks: Equatable, Sendable {
  public var name: String
  public var tracks: [PlaylistTrackIdentity]

  public init(name: String, tracks: [PlaylistTrackIdentity]) {
    self.name = name
    self.tracks = tracks
  }
}

public enum PlaylistSongProgress: Equatable, Sendable {
  case kept(in: [String])
  case passed(withFeedback: Bool)
  case notHeard
}

public struct PlaylistProgressCounts: Equatable, Sendable {
  public var kept: Int
  public var passedWithFeedback: Int
  public var passedWithoutFeedback: Int
  public var notHeard: Int

  public var heard: Int { kept + passedWithFeedback + passedWithoutFeedback }
  public var withFeedback: Int { kept + passedWithFeedback }
  public var songCount: Int { heard + notHeard }

  public init(kept: Int, passedWithFeedback: Int, passedWithoutFeedback: Int, notHeard: Int) {
    self.kept = kept
    self.passedWithFeedback = passedWithFeedback
    self.passedWithoutFeedback = passedWithoutFeedback
    self.notHeard = notHeard
  }
}

public struct PlaylistProgressResult: Equatable, Sendable {
  public var songs: [String: PlaylistSongProgress]
  public var counts: PlaylistProgressCounts

  public init(songs: [String: PlaylistSongProgress], counts: PlaylistProgressCounts) {
    self.songs = songs
    self.counts = counts
  }
}

public enum PlaylistProgress {
  /// Intentionally projects log, keeper, and note evidence into each staged song's current status.
  public static func make(
    playlist: PlaylistShelfPlaylist,
    keepers: [PlaylistKeeperTracks],
    plays: [ListeningPlay],
    notes: [TasteNote]
  ) -> PlaylistProgressResult {
    let stageDate = playlist.batch.recordedAt
    var songs: [String: PlaylistSongProgress] = [:]
    var counts = PlaylistProgressCounts(kept: 0, passedWithFeedback: 0, passedWithoutFeedback: 0, notHeard: 0)

    for song in playlist.songs {
      let feedbackSong = FeedbackSong(title: song.title, artist: song.artist)
      let keeperNames = Set(keepers.filter { keeper in
        keeper.tracks.contains { track in
          MusicFeedback.matches(feedbackSong, FeedbackSong(title: track.title, artist: track.artist))
        }
      }.map(\.name)).sorted()

      let hasNote = notes.contains { note in
        guard note.notedAt >= stageDate, !note.isTimeOnly else { return false }
        return PlaylistTasteNotes.matching([note], title: song.title, artist: song.artist).isEmpty == false
      }
      let hasPlay = plays.contains { play in
        play.windowEnd >= stageDate && MusicFeedback.matches(
          feedbackSong, FeedbackSong(title: play.item.title, artist: play.item.artist))
      }

      let status: PlaylistSongProgress
      if !keeperNames.isEmpty {
        status = .kept(in: keeperNames)
        counts.kept += 1
      } else if hasPlay || hasNote {
        status = .passed(withFeedback: hasNote)
        if hasNote { counts.passedWithFeedback += 1 } else { counts.passedWithoutFeedback += 1 }
      } else {
        status = .notHeard
        counts.notHeard += 1
      }
      songs[song.id] = status
    }
    return PlaylistProgressResult(songs: songs, counts: counts)
  }
}
