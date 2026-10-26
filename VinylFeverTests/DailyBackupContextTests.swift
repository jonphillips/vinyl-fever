import Foundation
import Dependencies
import Testing
import VinylFeverCore
@testable import VinylFever

struct DailyBackupContextTests {
  @Test("daily backups run only in the live app and poller contexts")
  func liveContextGuard() {
    #expect(shouldRunDailyBackup(in: .live))
    #expect(!shouldRunDailyBackup(in: .test))
    #expect(!shouldRunDailyBackup(in: .preview))
  }

  @Test("backup Settings state distinguishes missing, stale, warnings, and healthy sets")
  func settingsStates() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let current = DailyBackupManifest(createdAt: now, host: "Test Mac", build: "test", files: [], warnings: [])
    let old = DailyBackupManifest(createdAt: now.addingTimeInterval(-3 * 24 * 60 * 60), host: "Test Mac", build: "test", files: [], warnings: [])
    let warning = DailyBackupWarning(kind: .shrank, path: "iCloud/Listening/fetches/log.jsonl")

    #expect(backupHealth(manifest: nil, warnings: [], now: now) == .noSet)
    #expect(backupHealth(manifest: old, warnings: [], now: now) == .stale)
    #expect(backupHealth(manifest: current, warnings: [warning], now: now) == .warnings([warning]))
    #expect(backupHealth(manifest: current, warnings: [], now: now) == .ok)
  }
}
