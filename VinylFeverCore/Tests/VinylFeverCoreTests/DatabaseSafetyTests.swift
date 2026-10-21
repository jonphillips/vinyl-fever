import Foundation
import Dependencies
import SQLiteData
import Testing
@testable import VinylFeverCore

struct DatabaseSafetyTests {
  @Test
  func adoptionCopiesVerifiesAndPreservesTheLegacyDatabase() throws {
    let root = temporaryDirectory()
    let legacyPath = root.appending(path: "SQLiteData.db").path(percentEncoded: false)
    let newPath = root.appending(path: "VinylFever/VinylFever.sqlite").path(percentEncoded: false)

    let legacy = try open(path: legacyPath)
    try legacy.write { db in
      try db.execute(sql: "INSERT INTO sourceLabels (id, token, isBuiltIn) VALUES ('adopted-id', 'adopted-row', 0)")
      try db.execute(sql: "INSERT INTO sourceLabels (id, token, isBuiltIn) VALUES ('wal-id-1', 'wal-row-1', 0)")
      try db.execute(sql: "INSERT INTO sourceLabels (id, token, isBuiltIn) VALUES ('wal-id-2', 'wal-row-2', 0)")
    }
    let legacyWAL = try FileManager.default.attributesOfItem(atPath: legacyPath + "-wal")
    #expect((legacyWAL[.size] as? NSNumber)?.intValue ?? 0 > 0)

    let database = try open(path: newPath, legacyPath: legacyPath)
    let adoptedRows = try database.read { db in
      try String.fetchAll(db, sql: "SELECT token FROM sourceLabels WHERE token LIKE '%row%' ORDER BY token")
    }
    #expect(adoptedRows == ["adopted-row", "wal-row-1", "wal-row-2"])
    #expect(FileManager.default.fileExists(atPath: legacyPath + ".moved-to-VinylFever"))
    #expect(!FileManager.default.fileExists(atPath: legacyPath))
    let stagingFiles = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "VinylFever").path(percentEncoded: false))
      .filter { $0.hasPrefix(".VinylFever-adoption-") }
    #expect(stagingFiles.isEmpty)
  }

  @Test
  func needsLegacyAdoptionOnlyWhenLegacyExistsAndNewFileDoesNot() throws {
    let root = temporaryDirectory()
    let legacyPath = root.appending(path: "SQLiteData.db").path(percentEncoded: false)
    let newPath = root.appending(path: "VinylFever.sqlite").path(percentEncoded: false)

    #expect(!VinylFeverDatabase.needsLegacyAdoption(legacyPath: legacyPath, newPath: newPath))
    #expect(FileManager.default.createFile(atPath: legacyPath, contents: Data()))
    #expect(VinylFeverDatabase.needsLegacyAdoption(legacyPath: legacyPath, newPath: newPath))
    #expect(FileManager.default.createFile(atPath: newPath, contents: Data()))
    #expect(!VinylFeverDatabase.needsLegacyAdoption(legacyPath: legacyPath, newPath: newPath))
  }

  @Test
  func foreignLegacyDatabaseIsUntouchedAndNewDatabaseStartsFresh() throws {
    let root = temporaryDirectory()
    let legacyPath = root.appending(path: "SQLiteData.db").path(percentEncoded: false)
    let newPath = root.appending(path: "VinylFever/VinylFever.sqlite").path(percentEncoded: false)
    let foreign = try DatabaseQueue(path: legacyPath)
    try foreign.write { db in
      try db.execute(sql: "CREATE TABLE foreignData (value TEXT NOT NULL)")
      try db.execute(sql: "INSERT INTO foreignData VALUES ('keep')")
    }

    let database = try open(path: newPath, legacyPath: legacyPath)
    let hasAppSettings = try database.read { db in
      try db.tableExists("appSettings")
    }
    let foreignValue = try foreign.read { db in
      try String.fetchOne(db, sql: "SELECT value FROM foreignData")
    }
    #expect(hasAppSettings)
    #expect(foreignValue == "keep")
    #expect(FileManager.default.fileExists(atPath: legacyPath))
    #expect(!FileManager.default.fileExists(atPath: legacyPath + ".moved-to-VinylFever"))
  }

  @Test
  func existingNewDatabaseWinsWithoutTouchingLegacyFile() throws {
    let root = temporaryDirectory()
    let legacyPath = root.appending(path: "SQLiteData.db").path(percentEncoded: false)
    let newPath = root.appending(path: "VinylFever/VinylFever.sqlite").path(percentEncoded: false)

    do {
      let legacy = try open(path: legacyPath)
      try legacy.write { db in
        try db.execute(sql: "INSERT INTO sourceLabels (id, token, isBuiltIn) VALUES ('legacy-id', 'legacy', 0)")
      }
      let current = try open(path: newPath)
      try current.write { db in
        try db.execute(sql: "INSERT INTO sourceLabels (id, token, isBuiltIn) VALUES ('current-id', 'current', 0)")
      }
    }

    let database = try open(path: newPath, legacyPath: legacyPath)
    let tokens = try database.read { db in
      try String.fetchAll(db, sql: "SELECT token FROM sourceLabels WHERE token IN ('legacy', 'current') ORDER BY token")
    }
    #expect(tokens == ["current"])
    #expect(FileManager.default.fileExists(atPath: legacyPath))
    #expect(!FileManager.default.fileExists(atPath: legacyPath + ".moved-to-VinylFever"))
  }

  @Test
  func failedAdoptionLeavesBothFilesUnchangedAndThrows() throws {
    let root = temporaryDirectory()
    let legacyPath = root.appending(path: "SQLiteData.db").path(percentEncoded: false)
    let newPath = root.appending(path: "VinylFever/VinylFever.sqlite").path(percentEncoded: false)
    let originalBytes = Data("not a sqlite database".utf8)
    try originalBytes.write(to: URL(fileURLWithPath: legacyPath))

    do {
      _ = try open(path: newPath, legacyPath: legacyPath)
      Issue.record("Expected unsafe legacy database adoption to fail")
    } catch let error as VinylFeverDatabaseError {
      guard case .adoptionFailed = error else {
        Issue.record("Expected an adoption failure, got \(error)")
        return
      }
    }

    #expect(try Data(contentsOf: URL(fileURLWithPath: legacyPath)) == originalBytes)
    #expect(!FileManager.default.fileExists(atPath: newPath))
  }

  @Test
  func unknownMigrationIsRefusedWithoutChangingTheDatabase() throws {
    let path = temporaryDirectory().appending(path: "VinylFever.sqlite").path(percentEncoded: false)
    let database = try DatabaseQueue(path: path)
    var newerMigrator = DatabaseMigrator()
    VinylFeverDatabase.registerMigrations(in: &newerMigrator)
    newerMigrator.registerMigration("Future migration") { db in
      try db.execute(sql: "CREATE TABLE futureData (value TEXT NOT NULL)")
    }
    try newerMigrator.migrate(database)

    do {
      _ = try open(path: path)
      Issue.record("Expected an older-build refusal")
    } catch let error as VinylFeverDatabaseError {
      #expect(error == .olderBuild)
    }

    let stillPresent = try database.read { db in
      try db.tableExists("futureData")
    }
    #expect(stillPresent)
  }

  @Test
  func pendingMigrationsAreBackedUpBeforeTheyRunAndOnlyFiveBackupsRemain() throws {
    let root = temporaryDirectory()
    let backupsPath = root.appending(path: "Backups").path(percentEncoded: false)

    for index in 0..<7 {
      let path = root.appending(path: "Pending-\(index).sqlite").path(percentEncoded: false)
      try makePartiallyMigratedDatabase(path: path)
      _ = try open(path: path, backupDirectory: backupsPath)
    }

    let backups = try FileManager.default.contentsOfDirectory(atPath: backupsPath)
      .filter { $0.hasPrefix("VinylFever-") && $0.hasSuffix(".sqlite") }
    #expect(backups.count == 5)

    let backup = try #require(backups.sorted().first)
    let backupDB = try DatabaseQueue(
      path: root.appending(path: "Backups").appending(path: backup).path(percentEncoded: false)
    )
    let wasPreMigration = try backupDB.read { db in
      try !db.tableExists("appSettings")
    }
    #expect(wasPreMigration)
  }

  @Test
  func emptyNewDatabaseDoesNotCreateAMigrationBackup() throws {
    let root = temporaryDirectory()
    let path = root.appending(path: "VinylFever.sqlite").path(percentEncoded: false)
    let backupsPath = root.appending(path: "Backups").path(percentEncoded: false)
    _ = try DatabaseQueue(path: path)

    _ = try open(path: path, backupDirectory: backupsPath)

    #expect(!FileManager.default.fileExists(atPath: backupsPath))
  }

  private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "VinylFeverDatabaseSafety-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func open(path: String, legacyPath: String? = nil, backupDirectory: String? = nil) throws -> any DatabaseWriter {
    try withDependencies {
      $0.uuid = .incrementing
    } operation: {
      try VinylFeverDatabase.open(path: path, legacyPath: legacyPath, backupDirectory: backupDirectory)
    }
  }

  private func makePartiallyMigratedDatabase(path: String) throws {
    let database = try DatabaseQueue(path: path)
    try database.writeWithoutTransaction { db in
      try db.create(table: "grdb_migrations") {
        $0.column("identifier", .text).notNull().primaryKey()
      }
      try db.create(table: "sourceLabels") {
        $0.column("id", .text).notNull().primaryKey()
        $0.column("token", .text).notNull().defaults(to: "")
        $0.column("isBuiltIn", .boolean).notNull().defaults(to: false)
      }
      try db.execute(
        sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
        arguments: ["Create 'sourceLabels' table"]
      )
    }
  }
}
