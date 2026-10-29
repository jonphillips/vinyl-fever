#if os(macOS)
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
public enum ReleaseAgeBand: String, Codable, CaseIterable, Sendable { case new, recent, catalog, unknown }
public struct RecommendationOutcomeSong: Codable, Equatable, Sendable {
  public var artist: String; public var title: String; public var year: Int?
  public var band: ReleaseAgeBand; public var classification: NewMusicClassification?
  public var why: String?; public var like: [RecommendationLike]?
  public var picked: Bool?
}
public struct RecommendationOutcomeBatch: Codable, Equatable, Sendable {
  public var recordedAt: Date; public var kind: String; public var source: String
  public var playlist: String?
  public var songs: [RecommendationOutcomeSong]; public var notCounted: [String]
  public var counts: [String: Int]; public var pickedCounts: [String: Int]?
  public var notPickedCounts: [String: Int]?; public var notScored: String?
}
public struct RecommendationOutcomes: Codable, Equatable, Sendable {
  public var batches: [RecommendationOutcomeBatch]; public var skippedLines: Int
  public var listeningCoverage: ListeningCoverage?; public var snapshotAge: TimeInterval
}
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
  public struct StickRate: Codable, Equatable, Sendable { public var year: Int; public var selections: Int; public var returned: Int; public var excludedLateAdds: Int = 0; public var ratio: Double? { selections == 0 ? nil : Double(returned) / Double(selections) } }
  public struct OutcomeCell: Codable, Equatable, Sendable {
    public var kept: Int; public var passed: Int
    public init(kept: Int, passed: Int) { self.kept = kept; self.passed = passed }
    public var ratio: Double? { kept + passed < 10 ? nil : Double(kept) / Double(kept + passed) }
    private enum CodingKeys: String, CodingKey { case kept, passed, ratio }
    public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      kept = try values.decode(Int.self, forKey: .kept); passed = try values.decode(Int.self, forKey: .passed)
    }
    public func encode(to encoder: Encoder) throws {
      var values = encoder.container(keyedBy: CodingKeys.self)
      try values.encode(kept, forKey: .kept); try values.encode(passed, forKey: .passed)
      try values.encodeIfPresent(ratio, forKey: .ratio)
    }
  }
  public struct PickYield: Codable, Equatable, Sendable { public var picked: OutcomeCell; public var notPicked: OutcomeCell }
  public var weeklyYield: [String: Yield]
  public var appleNewMusicOverallYield: Yield
  public var overallYield: Yield { appleNewMusicOverallYield }
  public var stickRates: [StickRate]
  public var pendingWeeks: Int
  public var bySourceAndBand: [String: OutcomeCell]
  public var picksByWeek: [String: PickYield]
}

public enum TasteIntelligence {
  private struct ClassificationIndex {
    var identity: ArtistIdentity
    var keepKeys: Set<String>
    var heardKeysByWindow: [Date: Set<String>]
  }

  public static func songKey(artist: String, title: String, identity: ArtistIdentity) -> String {
    "\(identity.key(artist))|\(ListeningTextNormalizer.libraryTitle(title))"
  }

  public static func keptAndPassed(weeks: [NewMusicWeek], snapshot: LibrarySnapshot,
    roles: PlaylistRoles, log: ListeningLog, now: Date, limit: Int = 8) -> [NewMusicWeekResult] {
    let selectedWeeks = Array(weeks.sorted { $0.lastModifiedDate > $1.lastModifiedDate }.prefix(max(1, limit)))
    let classifier = classificationIndex(snapshot: snapshot, roles: roles, log: log,
      dates: selectedWeeks.map(\.lastModifiedDate))
    return selectedWeeks.map { classifyWeek($0, snapshot: snapshot, classifier: classifier, now: now) }
  }

  private static func classificationIndex(snapshot: LibrarySnapshot, roles: PlaylistRoles,
    log: ListeningLog, dates: [Date]) -> ClassificationIndex {
    let artists = Set(snapshot.tracks.map(\.artist) + snapshot.outsideTracks.values.map(\.artist))
    let identity = ArtistIdentity(knownArtists: artists)
    let keepKeys = keepKeys(snapshot: snapshot, roles: roles, identity: identity)
    let keyedPlays = log.plays.map { (windowEnd: $0.windowEnd,
      key: songKey(artist: $0.item.artist, title: $0.item.title, identity: identity)) }
    return ClassificationIndex(identity: identity, keepKeys: keepKeys,
      heardKeysByWindow: heardKeysByWindow(dates: dates, keyedPlays: keyedPlays))
  }

  private static func heardKeysByWindow(dates: [Date], keyedPlays: [(windowEnd: Date, key: String)]) -> [Date: Set<String>] {
    let orderedDates = Array(Set(dates)).sorted()
    var values = Array(repeating: Set<String>(), count: orderedDates.count)
    for play in keyedPlays {
      let earliestDate = play.windowEnd.addingTimeInterval(-14 * 86_400)
      var lower = 0
      var upper = orderedDates.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if orderedDates[middle] < earliestDate { lower = middle + 1 } else { upper = middle }
      }
      let firstDate = lower
      lower = firstDate
      upper = orderedDates.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if orderedDates[middle] <= play.windowEnd { lower = middle + 1 } else { upper = middle }
      }
      for index in firstDate..<lower {
        values[index].insert(play.key)
      }
    }
    return Dictionary(uniqueKeysWithValues: zip(orderedDates, values))
  }

  private static func classifyWeek(_ week: NewMusicWeek, snapshot: LibrarySnapshot,
    classifier: ClassificationIndex, now: Date) -> NewMusicWeekResult {
    let heardKeys = classifier.heardKeysByWindow[week.lastModifiedDate] ?? []
    var rows = week.tracks.map { track -> ClassifiedNewMusicTrack in
      let status = classify(artist: track.artist, title: track.title, date: week.lastModifiedDate,
        snapshot: snapshot, keepKeys: classifier.keepKeys, heardKeys: heardKeys, identity: classifier.identity, now: now)
      return ClassifiedNewMusicTrack(track: track, classification: status)
    }
    let order: [NewMusicClassification] = [.kept, .passed, .unheard, .pending]
    rows.sort { (order.firstIndex(of: $0.classification) ?? 0) < (order.firstIndex(of: $1.classification) ?? 0) }
    var counts: [String: Int] = [:]
    for row in rows { counts[row.classification.rawValue, default: 0] += 1 }
    return NewMusicWeekResult(lastModifiedDate: week.lastModifiedDate, fetchedAt: week.fetchedAt,
      counts: counts, tracks: rows)
  }

  private static func classify(artist: String, title: String, date: Date, snapshot: LibrarySnapshot,
    keepKeys: Set<String>, heardKeys: Set<String>, identity: ArtistIdentity, now: Date) -> NewMusicClassification {
    let key = songKey(artist: artist, title: title, identity: identity)
    let windowEnd = date.addingTimeInterval(14 * 86_400)
    guard !keepKeys.contains(key) else { return .kept }
    guard now >= windowEnd && snapshot.generatedAt >= windowEnd else { return .pending }
    return heardKeys.contains(key) ? .passed : .unheard
  }

  public static func band(releaseYear: Int?, batchYear: Int?) -> ReleaseAgeBand {
    guard let releaseYear, let batchYear else { return .unknown }
    if releaseYear >= batchYear - 1 && releaseYear <= batchYear { return .new }
    if releaseYear >= batchYear - 5 && releaseYear <= batchYear - 2 { return .recent }
    if releaseYear < batchYear - 5 { return .catalog }
    return .unknown
  }

  public static func recommendationOutcomes(ledger: RecommendationLedgerReadResult, weeks: [NewMusicWeek],
    snapshot: LibrarySnapshot, roles: PlaylistRoles, log: ListeningLog, now: Date, limit: Int = 10) -> RecommendationOutcomes {
    let sorted = Array(ledger.batches.sorted { $0.recordedAt > $1.recordedAt }.prefix(max(1, limit)))
    let needsWeekClassifications = sorted.contains { $0.kind == "new-music-picks" }
    let dates = (needsWeekClassifications ? weeks.map(\.lastModifiedDate) : []) + sorted.map { $0.batchDate ?? $0.recordedAt }
    let classifier = classificationIndex(snapshot: snapshot, roles: roles, log: log, dates: dates)
    var resultByDate: [Date: NewMusicWeekResult] = [:]
    if needsWeekClassifications {
      for week in weeks { resultByDate[week.lastModifiedDate] = classifyWeek(week, snapshot: snapshot, classifier: classifier, now: now) }
    }
    let identity = classifier.identity
    var batches: [RecommendationOutcomeBatch] = []
    for batch in sorted {
      let date = batch.batchDate ?? batch.recordedAt
      let year = Calendar.current.component(.year, from: date)
      let familiar = batch.tracks.filter(\.familiar).map { "\($0.artist) — \($0.title)" }
      let scored = batch.coverage?.listening != false
      var rows: [RecommendationOutcomeSong] = []
      for track in batch.tracks where !track.familiar && track.heardBeforePick != true {
        let status: NewMusicClassification?
        if batch.kind == "new-music-picks", let week = resultByDate[date] {
          let trackKey = songKey(artist: track.artist, title: track.title, identity: identity)
          status = week.tracks.first { songKey(artist: $0.track.artist, title: $0.track.title, identity: identity) == trackKey }?.classification
        } else {
          status = classify(artist: track.artist, title: track.title, date: date, snapshot: snapshot,
            keepKeys: classifier.keepKeys, heardKeys: classifier.heardKeysByWindow[date] ?? [], identity: identity, now: now)
        }
        rows.append(RecommendationOutcomeSong(artist: track.artist, title: track.title, year: track.year,
          band: band(releaseYear: track.year, batchYear: year), classification: status, why: track.why,
          like: track.like, picked: batch.kind == "new-music-picks" ? track.picked : nil))
      }
      var counts: [String: Int] = [:]
      var pickedCounts: [String: Int] = [:]; var notPickedCounts: [String: Int] = [:]
      for row in rows { if let status = row.classification { counts[status.rawValue, default: 0] += 1 } }
      if batch.kind == "new-music-picks" {
        for row in rows {
          guard let status = row.classification, status == .kept || status == .passed else { continue }
          if row.picked == true { pickedCounts[status.rawValue, default: 0] += 1 }
          else { notPickedCounts[status.rawValue, default: 0] += 1 }
        }
      }
      batches.append(RecommendationOutcomeBatch(recordedAt: batch.recordedAt, kind: batch.kind, source: batch.source,
        playlist: batch.playlist, songs: rows, notCounted: familiar, counts: counts,
        pickedCounts: batch.kind == "new-music-picks" ? pickedCounts : nil,
        notPickedCounts: batch.kind == "new-music-picks" ? notPickedCounts : nil,
        notScored: scored ? nil : "no listening evidence at staging")
      )
    }
    return RecommendationOutcomes(batches: Array(batches), skippedLines: ledger.skippedLines,
      listeningCoverage: log.coverage, snapshotAge: max(0, now.timeIntervalSince(snapshot.generatedAt)))
  }

  private static func keepKeys(snapshot: LibrarySnapshot, roles: PlaylistRoles, identity: ArtistIdentity) -> Set<String> {
    let resolved = PlaylistRoleMatcher.resolve(snapshot: snapshot, roles: roles)
    let tracks = Dictionary(snapshot.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    return Set(resolved.filter { $0.role == .keepers }.flatMap { row in row.playlist.members.compactMap { id in
      let track = tracks[id]; let outside = snapshot.outsideTracks[id]
      guard let artist = track?.artist ?? outside?.artist, let title = track?.name ?? outside?.name else { return nil }
      return songKey(artist: artist, title: title, identity: identity)
    } })
  }

  public static func baselines(weeks: [NewMusicWeekResult], snapshot: LibrarySnapshot,
    ledger: RecommendationLedgerReadResult? = nil, outcomes: RecommendationOutcomes? = nil,
    curation: [CurationChange] = []) -> TasteBaselines {
    let finished = weeks.filter { $0.counts[NewMusicClassification.pending.rawValue, default: 0] == 0 }
    let weekly = Dictionary(uniqueKeysWithValues: finished.map { week in
      (week.lastModifiedDate.ISO8601Format(), TasteBaselines.Yield(kept: week.counts["kept", default: 0], passed: week.counts["passed", default: 0]))
    })
    let total = TasteBaselines.Yield(kept: finished.reduce(0) { $0 + $1.counts["kept", default: 0] }, passed: finished.reduce(0) { $0 + $1.counts["passed", default: 0] })
    let artists = Set(snapshot.tracks.map(\.artist) + snapshot.outsideTracks.values.map(\.artist))
    let identity = ArtistIdentity(knownArtists: artists)
    let rates = selectionStickRates(snapshot: snapshot, identity: identity, curation: curation)
    let cells = outcomeCells(weeks: weeks, outcomes: outcomes)
    let picks = pickYields(weeks: weeks, ledger: ledger, identity: identity)
    return TasteBaselines(weeklyYield: weekly, appleNewMusicOverallYield: total, stickRates: rates,
      pendingWeeks: weeks.filter { $0.counts[NewMusicClassification.pending.rawValue, default: 0] > 0 }.count,
      bySourceAndBand: cells, picksByWeek: picks)
  }

  private static func selectionStickRates(snapshot: LibrarySnapshot, identity: ArtistIdentity,
    curation: [CurationChange]) -> [TasteBaselines.StickRate] {
    let tracks = Dictionary(snapshot.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
    let playlists = snapshot.playlists
    var replay: [Int: Set<String>] = [:]
    for playlist in playlists {
      guard playlist.name.hasPrefix("Replay "), let year = Int(playlist.name.dropFirst(7)) else { continue }
      replay[year, default: []].formUnion(playlist.members)
    }
    var added: [String: Date] = [:]
    for change in curation { for playlist in change.playlists where playlist.name.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil {
      for song in playlist.added {
        let key = songKey(artist: song.artist, title: song.title, identity: identity)
        added[key] = min(added[key] ?? change.observedAt, change.observedAt)
      }
    } }
    let currentYear = Calendar.current.component(.year, from: snapshot.generatedAt)
    var output: [TasteBaselines.StickRate] = []
    for year in 2021...max(2021, currentYear) {
      guard let selection = playlists.first(where: { $0.name.hasPrefix("\(year):") && $0.name.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil }) else {
        output.append(.init(year: year, selections: 0, returned: 0, excludedLateAdds: 0)); continue
      }
      var songs: Set<String> = []
      for id in selection.members {
        let track = tracks[id]; let outside = snapshot.outsideTracks[id]
        if let artist = track?.artist ?? outside?.artist, let title = track?.name ?? outside?.name {
          songs.insert(songKey(artist: artist, title: title, identity: identity))
        }
      }
      let cutoff = Calendar(identifier: .gregorian).date(from: DateComponents(year: year + 2, month: 1, day: 1)) ?? .distantFuture
      let late = Set(songs.filter { (added[$0] ?? .distantPast) >= cutoff })
      songs.subtract(late)
      var replayKeys: Set<String> = []
      for id in (replay[year] ?? []).union(replay[year + 1] ?? []) {
        let track = tracks[id]; let outside = snapshot.outsideTracks[id]
        if let artist = track?.artist ?? outside?.artist, let title = track?.name ?? outside?.name {
          replayKeys.insert(songKey(artist: artist, title: title, identity: identity))
        }
      }
      output.append(.init(year: year, selections: songs.count, returned: songs.intersection(replayKeys).count, excludedLateAdds: late.count))
    }
    return output
  }

  private static func outcomeCells(weeks: [NewMusicWeekResult], outcomes: RecommendationOutcomes?) -> [String: TasteBaselines.OutcomeCell] {
    var values: [String: [Int]] = [:]
    for source in ["apple-new-music", "chat"] { for age in ReleaseAgeBand.allCases { values["\(source)|\(age.rawValue)"] = [0, 0] } }
    for week in weeks {
      let year = Calendar.current.component(.year, from: week.lastModifiedDate)
      for row in week.tracks where row.classification == .kept || row.classification == .passed {
        let age = band(releaseYear: row.track.releaseDate.flatMap { Int($0.prefix(4)) }, batchYear: year)
        increment(values: &values, key: "apple-new-music|\(age.rawValue)", status: row.classification)
      }
    }
    for batch in outcomes?.batches ?? [] where batch.notScored == nil { for song in batch.songs {
      increment(values: &values, key: "chat|\(song.band.rawValue)", status: song.classification)
    } }
    return values.mapValues { .init(kept: $0[0], passed: $0[1]) }
  }

  private static func increment(values: inout [String: [Int]], key: String, status: NewMusicClassification?) {
    guard let status, status == .kept || status == .passed else { return }
    let index = status == .kept ? 0 : 1
    values[key, default: [0, 0]][index] += 1
  }

  private static func pickYields(weeks: [NewMusicWeekResult], ledger: RecommendationLedgerReadResult?,
    identity: ArtistIdentity) -> [String: TasteBaselines.PickYield] {
    var picks: [String: TasteBaselines.PickYield] = [:]
    let batches = (ledger?.batches ?? []).filter { $0.kind == "new-music-picks" }
      .sorted { $0.recordedAt < $1.recordedAt }
    var seenWeeks = Set<Date>()
    for batch in batches {
      let date = batch.batchDate ?? batch.recordedAt
      guard batch.coverage?.listening != false, seenWeeks.insert(date).inserted else { continue }
      guard let week = weeks.first(where: { $0.lastModifiedDate == date }) else { continue }
      var classified: [String: NewMusicClassification] = [:]
      for row in week.tracks { classified[songKey(artist: row.track.artist, title: row.track.title, identity: identity)] = row.classification }
      var yes = TasteBaselines.Yield(kept: 0, passed: 0); var no = TasteBaselines.Yield(kept: 0, passed: 0)
      for track in batch.tracks where track.heardBeforePick != true {
        guard let status = classified[songKey(artist: track.artist, title: track.title, identity: identity)] else { continue }
        if track.picked == true { if status == .kept { yes.kept += 1 }; if status == .passed { yes.passed += 1 } }
        else { if status == .kept { no.kept += 1 }; if status == .passed { no.passed += 1 } }
      }
      picks[date.ISO8601Format()] = .init(picked: .init(kept: yes.kept, passed: yes.passed),
        notPicked: .init(kept: no.kept, passed: no.passed))
    }
    return picks
  }
}
#endif
