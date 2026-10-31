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

/// Indexed, immutable listening/keeper evidence with incremental note and keep updates.
public struct PlaylistProgressIndex: Sendable {
  private var keeperNamesByTrackKey: [String: Set<String>] = [:]
  private var latestPlayEndByTrackKey: [String: Date] = [:]
  private var noteDatesBySongID: [String: [Date]] = [:]
  private var indexedNoteIDs: Set<String> = []
  private var trackKeyByIdentity: [TrackIdentity: String] = [:]

  public init(
    playlists: [PlaylistShelfPlaylist],
    keepers: [PlaylistKeeperTracks],
    plays: [ListeningPlay],
    notes: [TasteNote]
  ) {
    for keeper in keepers {
      for track in keeper.tracks {
        addKeeper(name: keeper.name, artist: track.artist, title: track.title)
      }
    }
    for play in plays {
      let key = trackKey(artist: play.item.artist, title: play.item.title)
      if play.windowEnd > latestPlayEndByTrackKey[key, default: .distantPast] {
        latestPlayEndByTrackKey[key] = play.windowEnd
      }
    }
    addNotes(notes, playlists: playlists)
  }

  public mutating func addKeeper(name: String, artist: String, title: String) {
    keeperNamesByTrackKey[trackKey(artist: artist, title: title), default: []].insert(name)
  }

  /// Uses the established note matcher once per newly read note; later progress projections are O(songs).
  public mutating func addNotes(_ notes: [TasteNote], playlists: [PlaylistShelfPlaylist]) {
    let songs = playlists.flatMap(\.songs)
    for note in notes where indexedNoteIDs.insert(Self.noteID(note)).inserted {
      guard !note.isTimeOnly else { continue }
      for song in songs where !PlaylistTasteNotes.matching([note], title: song.title, artist: song.artist).isEmpty {
        noteDatesBySongID[song.id, default: []].append(note.notedAt)
      }
    }
  }

  public mutating func result(for playlist: PlaylistShelfPlaylist) -> PlaylistProgressResult {
    let stagedAt = playlist.batch.recordedAt
    var songStatuses: [String: PlaylistSongProgress] = [:]
    var counts = PlaylistProgressCounts(kept: 0, passedWithFeedback: 0, passedWithoutFeedback: 0, notHeard: 0)

    for song in playlist.songs {
      let key = trackKey(artist: song.artist, title: song.title)
      let keeperNames = (keeperNamesByTrackKey[key] ?? []).sorted()
      let hasNote = noteDatesBySongID[song.id]?.contains(where: { $0 >= stagedAt }) ?? false
      let hasPlay = (latestPlayEndByTrackKey[key] ?? .distantPast) >= stagedAt

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
      songStatuses[song.id] = status
    }
    return PlaylistProgressResult(songs: songStatuses, counts: counts)
  }

  private static func noteID(_ note: TasteNote) -> String {
    note.id.map { "id:\($0)" }
      ?? "\(note.notedAt.timeIntervalSince1970)|\(note.title ?? "")|\(note.artist ?? "")"
  }

  private mutating func trackKey(artist: String, title: String) -> String {
    let identity = TrackIdentity(artist: artist, title: title)
    if let cached = trackKeyByIdentity[identity] { return cached }
    let key = ListeningTrackKey.make(artist: artist, title: title)
    trackKeyByIdentity[identity] = key
    return key
  }

  private struct TrackIdentity: Hashable, Sendable {
    var artist: String
    var title: String
  }
}

public enum PlaylistProgress {
  /// Intentionally projects evidence into each staged song's current status.
  public static func make(
    playlist: PlaylistShelfPlaylist,
    keepers: [PlaylistKeeperTracks],
    plays: [ListeningPlay],
    notes: [TasteNote]
  ) -> PlaylistProgressResult {
    var index = PlaylistProgressIndex(playlists: [playlist], keepers: keepers, plays: plays, notes: notes)
    return index.result(for: playlist)
  }
}
