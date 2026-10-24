import Foundation
import VinylFeverListening

public struct CurationSong: Codable, Equatable, Sendable {
  public var artist: String
  public var title: String
  public var album: String
  public init(artist: String, title: String, album: String) {
    self.artist = artist; self.title = title; self.album = album
  }
}

public struct CurationPlaylistChange: Codable, Equatable, Sendable {
  public var name: String
  public var persistentID: String
  public var added: [CurationSong]
  public var removed: [CurationSong]
  public init(name: String, persistentID: String, added: [CurationSong] = [], removed: [CurationSong] = []) {
    self.name = name; self.persistentID = persistentID; self.added = added; self.removed = removed
  }
}

public struct CurationTrackChange: Codable, Equatable, Sendable {
  public var song: CurationSong
  public var favoriteFrom: Bool?
  public var favoriteTo: Bool?
  public var dislikeFrom: Bool?
  public var dislikeTo: Bool?
}

public struct CurationPlaylistPresence: Codable, Equatable, Sendable {
  public var name: String
  public var persistentID: String
}

public struct CurationChange: Codable, Equatable, Sendable {
  public var format = "vf-curation-change"
  public var version = 1
  public var observedAt: Date
  public var previousSnapshotAt: Date?
  public var baseline: Bool
  public var playlists: [CurationPlaylistChange]
  public var tracks: [CurationTrackChange]
  public var appeared: [CurationPlaylistPresence]
  public var disappeared: [CurationPlaylistPresence]
  public var isEmpty: Bool { !baseline && playlists.isEmpty && tracks.isEmpty && appeared.isEmpty && disappeared.isEmpty }
  public init(observedAt: Date, previousSnapshotAt: Date?, baseline: Bool = false,
    playlists: [CurationPlaylistChange] = [], tracks: [CurationTrackChange] = [],
    appeared: [CurationPlaylistPresence] = [], disappeared: [CurationPlaylistPresence] = []) {
    self.observedAt = observedAt; self.previousSnapshotAt = previousSnapshotAt; self.baseline = baseline
    self.playlists = playlists; self.tracks = tracks; self.appeared = appeared; self.disappeared = disappeared
  }
}

public enum SnapshotCurationDiff {
  public static func diff(previous: LibrarySnapshot?, current: LibrarySnapshot, observedAt: Date) -> CurationChange {
    guard let previous else {
      return CurationChange(observedAt: observedAt, previousSnapshotAt: nil, baseline: true)
    }
    let previousPlaylists = Dictionary(previous.playlists.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let currentPlaylists = Dictionary(current.playlists.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let previousTracks = Dictionary(previous.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let currentTracks = Dictionary(current.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    func song(_ id: String, snapshot: LibrarySnapshot, tracks: [String: LibraryTrack]) -> CurationSong? {
      let outside = snapshot.outsideTracks[id]
      guard let title = tracks[id]?.name ?? outside?.name,
        let artist = tracks[id]?.artist ?? outside?.artist else { return nil }
      return CurationSong(artist: artist, title: title, album: tracks[id]?.album ?? outside?.album ?? "")
    }
    let playlistChanges = current.playlists.compactMap { playlist -> CurationPlaylistChange? in
      guard let old = previousPlaylists[playlist.persistentID] else { return nil }
      // Membership is a set: changes in rank or duplicate order are not curation changes.
      let before = Set(old.members), after = Set(playlist.members)
      let added = after.subtracting(before).sorted().compactMap { song($0, snapshot: current, tracks: currentTracks) }
      let removed = before.subtracting(after).sorted().compactMap { song($0, snapshot: previous, tracks: previousTracks) }
      guard !added.isEmpty || !removed.isEmpty else { return nil }
      return CurationPlaylistChange(name: playlist.name, persistentID: playlist.persistentID, added: added, removed: removed)
    }
    let trackChanges = currentTracks.keys.sorted().compactMap { id -> CurationTrackChange? in
      guard let before = previousTracks[id], let after = currentTracks[id],
        before.favorited != after.favorited || before.disliked != after.disliked else { return nil }
      return CurationTrackChange(song: CurationSong(artist: after.artist, title: after.name, album: after.album),
        favoriteFrom: before.favorited == after.favorited ? nil : before.favorited,
        favoriteTo: before.favorited == after.favorited ? nil : after.favorited,
        dislikeFrom: before.disliked == after.disliked ? nil : before.disliked,
        dislikeTo: before.disliked == after.disliked ? nil : after.disliked)
    }
    let previousIDs = Set(previousPlaylists.keys), currentIDs = Set(currentPlaylists.keys)
    let appeared = current.playlists.filter { !previousIDs.contains($0.persistentID) }.map { CurationPlaylistPresence(name: $0.name, persistentID: $0.persistentID) }
    let disappeared = previous.playlists.filter { !currentIDs.contains($0.persistentID) }.map { CurationPlaylistPresence(name: $0.name, persistentID: $0.persistentID) }
    return CurationChange(observedAt: observedAt, previousSnapshotAt: previous.generatedAt,
      playlists: playlistChanges, tracks: trackChanges, appeared: appeared, disappeared: disappeared)
  }
}

public enum CurationLogCodec {
  public static func encode(_ change: CurationChange) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    var data = try encoder.encode(change); data.append(0x0A); return data
  }
}

public enum NewMusicClassification: String, Codable, Sendable { case kept, passed, unheard, pending }
public struct ClassifiedNewMusicTrack: Codable, Equatable, Sendable {
  public var track: NewMusicTrack
  public var classification: NewMusicClassification
}
public struct NewMusicWeekResult: Codable, Equatable, Sendable {
  public var lastModifiedDate: Date
  public var fetchedAt: Date
  public var counts: [String: Int]
  public var tracks: [ClassifiedNewMusicTrack]
  public init(lastModifiedDate: Date, fetchedAt: Date, counts: [String: Int], tracks: [ClassifiedNewMusicTrack]) {
    self.lastModifiedDate = lastModifiedDate; self.fetchedAt = fetchedAt
    self.counts = counts; self.tracks = tracks
  }
}
public struct TasteBaselines: Codable, Equatable, Sendable {
  public struct Yield: Codable, Equatable, Sendable {
    public var kept: Int; public var passed: Int
    public var ratio: Double? { kept + passed == 0 ? nil : Double(kept) / Double(kept + passed) }
  }
  public struct StickRate: Codable, Equatable, Sendable { public var year: Int; public var selections: Int; public var returned: Int; public var ratio: Double? { selections == 0 ? nil : Double(returned) / Double(selections) } }
  public var weeklyYield: [String: Yield]
  public var overallYield: Yield
  public var stickRates: [StickRate]
  public var pendingWeeks: Int
}

public enum TasteIntelligence {
  public static func songKey(artist: String, title: String, identity: ArtistIdentity) -> String {
    "\(identity.key(artist))|\(ListeningTextNormalizer.libraryTitle(title))"
  }

  public static func keptAndPassed(weeks: [NewMusicWeek], snapshot: LibrarySnapshot,
    roles: PlaylistRoles, log: ListeningLog, now: Date, limit: Int = 8) -> [NewMusicWeekResult] {
    let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
    let tracksByID = Dictionary(snapshot.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let artists = Set(snapshot.tracks.map(\.artist) + snapshot.outsideTracks.values.map(\.artist))
    let identity = ArtistIdentity(knownArtists: artists)
    let keepKeys = Set(resolved.filter { $0.role == .keepers }.flatMap { row in
      row.playlist.members.compactMap { id -> String? in
        let track = tracksByID[id]
        let outside = snapshot.outsideTracks[id]
        guard let artist = track?.artist ?? outside?.artist,
          let title = track?.name ?? outside?.name,
          !identity.key(artist).isEmpty else { return nil }
        return songKey(artist: artist, title: title, identity: identity)
      }
    })
    let keyedPlays = log.plays.map { (windowEnd: $0.windowEnd, key: songKey(artist: $0.item.artist, title: $0.item.title, identity: identity)) }
    return Array(weeks.sorted { $0.lastModifiedDate > $1.lastModifiedDate }.prefix(max(1, limit))).map { week in
      let windowEnd = week.lastModifiedDate.addingTimeInterval(14 * 86_400)
      let completed = now >= windowEnd && snapshot.generatedAt >= windowEnd
      let heardKeys = Set(keyedPlays.lazy.filter { $0.windowEnd >= week.lastModifiedDate && $0.windowEnd <= windowEnd }.map(\.key))
      var rows = week.tracks.map { track -> ClassifiedNewMusicTrack in
        let key = songKey(artist: track.artist, title: track.title, identity: identity)
        let heard = heardKeys.contains(key)
        let status: NewMusicClassification = keepKeys.contains(key) ? .kept : (completed ? (heard ? .passed : .unheard) : .pending)
        return ClassifiedNewMusicTrack(track: track, classification: status)
      }
      let order: [NewMusicClassification] = [.kept, .passed, .unheard, .pending]
      rows.sort { (order.firstIndex(of: $0.classification) ?? 0) < (order.firstIndex(of: $1.classification) ?? 0) }
      var counts: [String: Int] = [:]
      for row in rows { counts[row.classification.rawValue, default: 0] += 1 }
      return NewMusicWeekResult(lastModifiedDate: week.lastModifiedDate, fetchedAt: week.fetchedAt, counts: counts, tracks: rows)
    }
  }

  public static func baselines(weeks: [NewMusicWeekResult], snapshot: LibrarySnapshot) -> TasteBaselines {
    let finished = weeks.filter { $0.counts[NewMusicClassification.pending.rawValue, default: 0] == 0 }
    let weekly = Dictionary(uniqueKeysWithValues: finished.map { week in
      (week.lastModifiedDate.ISO8601Format(), TasteBaselines.Yield(kept: week.counts["kept", default: 0], passed: week.counts["passed", default: 0]))
    })
    let total = TasteBaselines.Yield(kept: finished.reduce(0) { $0 + $1.counts["kept", default: 0] }, passed: finished.reduce(0) { $0 + $1.counts["passed", default: 0] })
    let playlists = Dictionary(snapshot.playlists.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    let tracks = Dictionary(snapshot.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let artists = Set(snapshot.tracks.map(\.artist) + snapshot.outsideTracks.values.map(\.artist))
    let identity = ArtistIdentity(knownArtists: artists)
    let replayByYear = Dictionary(grouping: snapshot.playlists.compactMap { playlist -> (Int, Set<String>)? in
      guard let match = playlist.name.range(of: #"^Replay \d{4}$"#, options: .regularExpression),
        let year = Int(playlist.name[match].split(separator: " ").last ?? "0") else { return nil }
      return (year, Set(playlist.members))
    }, by: \.0).mapValues { values in values.reduce(into: Set<String>()) { $0.formUnion($1.1) } }
    let currentYear = Calendar.current.component(.year, from: snapshot.generatedAt)
    let rates = (2021...max(2021, currentYear)).map { year -> TasteBaselines.StickRate in
      guard let selections = playlists.values.first(where: { $0.name.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil && $0.name.hasPrefix("\(year):") }) else { return .init(year: year, selections: 0, returned: 0) }
      let songs = Set(selections.members.compactMap { id -> String? in
        let track = tracks[id]
        let outside = snapshot.outsideTracks[id]
        guard let artist = track?.artist ?? outside?.artist,
          let title = track?.name ?? outside?.name else { return nil }
        return songKey(artist: artist, title: title, identity: identity)
      })
      let replayIDs = (replayByYear[year] ?? []).union(replayByYear[year + 1] ?? [])
      let replayKeys = Set(replayIDs.compactMap { id -> String? in
        let track = tracks[id]
        let outside = snapshot.outsideTracks[id]
        guard let artist = track?.artist ?? outside?.artist,
          let title = track?.name ?? outside?.name else { return nil }
        return songKey(artist: artist, title: title, identity: identity)
      })
      let count = songs.filter { key in
        replayKeys.contains(key)
      }.count
      return .init(year: year, selections: songs.count, returned: count)
    }
    return TasteBaselines(weeklyYield: weekly, overallYield: total, stickRates: rates,
      pendingWeeks: weeks.filter { $0.counts[NewMusicClassification.pending.rawValue, default: 0] > 0 }.count)
  }
}
