import CustomDump
import Foundation
import SQLiteData
import Testing
@testable import VinylFeverCore

struct AppSettingTests {
  @Test
  func defaultSettingsAreSeededIdempotently() throws {
    let database = try VinylFeverDatabase.open()

    try VinylFeverDatabase.seedDefaultAppSettings(in: database)

    let settings = try database.read { db in
      try AppSetting.all.fetchAll(db)
    }

    expectNoDifference(settings, [.default])
  }

  @Test
  func toolOverridesPersistAcrossDatabaseLaunches() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory
      .appendingPathComponent("VinylFever.sqlite")
      .path(percentEncoded: false)
    let settings = AppSetting.default
      .withOverridePath("/custom/bin/metaflac", for: .metaflac)
      .withOverridePath(" /custom/bin/ffmpeg ", for: .ffmpeg)

    do {
      let database = try VinylFeverDatabase.open(path: path)
      try database.write { db in
        try AppSetting.upsert { settings }.execute(db)
      }
    }

    do {
      let database = try VinylFeverDatabase.open(path: path)
      let persistedSettings = try database.read { db in
        try AppSetting.all.fetchAll(db)
      }

      expectNoDifference(AppSetting.current(from: persistedSettings), settings)
      expectNoDifference(
        AppSetting.current(from: persistedSettings).toolPathOverrides,
        ToolPathOverrides(
          metaflacPath: "/custom/bin/metaflac",
          ffmpegPath: "/custom/bin/ffmpeg"
        )
      )
    }
  }
}
