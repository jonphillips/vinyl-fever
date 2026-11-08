import Foundation
import GRDB
import SQLiteData
import VinylFeverNotes

@Table("cachedBatch")
struct CachedBatch: Equatable, Identifiable, Sendable {
  var id: String { key }
  @Column(primaryKey: true)
  var key: String
  @Column("batch")
  var line: String

  var batch: RecommendationBatch? {
    RecommendationLedgerCodec.readFiles([Data(line.utf8)]).batches.first
  }
}

@Table("cachedCreationEvent")
struct CachedCreationEvent: Equatable, Identifiable, Sendable {
  var id: String { key }
  @Column(primaryKey: true)
  var key: String
  @Column("event")
  var line: String

  var event: PlaylistCreationEvent? {
    PlaylistCreationsCodec.readFiles([Data(line.utf8)]).events.first
  }
}

@Table("cachedLibraryPlaylist")
struct CachedLibraryPlaylist: Equatable, Identifiable, Sendable {
  @Column(primaryKey: true)
  var id: String
  var name: String
}

@Table("cachedSongProgress")
struct CachedSongProgress: Equatable, Identifiable, Sendable {
  var id: CachedSongProgressID
  var status: String
  @Column(as: [String].JSONRepresentation.self)
  var keptIn: [String]

  init(playlistID: String, songID: String, progress: PlaylistSongProgress) {
    id = CachedSongProgressID(playlistID: playlistID, songID: songID)
    switch progress {
    case let .kept(names):
      status = "kept"
      keptIn = names
    case let .passed(withFeedback):
      status = withFeedback ? "passedWithFeedback" : "passedWithoutFeedback"
      keptIn = []
    case .notHeard:
      status = "notHeard"
      keptIn = []
    }
  }

  var progress: PlaylistSongProgress? {
    switch status {
    case "kept": .kept(in: keptIn)
    case "passedWithFeedback": .passed(withFeedback: true)
    case "passedWithoutFeedback": .passed(withFeedback: false)
    case "notHeard": .notHeard
    default: nil
    }
  }
}

@Selection
struct CachedSongProgressID: Hashable, Sendable {
  var playlistID: String
  var songID: String
}

struct MobileShelfCache: Equatable {
  var batches: [RecommendationBatch]
  var creationEvents: [PlaylistCreationEvent]
  var libraryPlaylists: [KeepLibraryPlaylist]
  var progress: [String: PlaylistProgressResult]

  static let empty = MobileShelfCache(batches: [], creationEvents: [], libraryPlaylists: [], progress: [:])
}

enum ShelfCache {
  static func load(from database: any DatabaseReader) throws -> MobileShelfCache {
    try database.read { db in
      let batches = try CachedBatch.all.fetchAll(db).compactMap(\.batch)
      let events = try CachedCreationEvent.all.fetchAll(db).compactMap(\.event)
      let library = try CachedLibraryPlaylist.all.fetchAll(db).map {
        KeepLibraryPlaylist(id: $0.id, name: $0.name)
      }
      let songs = try CachedSongProgress.all.fetchAll(db)
      var progressByPlaylist: [String: [String: PlaylistSongProgress]] = [:]
      for row in songs {
        if let status = row.progress {
          progressByPlaylist[row.id.playlistID, default: [:]][row.id.songID] = status
        }
      }
      return MobileShelfCache(batches: batches, creationEvents: events, libraryPlaylists: library,
        progress: progressByPlaylist.mapValues(PlaylistProgressResult.init(songs:)))
    }
  }

  static func writeShelf(_ read: RecommendationLedgerFolderRead, to database: any DatabaseWriter) throws -> MobileShelfCache {
    let merged = try mergeShelf(read, with: load(from: database))
    try replaceShelf(merged, to: database)
    return merged
  }

  static func mergeShelf(_ read: RecommendationLedgerFolderRead, with cached: MobileShelfCache) -> MobileShelfCache {
    let clean = read.unreadableFileCount == 0 && read.ledger.skippedLines == 0
      && read.creations.unreadableFileCount == 0 && read.creations.skippedLines == 0
    var batches = clean ? [:] : Dictionary(uniqueKeysWithValues:
      cached.batches.map { (PlaylistCreationsCodec.batchKey(host: $0.host, recordedAt: $0.recordedAt), $0) })
    for batch in read.ledger.batches {
      batches[PlaylistCreationsCodec.batchKey(host: batch.host, recordedAt: batch.recordedAt)] = batch
    }
    var events = clean ? [:] : Dictionary(uniqueKeysWithValues:
      cached.creationEvents.map { (PlaylistCreationsCodec.batchKey(host: $0.host, recordedAt: $0.recordedAt), $0) })
    for event in read.creations.events {
      let key = PlaylistCreationsCodec.batchKey(host: event.host, recordedAt: event.recordedAt)
      if events[key].map({ $0.at < event.at }) ?? true { events[key] = event }
    }
    return MobileShelfCache(batches: Array(batches.values), creationEvents: Array(events.values),
      libraryPlaylists: cached.libraryPlaylists, progress: cached.progress)
  }

  static func writeShelf(_ cache: MobileShelfCache, to database: any DatabaseWriter) throws {
    try replaceShelf(cache, to: database)
  }

  static func replaceShelf(_ cache: MobileShelfCache, to database: any DatabaseWriter) throws {
    let batchRows = try cache.batches.map { batch in
      CachedBatch.Draft(
        key: PlaylistCreationsCodec.batchKey(host: batch.host, recordedAt: batch.recordedAt),
        line: String(decoding: try RecommendationLedgerCodec.encode(batch), as: UTF8.self)
      )
    }
    let eventRows = try cache.creationEvents.map { event in
      CachedCreationEvent.Draft(
        key: PlaylistCreationsCodec.batchKey(host: event.host, recordedAt: event.recordedAt),
        line: String(decoding: try PlaylistCreationsCodec.encode(event), as: UTF8.self)
      )
    }
    try database.write { db in
      try CachedBatch.delete().execute(db)
      try CachedBatch.insert { batchRows }.execute(db)
      try CachedCreationEvent.delete().execute(db)
      try CachedCreationEvent.insert { eventRows }.execute(db)
    }
  }

  static func replaceLibrary(_ playlists: [KeepLibraryPlaylist], to database: any DatabaseWriter) throws {
    try database.write { db in
      try CachedLibraryPlaylist.delete().execute(db)
      try CachedLibraryPlaylist.insert {
        playlists.map { CachedLibraryPlaylist.Draft(id: $0.id, name: $0.name) }
      }.execute(db)
    }
  }

  static func replaceProgress(_ progress: [String: PlaylistProgressResult], to database: any DatabaseWriter) throws {
    try database.write { db in
      try CachedSongProgress.delete().execute(db)
      for (playlistID, result) in progress {
        for (songID, status) in result.songs {
          let row = CachedSongProgress(playlistID: playlistID, songID: songID, progress: status)
          try db.execute(
            sql: "INSERT INTO cachedSongProgress (playlistID, songID, status, keptIn) VALUES (?, ?, ?, ?)",
            arguments: [playlistID, songID, row.status, String(decoding: try JSONEncoder().encode(row.keptIn), as: UTF8.self)]
          )
        }
      }
    }
  }
}
