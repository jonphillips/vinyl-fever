import Dependencies
import SQLiteData

public enum VinylFeverDatabase {
  public static func registerMigrations(in migrator: inout DatabaseMigrator) {
  }
}

extension DependencyValues {
  public mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    VinylFeverDatabase.registerMigrations(in: &migrator)
    try migrator.migrate(database)
    defaultDatabase = database
  }
}
