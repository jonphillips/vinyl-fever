import Foundation
import VinylFeverListening

public enum LibraryRanking: Equatable, Sendable {
  case plays, favorites, recentlyAdded, recentlyPlayed
}
public enum LibrarySort: Equatable, Sendable {
  case plays, favorites, recentlyAdded, recentlyPlayed, title, artist
}

public struct LibrarySearchFilter: Equatable, Sendable {
  public var artist: String? = nil
  public var title: String? = nil
  public var album: String? = nil
  public var genre: String? = nil
  public var yearFrom: Int? = nil
  public var yearTo: Int? = nil
  public var minPlays: Int? = nil
  public var maxPlays: Int? = nil
  public var favorited: Bool? = nil
  public var availability: LibraryAvailability? = nil
  public init() {}
}

public struct LibraryArtistSummary: Codable, Equatable, Sendable {
  public var artist: String
  public var plays: Int
  public var favorites: Int
  public var trackCount: Int
  public var lastPlayed: Date?
  public var lastAdded: Date?
}
public struct LibraryOverview: Codable, Equatable, Sendable {
  public var generatedAt: Date
  public var trackCount: Int
  public var artistCount: Int
  public var albumCount: Int
  public var genreCounts: [String: Int]
  public var decadeCounts: [Int: Int]
  public var topArtists: [LibraryArtistSummary]
}
public struct LibraryArtistProfile: Codable, Equatable, Sendable {
  public var artist: String
  public var albums: [String]
  public var trackCount: Int
  public var totalPlays: Int
  public var favorites: Int
  public var firstAdded: Date?
  public var lastPlayed: Date?
  public var mostPlayedTracks: [LibraryTrack]
  public var uploadedTrackCount: Int
}
public struct LibraryTrackCheck: Codable, Equatable, Sendable {
  public var artist: String
  public var title: String
  public var owned: Bool
  public var plays: Int
  public var versionCount: Int
  public var favorited: Bool
  public var lastPlayed: Date?
  public var availability: [LibraryAvailability]
  public var uploadedAlbums: [String]
}

/// An immutable, pre-indexed view of a snapshot. Query methods are deterministic and capped.
public struct LibraryIndex: Sendable {
  public static let defaultLimit = 50
  public static let maximumLimit = 200
  public static let maximumCheckTracks = 200

  private let tracks: [LibraryTrack]
  private let bySong: [String: [LibraryTrack]]
  private let uploadedByTitle: [String: [UploadedTrackEntry]]
  public let artistIdentity: ArtistIdentity
  private let artistKeys: [String: String]
  private let artistCredits: [String: Set<String>]

  private struct UploadedTrackEntry: Sendable {
    var track: LibraryTrack
    var normalizedTitle: String
    var normalizedArtist: String
    var normalizedAlbum: String
  }

  public init(snapshot: LibrarySnapshot, aliases: [String: String] = [:]) {
    tracks = snapshot.tracks
    let knownArtists = Set(snapshot.tracks.map(\.artist))
    let artistNames = Set(snapshot.tracks.flatMap { [$0.artist, $0.albumArtist] })
    let identity = ArtistIdentity(aliases: aliases, knownArtists: knownArtists)
    let keys = Dictionary(uniqueKeysWithValues: artistNames.map { ($0, identity.key($0)) })
    let credits = Dictionary(uniqueKeysWithValues: artistNames.map { ($0, identity.credits($0)) })
    artistIdentity = identity
    artistKeys = keys
    artistCredits = credits
    bySong = Dictionary(grouping: snapshot.tracks.flatMap { track in
      (credits[track.artist] ?? [identity.key(track.artist)]).map {
        (key: "\($0)|\(SongTextNormalizer.libraryTitle(track.name))", track: track)
      }
    }, by: \.key).mapValues { $0.map(\.track) }
    uploadedByTitle = Dictionary(grouping: snapshot.tracks.compactMap { track in
      guard track.availability == .uploaded else { return nil }
      return UploadedTrackEntry(
        track: track,
        normalizedTitle: SongTextNormalizer.title(track.name),
        normalizedArtist: track.artist,
        normalizedAlbum: SongTextNormalizer.album(track.album))
    }, by: \.normalizedTitle)
  }

  public func shouldUseLibraryRoute(_ request: TrackRequest) -> Bool {
    guard let album = request.album, !album.isEmpty else { return false }
    let title = SongTextNormalizer.title(request.title)
    let artist = request.artist
    let albumKey = SongTextNormalizer.album(album)
    return (uploadedByTitle[title] ?? []).contains { entry in
      entry.normalizedAlbum == albumKey
        && artistIdentity.matches(request: artist, track: entry.normalizedArtist)
    }
  }

  public func uploadedCandidates(
    _ request: TrackRequest, limit: Int = LibraryUploadMatcher.uploadPickerLimit,
    requiringNamedAlbum: Bool = false
  )
    -> [CatalogSongCandidate]
  {
    let artist = request.artist
    var albums: Set<String> = []
    return (uploadedByTitle[SongTextNormalizer.title(request.title)] ?? [])
      .filter { artistIdentity.matches(request: artist, track: $0.normalizedArtist) }
      .filter { !requiringNamedAlbum || !$0.normalizedAlbum.isEmpty }
      .sorted { lhs, rhs in
        lhs.track.playCount == rhs.track.playCount
          ? lhs.normalizedAlbum.localizedStandardCompare(rhs.normalizedAlbum) == .orderedAscending
          : lhs.track.playCount > rhs.track.playCount
      }
      .filter { albums.insert($0.normalizedAlbum).inserted }
      .prefix(max(limit, 0))
      .map { entry in
        CatalogSongCandidate(
          id: entry.track.persistentID, title: entry.track.name, artistName: entry.track.artist,
          albumTitle: entry.track.album, source: .libraryUpload)
      }
  }

  public func overview(generatedAt: Date) -> LibraryOverview {
    let groups = artistGroups()
    let genres = Dictionary(grouping: tracks.compactMap { nonempty($0.genre)?.trimmingCharacters(in: .whitespacesAndNewlines) }, by: { $0 })
      .mapValues(\.count)
      .filter { !$0.key.isEmpty }
      .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending : lhs.value > rhs.value }
      .prefix(25)
      .reduce(into: [String: Int]()) { $0[$1.key] = $1.value }
    let latestYear = Calendar.current.component(.year, from: Date()) + 1
    let decades = Dictionary(
      grouping: tracks.compactMap { track -> Int? in
        guard let year = track.year, (1900...latestYear).contains(year) else { return nil }
        return year / 10 * 10
      }, by: { $0 }
    ).mapValues(\.count)
    return LibraryOverview(
      generatedAt: generatedAt, trackCount: tracks.count,
      artistCount: Set(tracks.compactMap { artistKeys[$0.artist] }.filter { !$0.isEmpty })
        .count,
      albumCount: Set(
        tracks.map {
          "\(artistKeys[$0.albumArtist.isEmpty ? $0.artist : $0.albumArtist] ?? artistIdentity.key($0.albumArtist.isEmpty ? $0.artist : $0.albumArtist))|\(SongTextNormalizer.album($0.album))"
        }
      ).count,
      genreCounts: genres, decadeCounts: decades,
      topArtists: Array(sortedArtists(groups, by: .plays).prefix(10)))
  }

  public func topArtists(by ranking: LibraryRanking = .plays, limit: Int = defaultLimit)
    -> [LibraryArtistSummary]
  {
    Array(sortedArtists(artistGroups(), by: ranking).prefix(Self.cap(limit)))
  }

  public func topTracks(by ranking: LibraryRanking = .plays, limit: Int = defaultLimit)
    -> [LibraryTrack]
  {
    Array(sortedTracks(tracks, by: ranking).prefix(Self.cap(limit)))
  }

  public func search(
    _ filter: LibrarySearchFilter = .init(), sort: LibrarySort = .plays, limit: Int = defaultLimit
  ) -> [LibraryTrack] {
    let matches = tracks.filter { track in
      match(filter.artist, in: track.artist) && match(filter.title, in: track.name)
        && match(filter.album, in: track.album) && match(filter.genre, in: track.genre ?? "")
        && (filter.yearFrom == nil || (track.year ?? Int.min) >= filter.yearFrom!)
        && (filter.yearTo == nil || (track.year ?? Int.max) <= filter.yearTo!)
        && (filter.minPlays == nil || track.playCount >= filter.minPlays!)
        && (filter.maxPlays == nil || track.playCount <= filter.maxPlays!)
        && (filter.favorited == nil || track.favorited == filter.favorited!)
        && (filter.availability == nil || track.availability == filter.availability!)
    }
    return Array(sortedTracks(matches, by: sort).prefix(Self.cap(limit)))
  }

  public func artistProfile(_ artist: String) -> LibraryArtistProfile? {
    let artistKey = artistIdentity.key(artist)
    let owned = tracks.filter {
      (artistCredits[$0.artist] ?? [artistIdentity.key($0.artist)]).contains(artistKey)
        || (artistCredits[$0.albumArtist] ?? [artistIdentity.key($0.albumArtist)]).contains(artistKey)
    }
    guard !owned.isEmpty else { return nil }
    return LibraryArtistProfile(
      artist: artist, albums: Array(Set(owned.map(\.album).filter { !$0.isEmpty })).sorted(),
      trackCount: owned.count, totalPlays: owned.reduce(0) { $0 + $1.playCount },
      favorites: owned.filter(\.favorited).count,
      firstAdded: owned.compactMap(\.dateAdded).min(),
      lastPlayed: owned.compactMap(\.lastPlayed).max(),
      mostPlayedTracks: Array(sortedTracks(owned, by: LibraryRanking.plays).prefix(10)),
      uploadedTrackCount: owned.filter { $0.availability == .uploaded }.count)
  }

  public func checkTracks(_ requests: [(artist: String, title: String)]) -> [LibraryTrackCheck] {
    requests.prefix(Self.maximumCheckTracks).map { request in
      let matches = bySong[songKey(artist: request.artist, title: request.title)] ?? []
      return LibraryTrackCheck(
        artist: request.artist, title: request.title, owned: !matches.isEmpty,
        plays: matches.reduce(0) { $0 + $1.playCount }, versionCount: matches.count,
        favorited: matches.contains(where: \.favorited),
        lastPlayed: matches.compactMap(\.lastPlayed).max(),
        availability: Array(Set(matches.map(\.availability))).sorted { $0.rawValue < $1.rawValue },
        uploadedAlbums: uploadedCandidates(
          TrackRequest(index: 1, artist: request.artist, title: request.title), limit: 5,
          requiringNamedAlbum: true
        ).compactMap(\.albumTitle))
    }
  }

  public func annotation(
    artist: String, title: String, candidateArtist: String? = nil, candidateTitle: String? = nil,
    snapshotAvailable: Bool = true
  ) -> LibraryAnnotation {
    guard snapshotAvailable else { return .snapshotUnavailable }
    var matches = bySong[songKey(artist: artist, title: title)] ?? []
    if let candidateArtist, let candidateTitle,
      artistIdentity.key(candidateArtist) != artistIdentity.key(artist)
        || SongTextNormalizer.title(candidateTitle) != SongTextNormalizer.title(title)
    {
      matches += bySong[songKey(artist: candidateArtist, title: candidateTitle)] ?? []
    }
    guard !matches.isEmpty else { return .notInLibrary }
    return .inLibrary(
      plays: matches.reduce(0) { $0 + $1.playCount },
      lastPlayed: matches.compactMap(\.lastPlayed).max(),
      favorited: matches.contains(where: \.favorited), versionCount: matches.count)
  }

  private func songKey(artist: String, title: String) -> String {
    "\(artistIdentity.key(artist))|\(SongTextNormalizer.libraryTitle(title))"
  }
  private static func cap(_ limit: Int) -> Int { min(max(1, limit), maximumLimit) }
  private func nonempty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
  }
  private func match(_ query: String?, in value: String) -> Bool {
    query.map { SongTextNormalizer.text(value).contains(SongTextNormalizer.text($0)) } ?? true
  }

  private func artistGroups() -> [LibraryArtistSummary] {
    Dictionary(grouping: tracks, by: { artistKeys[$0.artist] ?? artistIdentity.key($0.artist) }).map { key, tracks in
      LibraryArtistSummary(
        artist: tracks.first?.artist ?? key, plays: tracks.reduce(0) { $0 + $1.playCount },
        favorites: tracks.filter(\.favorited).count, trackCount: tracks.count,
        lastPlayed: tracks.compactMap(\.lastPlayed).max(),
        lastAdded: tracks.compactMap(\.dateAdded).max())
    }
  }
  private func sortedArtists(_ values: [LibraryArtistSummary], by ranking: LibraryRanking)
    -> [LibraryArtistSummary]
  {
    values.sorted { lhs, rhs in
      let left: Int
      let right: Int
      switch ranking {
      case .plays:
        left = lhs.plays
        right = rhs.plays
      case .favorites:
        left = lhs.favorites
        right = rhs.favorites
      case .recentlyAdded:
        let leftDate = lhs.lastAdded ?? .distantPast
        let rightDate = rhs.lastAdded ?? .distantPast
        return leftDate == rightDate
          ? lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending
          : leftDate > rightDate
      case .recentlyPlayed:
        return (lhs.lastPlayed ?? .distantPast) == (rhs.lastPlayed ?? .distantPast)
          ? lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending
          : (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast)
      }
      return left == right
        ? lhs.artist.localizedStandardCompare(rhs.artist) == .orderedAscending : left > right
    }
  }
  private func sortedTracks(_ values: [LibraryTrack], by ranking: LibraryRanking) -> [LibraryTrack]
  {
    values.sorted { lhs, rhs in
      switch ranking {
      case .plays:
        return lhs.playCount == rhs.playCount
          ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
          : lhs.playCount > rhs.playCount
      case .favorites:
        return lhs.favorited == rhs.favorited
          ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.favorited
      case .recentlyAdded:
        return (lhs.dateAdded ?? .distantPast) == (rhs.dateAdded ?? .distantPast)
          ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
          : (lhs.dateAdded ?? .distantPast) > (rhs.dateAdded ?? .distantPast)
      case .recentlyPlayed:
        return (lhs.lastPlayed ?? .distantPast) == (rhs.lastPlayed ?? .distantPast)
          ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
          : (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast)
      }
    }
  }
  private func sortedTracks(_ values: [LibraryTrack], by sort: LibrarySort) -> [LibraryTrack] {
    let ranking: LibraryRanking =
      switch sort {
      case .plays: .plays
      case .favorites: .favorites
      case .recentlyAdded: .recentlyAdded
      case .recentlyPlayed: .recentlyPlayed
      case .title: .recentlyAdded
      case .artist: .recentlyAdded
      }
    if sort == .title {
      return values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        .prefix(Self.maximumLimit).map { $0 }
    }
    if sort == .artist {
      return values.sorted { $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
        .prefix(Self.maximumLimit).map { $0 }
    }
    return sortedTracks(values, by: ranking)
  }
}
