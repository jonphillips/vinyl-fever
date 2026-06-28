import Dependencies
import Foundation
import SQLiteData

public enum VinylFeverDatabase {
  public static func open(path: String? = nil) throws -> any DatabaseWriter {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
    }

    let database: any DatabaseWriter =
      if let path {
        try DatabasePool(path: path, configuration: configuration)
      } else {
        try SQLiteData.defaultDatabase(configuration: configuration)
      }

    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    registerMigrations(in: &migrator)
    try migrator.migrate(database)
    try seedBuiltInSourceLabels(in: database)
    try seedDefaultAppSettings(in: database)
    return database
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
