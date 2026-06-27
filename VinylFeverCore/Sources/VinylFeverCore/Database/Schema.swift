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
  }

  public static func seedBuiltInSourceLabels(in database: any DatabaseWriter) throws {
    try database.write { db in
      for sourceLabel in SourceLabel.builtIns {
        try SourceLabel.upsert { sourceLabel }.execute(db)
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
