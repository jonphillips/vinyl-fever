import Dependencies
import Foundation
import GRDB
import SQLiteData

public enum VinylFeverDatabaseError: Error, Equatable, LocalizedError {
  case olderBuild
  case adoptionFailed(String)

  public var errorDescription: String? {
    switch self {
    case .olderBuild:
      "This build of Vinyl Fever is older than your data. Install the current build."
    case let .adoptionFailed(message):
      "Vinyl Fever could not safely adopt its existing database. The original file was left in place.\n\n\(message)"
    }
  }
}

public enum VinylFeverDatabase {
  public static let legacyDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/SQLiteData.db")

  public static let liveDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/VinylFever/VinylFever.sqlite")

  public static func open(
    path: String? = nil,
    legacyPath: String? = nil,
    backupDirectory: String? = nil
  ) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
    }

    @Dependency(\.context) var context
    let isLive = context == .live && path == nil
    let resolvedPath: String?
    if let path {
      resolvedPath = path
    } else if isLive {
      resolvedPath = liveDatabaseURL.path(percentEncoded: false)
    } else {
      resolvedPath = nil
    }

    let oldPath = legacyPath ?? (isLive ? legacyDatabaseURL.path(percentEncoded: false) : nil)
    if let resolvedPath, let oldPath, resolvedPath != oldPath {
      try adoptLegacyDatabaseIfNeeded(oldPath: oldPath, newPath: resolvedPath)
    }
    if let resolvedPath {
      try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: resolvedPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
    }

    let database: any DatabaseWriter =
      if let path {
        try DatabasePool(path: path, configuration: configuration)
      } else {
        try SQLiteData.defaultDatabase(path: resolvedPath, configuration: configuration)
      }

    var migrator = DatabaseMigrator()
    registerMigrations(in: &migrator)

    if try database.read({ try migrator.hasBeenSuperseded($0) }) {
      throw VinylFeverDatabaseError.olderBuild
    }

    let hasPendingMigrations = try database.read { try !migrator.hasCompletedMigrations($0) }
    if hasPendingMigrations, isLive || backupDirectory != nil {
      let directory = backupDirectory
        ?? liveDatabaseURL.deletingLastPathComponent().appending(path: "Backups").path(percentEncoded: false)
      try makeMigrationBackup(of: database, in: directory)
    }

    try migrator.migrate(database)
    try seedBuiltInSourceLabels(in: database)
    try seedDefaultAppSettings(in: database)
    return database
  }

  private static func adoptLegacyDatabaseIfNeeded(oldPath: String, newPath: String) throws {
    let fileManager = FileManager.default
    guard !fileManager.fileExists(atPath: newPath), fileManager.fileExists(atPath: oldPath) else { return }

    do {
      let newURL = URL(fileURLWithPath: newPath)
      try fileManager.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let stagingURL = newURL.deletingLastPathComponent()
        .appending(path: ".VinylFever-adoption-\(UUID().uuidString).sqlite")

      do {
        var expectedRowCounts: [String: Int]?
        do {
          var readonlyConfiguration = Configuration()
          readonlyConfiguration.readonly = true
          let source = try DatabaseQueue(path: oldPath, configuration: readonlyConfiguration)
          let isVinylFever = try source.read { db in
            let hasMigrationTable = try String.fetchOne(
              db,
              sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'grdb_migrations'"
            ) != nil
            guard hasMigrationTable else { return false }
            return try String.fetchOne(
              db,
              sql: "SELECT identifier FROM grdb_migrations WHERE identifier = ?",
              arguments: ["Create 'sourceLabels' table"]
            ) != nil
          }
          guard isVinylFever else { return }

          expectedRowCounts = try tableRowCounts(from: source)
          let destination = try DatabaseQueue(path: stagingURL.path(percentEncoded: false))
          try source.backup(to: destination)
        }
        guard let expectedRowCounts else { return }

        try validateDatabase(at: stagingURL.path(percentEncoded: false), expectedRowCounts: expectedRowCounts)

        guard !fileManager.fileExists(atPath: newPath) else {
          throw VinylFeverDatabaseError.adoptionFailed("The new database appeared during adoption.")
        }
        try fileManager.moveItem(at: stagingURL, to: newURL)

        let oldURL = URL(fileURLWithPath: oldPath)
        let archivedURL = URL(fileURLWithPath: oldPath + ".moved-to-VinylFever")
        let sidecars = [oldURL, URL(fileURLWithPath: oldPath + "-wal"), URL(fileURLWithPath: oldPath + "-shm")]
        var moved: [(from: URL, to: URL)] = []
        do {
          for sourceURL in sidecars where fileManager.fileExists(atPath: sourceURL.path) {
            let destinationURL = sourceURL == oldURL
              ? archivedURL
              : URL(fileURLWithPath: archivedURL.path + (sourceURL.path.hasSuffix("-wal") ? "-wal" : "-shm"))
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
              throw VinylFeverDatabaseError.adoptionFailed("The preserved legacy filename already exists: \(destinationURL.lastPathComponent)")
            }
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            moved.append((sourceURL, destinationURL))
          }
        } catch {
          for item in moved.reversed() where fileManager.fileExists(atPath: item.to.path) {
            try? fileManager.moveItem(at: item.to, to: item.from)
          }
          try? fileManager.removeItem(at: newURL)
          throw error
        }
      } catch {
        for url in [stagingURL, URL(fileURLWithPath: stagingURL.path + "-wal"), URL(fileURLWithPath: stagingURL.path + "-shm")] {
          try? fileManager.removeItem(at: url)
        }
        throw error
      }
    } catch {
      if let error = error as? VinylFeverDatabaseError { throw error }
      throw VinylFeverDatabaseError.adoptionFailed(error.localizedDescription)
    }
  }

  private static func tableRowCounts(from database: any DatabaseReader) throws -> [String: Int] {
    try database.read { db in
      let tables = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )
      return try Dictionary(uniqueKeysWithValues: tables.map { table in
        let quotedTable = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(quotedTable)") ?? 0
        return (table, count)
      })
    }
  }

  private static func validateDatabase(at path: String, expectedRowCounts: [String: Int]) throws {
    let database = try DatabaseQueue(path: path)
    let integrity = try database.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
    guard integrity == "ok" else {
      throw VinylFeverDatabaseError.adoptionFailed("The copied database failed SQLite integrity_check: \(integrity ?? "no result").")
    }
    let copiedRowCounts = try tableRowCounts(from: database)
    guard copiedRowCounts == expectedRowCounts else {
      throw VinylFeverDatabaseError.adoptionFailed("The copied database's table row counts do not match the original.")
    }
  }

  private static func makeMigrationBackup(of database: any DatabaseWriter, in directoryPath: String) throws {
    let fileManager = FileManager.default
    let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
    let backupURL = directory.appending(path: "VinylFever-\(formatter.string(from: Date())).sqlite")
    let destination = try DatabaseQueue(path: backupURL.path(percentEncoded: false))
    try database.backup(to: destination)

    let backups = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )
    .filter { $0.lastPathComponent.hasPrefix("VinylFever-") && $0.pathExtension == "sqlite" }
    .sorted { $0.lastPathComponent > $1.lastPathComponent }
    for oldBackup in backups.dropFirst(5) {
      try fileManager.removeItem(at: oldBackup)
    }
  }

  public static func registerMigrations(in migrator: inout DatabaseMigrator) {
    migrator.registerMigration("Create 'sourceLabels' table") { db in
      try #sql("""
        CREATE TABLE "sourceLabels" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "token" TEXT NOT NULL DEFAULT '',
          "isBuiltIn" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create 'appSettings' table") { db in
      try #sql("""
        CREATE TABLE "appSettings" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "metaflacPath" TEXT,
          "ffmpegPath" TEXT,
          "ffprobePath" TEXT
        ) STRICT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create run log tables") { db in
      try #sql("""
        CREATE TABLE "runRecords" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "showRootPath" TEXT NOT NULL DEFAULT '',
          "kind" TEXT NOT NULL DEFAULT 'metadataRead',
          "startedAt" TEXT NOT NULL,
          "finishedAt" TEXT,
          "command" TEXT NOT NULL DEFAULT '',
          "exitSummary" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE TABLE "runFileOutcomes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "runID" TEXT NOT NULL REFERENCES "runRecords"("id") ON DELETE CASCADE,
          "sourcePath" TEXT NOT NULL DEFAULT '',
          "producedPath" TEXT,
          "status" TEXT NOT NULL DEFAULT 'read',
          "note" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_runFileOutcomes_on_runID" ON "runFileOutcomes"("runID")
        """)
        .execute(db)
    }

    migrator.registerMigration("Create 'compilationAlbums' table") { db in
      try #sql("""
        CREATE TABLE "compilationAlbums" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "album" TEXT NOT NULL DEFAULT '',
          "albumArtist" TEXT NOT NULL DEFAULT '',
          "displayImage" BLOB,
          "fallbackArtwork" BLOB,
          "stripTrackAndDisc" INTEGER NOT NULL DEFAULT 1,
          "setCompilationFlag" INTEGER NOT NULL DEFAULT 0,
          "groupingTokensText" TEXT NOT NULL DEFAULT '',
          "seedFolderPath" TEXT,
          "seedWarningsText" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """)
        .execute(db)
    }

    // 'collectionPolicies' before 'collectionRecipes': the recipe FK references it.
    migrator.registerMigration("Create 'collectionPolicies' table") { db in
      try #sql("""
        CREATE TABLE "collectionPolicies" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL DEFAULT '',
          "details" TEXT NOT NULL DEFAULT ''
        ) STRICT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create 'collectionRecipes' table") { db in
      try #sql("""
        CREATE TABLE "collectionRecipes" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "collectionPolicyID" TEXT NOT NULL REFERENCES "collectionPolicies"("id") ON DELETE CASCADE,
          "name" TEXT NOT NULL DEFAULT '',
          "pattern" TEXT NOT NULL DEFAULT '',
          "captureName" TEXT NOT NULL DEFAULT 'value',
          "targetField" TEXT NOT NULL DEFAULT 'title',
          "op" TEXT NOT NULL DEFAULT 'appendIfAbsent',
          "affixTemplate" TEXT NOT NULL DEFAULT ' ({value})',
          "useModel" INTEGER NOT NULL DEFAULT 0,
          "prompt" TEXT NOT NULL DEFAULT '',
          "enabled" INTEGER NOT NULL DEFAULT 1
        ) STRICT
        """)
        .execute(db)

      try #sql("""
        CREATE INDEX "index_collectionRecipes_on_collectionPolicyID"
          ON "collectionRecipes"("collectionPolicyID")
        """)
        .execute(db)
    }

    migrator.registerMigration("Bind compilation albums to collection policies") { db in
      try #sql("""
        ALTER TABLE "compilationAlbums"
          ADD COLUMN "collectionPolicyID" TEXT
          REFERENCES "collectionPolicies"("id") ON DELETE SET NULL
        """)
        .execute(db)
    }

    migrator.registerMigration("Add Music watch folder to app settings") { db in
      try #sql("""
        ALTER TABLE "appSettings"
          ADD COLUMN "musicWatchFolderPath" TEXT
        """)
        .execute(db)
    }

    migrator.registerMigration("Create 'artistAliases' table") { db in
      try #sql("""
        CREATE TABLE "artistAliases" (
          "variant" TEXT NOT NULL,
          "canonical" TEXT NOT NULL,
          "decision" TEXT NOT NULL CHECK ("decision" IN ('accepted', 'rejected')),
          "decidedAt" TEXT NOT NULL,
          PRIMARY KEY ("variant", "canonical")
        ) STRICT
        """).execute(db)
      try #sql("CREATE UNIQUE INDEX \"artistAliases_acceptedVariant\" ON \"artistAliases\" (\"variant\") WHERE \"decision\" = 'accepted'").execute(db)
    }
  }

  public static func seedBuiltInSourceLabels(in database: any DatabaseWriter) throws {
    try database.write { db in
      for sourceLabel in SourceLabel.builtIns {
        try SourceLabel.upsert { sourceLabel }.execute(db)
      }
    }
  }

  public static func seedDefaultAppSettings(in database: any DatabaseWriter) throws {
    try database.write { db in
      let existingSettings = try AppSetting.find(AppSetting.singletonID).fetchOne(db)
      if existingSettings == nil {
        try AppSetting.upsert { .default }.execute(db)
      }
    }
  }
}

extension DependencyValues {
  public mutating func bootstrapDatabase(path: String? = nil) throws {
    defaultDatabase = try VinylFeverDatabase.open(path: path)
  }
}

@DatabaseFunction
private func uuid() -> UUID {
  @Dependency(\.uuid) var uuid
  return uuid()
}
