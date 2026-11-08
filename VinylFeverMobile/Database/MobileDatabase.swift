import Dependencies
import Foundation
import GRDB
import SQLiteData

enum MobileDatabase {
  static let liveDatabaseURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "VinylFever/VinylFeverMobile.sqlite")

  static func open(path: String? = nil) -> any DatabaseWriter {
    @Dependency(\.context) var context
    let isLive = context == .live && path == nil
    let resolvedPath = path ?? (isLive ? liveDatabaseURL.path(percentEncoded: false) : nil)

    do {
      if let resolvedPath {
        try FileManager.default.createDirectory(
          at: URL(fileURLWithPath: resolvedPath).deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
      }
      return try makeMigratedDatabase(path: resolvedPath)
    } catch {
      NSLog("Vinyl Fever mobile cache database failed to open or migrate: %@", error.localizedDescription)
      if let resolvedPath {
        removeDatabaseFiles(at: resolvedPath)
        do {
          return try makeMigratedDatabase(path: resolvedPath)
        } catch {
          NSLog("Vinyl Fever mobile cache database could not be recreated: %@", error.localizedDescription)
        }
      }
    }

    do {
      let database = try DatabaseQueue()
      do {
        try migrate(database)
      } catch {
        NSLog("Vinyl Fever mobile in-memory cache database migration failed: %@", error.localizedDescription)
      }
      return database
    } catch {
      fatalError("Vinyl Fever mobile in-memory cache database could not open: \(error.localizedDescription)")
    }
  }

  static func openInMemory() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try migrate(database)
    return database
  }

  private static func makeMigratedDatabase(path: String?) throws -> any DatabaseWriter {
    let database = try makeDatabase(path: path)
    try migrate(database)
    return database
  }

  private static func makeDatabase(path: String?) throws -> any DatabaseWriter {
    try SQLiteData.defaultDatabase(path: path)
  }

  private static func migrate(_ database: any DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1 shelf cache") { db in
      try #sql("""
        CREATE TABLE "cachedBatch" (
          "key" TEXT PRIMARY KEY NOT NULL,
          "batch" TEXT NOT NULL
        ) STRICT
        """).execute(db)
      try #sql("""
        CREATE TABLE "cachedCreationEvent" (
          "key" TEXT PRIMARY KEY NOT NULL,
          "event" TEXT NOT NULL
        ) STRICT
        """).execute(db)
      try #sql("""
        CREATE TABLE "cachedLibraryPlaylist" (
          "id" TEXT PRIMARY KEY NOT NULL,
          "name" TEXT NOT NULL
        ) STRICT
        """).execute(db)
      try #sql("""
        CREATE TABLE "cachedSongProgress" (
          "playlistID" TEXT NOT NULL,
          "songID" TEXT NOT NULL,
          "status" TEXT NOT NULL,
          "keptIn" TEXT NOT NULL,
          PRIMARY KEY ("playlistID", "songID")
        ) STRICT
        """).execute(db)
    }
    guard try !database.read({ try migrator.hasBeenSuperseded($0) }) else {
      throw MobileDatabaseError.olderBuild
    }
    try migrator.migrate(database)
  }

  private static func removeDatabaseFiles(at path: String) {
    for file in [path, "\(path)-wal", "\(path)-shm"] {
      try? FileManager.default.removeItem(atPath: file)
    }
  }
}

private enum MobileCacheDatabaseKey: DependencyKey {
  static var liveValue: (any DatabaseWriter)? { MobileDatabase.open() }
  static var testValue: (any DatabaseWriter)? { nil }
}

extension DependencyValues {
  var mobileCacheDatabase: (any DatabaseWriter)? {
    get { self[MobileCacheDatabaseKey.self] }
    set { self[MobileCacheDatabaseKey.self] = newValue }
  }
}

private enum MobileDatabaseError: Error {
  case olderBuild
}
