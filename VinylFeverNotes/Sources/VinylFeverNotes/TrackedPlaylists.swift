import Foundation

public struct TrackedPlaylistTrack: Codable, Equatable, Sendable, Identifiable {
  public var catalogID: String
  public var title: String
  public var artist: String
  public var album: String?
  public var releaseDate: String?
  public var dateAdded: Date?
  public var id: String { catalogID }

  public init(catalogID: String, title: String, artist: String, album: String? = nil,
    releaseDate: String? = nil, dateAdded: Date? = nil) {
    self.catalogID = catalogID; self.title = title; self.artist = artist; self.album = album
    self.releaseDate = releaseDate; self.dateAdded = dateAdded
  }
}

public struct TrackedPlaylistSnapshot: Codable, Equatable, Sendable {
  public var format = "vf-tracked-playlist"
  public var version = 1
  public var name: String
  public var catalogID: String
  public var lastModifiedDate: Date
  public var fetchedAt: Date
  public var host: String
  public var tracks: [TrackedPlaylistTrack]

  public init(name: String, catalogID: String, lastModifiedDate: Date, fetchedAt: Date,
    host: String, tracks: [TrackedPlaylistTrack]) {
    self.name = name; self.catalogID = catalogID; self.lastModifiedDate = lastModifiedDate
    self.fetchedAt = fetchedAt; self.host = host; self.tracks = tracks
  }
}

public struct TrackedPlaylistGap: Codable, Equatable, Sendable {
  public var format = "vf-tracked-playlist-gap"
  public var version = 1
  public var name: String
  public var fetchedAt: Date
  public var host: String
  public var detail: String

  public init(name: String, fetchedAt: Date, host: String, detail: String) {
    self.name = name; self.fetchedAt = fetchedAt; self.host = host; self.detail = detail
  }
}

public enum TrackedPlaylistRecord: Equatable, Sendable {
  case snapshot(TrackedPlaylistSnapshot)
  case gap(TrackedPlaylistGap)
}

public enum TrackedPlaylistExposureCodec {
  public static func encode(_ value: TrackedPlaylistSnapshot) throws -> Data { try line(value) }
  public static func encode(_ value: TrackedPlaylistGap) throws -> Data { try line(value) }

  public static func readFiles(_ files: [Data]) -> [TrackedPlaylistRecord] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return files.flatMap { data -> [TrackedPlaylistRecord] in
      String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { raw in
        let line = Data(raw.utf8)
        let header = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        switch (header?["format"] as? String, header?["version"] as? Int) {
        case ("vf-tracked-playlist", 1):
          return (try? decoder.decode(TrackedPlaylistSnapshot.self, from: line)).map(TrackedPlaylistRecord.snapshot)
        case ("vf-tracked-playlist-gap", 1):
          return (try? decoder.decode(TrackedPlaylistGap.self, from: line)).map(TrackedPlaylistRecord.gap)
        default: return nil
        }
      }
    }
  }

  private static func line<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value) + Data([0x0A])
  }
}

public struct PlaylistCatchupSong: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var artist: String
  public var album: String?
  public var releaseDate: String?
  public var dateAdded: Date?
  public var sources: [String]

  public init(id: String, title: String, artist: String, album: String?, releaseDate: String?,
    dateAdded: Date?, sources: [String]) {
    self.id = id; self.title = title; self.artist = artist; self.album = album
    self.releaseDate = releaseDate; self.dateAdded = dateAdded; self.sources = sources
  }
}

public enum PlaylistCatchup {
  public static func make(
    snapshots: [TrackedPlaylistSnapshot],
    heardTrackKeys: Set<String>,
    keeperTrackKeys: Set<String>,
    currentWeeklyCatalogIDs: Set<String> = [],
    currentWeeklyTrackKeys: Set<String> = [],
    identity: ArtistIdentity = .empty
  ) -> [PlaylistCatchupSong] {
    let latestSnapshots = Dictionary(grouping: snapshots, by: \.name).values.compactMap {
      $0.max { $0.fetchedAt < $1.fetchedAt }
    }
    var byCatalogID: [String: PlaylistCatchupSong] = [:]
    for snapshot in latestSnapshots {
      for track in snapshot.tracks {
        let key = ListeningTextNormalizer.trackKey(artist: track.artist, title: track.title)
        guard !heardTrackKeys.contains(key), !keeperTrackKeys.contains(key),
          !currentWeeklyCatalogIDs.contains(track.catalogID), !currentWeeklyTrackKeys.contains(key)
        else { continue }
        if var existing = byCatalogID[track.catalogID] {
          existing.sources.append(snapshot.name)
          byCatalogID[track.catalogID] = existing
        } else {
          byCatalogID[track.catalogID] = PlaylistCatchupSong(
            id: track.catalogID, title: track.title, artist: track.artist, album: track.album,
            releaseDate: track.releaseDate, dateAdded: track.dateAdded, sources: [snapshot.name])
        }
      }
    }

    var byText: [String: PlaylistCatchupSong] = [:]
    for song in byCatalogID.values {
      let key = "\(identity.key(song.artist))|\(ListeningTextNormalizer.libraryTitle(song.title))"
      if var existing = byText[key] {
        existing.sources = Array(Set(existing.sources + song.sources)).sorted()
        let songDate = Self.sortDate(song)
        let existingDate = Self.sortDate(existing)
        if songDate > existingDate || (songDate == existingDate && song.id < existing.id) {
          existing.id = song.id
          existing.title = song.title
          existing.artist = song.artist
          existing.album = song.album
          existing.releaseDate = song.releaseDate
          existing.dateAdded = song.dateAdded
        }
        byText[key] = existing
      } else {
        var song = song
        song.sources = Array(Set(song.sources)).sorted()
        byText[key] = song
      }
    }

    return byText.values.map { (song: $0, date: Self.sortDate($0)) }.sorted { lhs, rhs in
      if lhs.date != rhs.date { return lhs.date > rhs.date }
      return lhs.song.title.localizedStandardCompare(rhs.song.title) == .orderedAscending
    }.map(\.song)
  }

  public static func filtered(_ songs: [PlaylistCatchupSong], source: String?) -> [PlaylistCatchupSong] {
    guard let source else { return songs }
    return songs.filter { $0.sources.contains(source) }
  }

  public static func sources(in songs: [PlaylistCatchupSong]) -> [String] {
    Array(Set(songs.flatMap(\.sources))).sorted()
  }

  /// Newest first: the date added where the API gave one, the release date otherwise.
  private static func sortDate(_ song: PlaylistCatchupSong) -> Date {
    song.dateAdded ?? date(song.releaseDate) ?? .distantPast
  }

  private static func date(_ value: String?) -> Date? {
    guard let value else { return nil }
    if value.count == 10 {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      if let date = formatter.date(from: value) { return date }
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}
