import Foundation
import CryptoKit
import GRDB
import Testing
@testable import VinylFeverCore

struct DailyBackupTests {
  @Test("daily set copies sources, excludes its own destination, and writes matching manifest evidence")
  func createsCompleteSet() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    try fixture.write("{\"one\":1}\n{\"two\":2}\n", to: "iCloud/Taste Intelligence/notes.jsonl")
    try fixture.write("roles", to: "iCloud/Taste Intelligence/playlist-roles.json")
    try fixture.write("old", to: "iCloud/Backups/old.sqlite")
    try fixture.write("metadata", to: "iCloud/.DS_Store")
    try fixture.write("processed", to: "inbox/one.json")

    let result = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    guard case .created = result else { Issue.record("Expected a completed set"); return }
    let set = fixture.dailyRoot.appending(path: "2026-09-01")
    let manifest = try #require(try DailyBackup.latestManifest(in: fixture.dailyRoot))
    let note = try #require(manifest.files.first { $0.path == "iCloud/Taste Intelligence/notes.jsonl" })
    let copiedNote = try Data(contentsOf: set.appending(path: note.path))
    #expect(note.bytes == copiedNote.count)
    #expect(note.lineCount == 2)
    #expect(note.sha256 == fixture.sha256(copiedNote))
    #expect(String(data: try Data(contentsOf: set.appending(path: "PlaylistInbox/Processed/one.json")), encoding: .utf8) == "processed")
    #expect(!FileManager.default.fileExists(atPath: set.appending(path: "iCloud/Backups/old.sqlite").path))
    #expect(!FileManager.default.fileExists(atPath: set.appending(path: "iCloud/.DS_Store").path))
    #expect(manifest.format == "vf-backup-manifest")
    #expect(manifest.version == 1)

    let cloudCopy = fixture.cloudBackupRoot.appending(path: "Test_Mac/VinylFever-2026-09-01.sqlite")
    #expect(FileManager.default.fileExists(atPath: cloudCopy.path))
  }

  @Test("unchanged inputs hard-link, shrinking logs warn, and the prior set stays pinned")
  func linksAndDetectsShrink() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    let notePath = "iCloud/Listening/fetches/poller/2026-09.jsonl"
    try fixture.write("one\ntwo\nthree\n", to: notePath)
    try fixture.write("same", to: "iCloud/Taste Intelligence/playlist-roles.json")
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    let firstSet = fixture.dailyRoot.appending(path: "2026-09-01")
    let firstRoles = firstSet.appending(path: "iCloud/Taste Intelligence/playlist-roles.json")
    let firstNote = firstSet.appending(path: notePath)

    try fixture.write("one\n", to: notePath)
    try fixture.write("same", to: "inbox/unchanged.txt")
    _ = try DailyBackup.make(fixture.input(day: "2026-09-02"))
    let secondSet = fixture.dailyRoot.appending(path: "2026-09-02")
    let secondRoles = secondSet.appending(path: "iCloud/Taste Intelligence/playlist-roles.json")
    let secondNote = secondSet.appending(path: notePath)
    let firstInfo = try FileManager.default.attributesOfItem(atPath: firstRoles.path)
    let secondInfo = try FileManager.default.attributesOfItem(atPath: secondRoles.path)
    #expect((firstInfo[.systemFileNumber] as? NSNumber)?.uint64Value == (secondInfo[.systemFileNumber] as? NSNumber)?.uint64Value)
    let firstDatabaseInfo = try FileManager.default.attributesOfItem(atPath: firstSet.appending(path: "VinylFever.sqlite").path)
    let secondDatabaseInfo = try FileManager.default.attributesOfItem(atPath: secondSet.appending(path: "VinylFever.sqlite").path)
    #expect((firstDatabaseInfo[.systemFileNumber] as? NSNumber)?.uint64Value == (secondDatabaseInfo[.systemFileNumber] as? NSNumber)?.uint64Value)
    let firstNoteInfo = try FileManager.default.attributesOfItem(atPath: firstNote.path)
    let secondNoteInfo = try FileManager.default.attributesOfItem(atPath: secondNote.path)
    #expect((firstNoteInfo[.systemFileNumber] as? NSNumber)?.uint64Value != (secondNoteInfo[.systemFileNumber] as? NSNumber)?.uint64Value)

    let manifest = try #require(try DailyBackup.latestManifest(in: fixture.dailyRoot))
    #expect(manifest.warnings.contains(DailyBackupWarning(kind: .shrank, path: notePath)))
    #expect(FileManager.default.fileExists(atPath: firstSet.path))
    #expect(DailyBackup.recentWarnings(in: fixture.dailyRoot).contains(DailyBackupWarning(kind: .shrank, path: notePath)))
  }

  @Test("a missing prior JSONL file is recorded by path")
  func reportsMissingLog() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    try fixture.write("one\n", to: "iCloud/Listening/missing.jsonl")
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    try FileManager.default.removeItem(at: fixture.iCloudRoot.appending(path: "Listening/missing.jsonl"))
    _ = try DailyBackup.make(fixture.input(day: "2026-09-02"))
    let manifest = try #require(try DailyBackup.latestManifest(in: fixture.dailyRoot))
    #expect(manifest.warnings.contains(DailyBackupWarning(kind: .missing, path: "iCloud/Listening/missing.jsonl")))
  }

  @Test("unreadable cloud files reuse the previous copy and report the unreadable path")
  func reusesPreviousUnreadableFile() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    let path = "iCloud/Taste Intelligence/notes.jsonl"
    try fixture.write("saved\n", to: path)
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    let previous = fixture.dailyRoot.appending(path: "2026-09-01").appending(path: path)
    var input = fixture.input(day: "2026-09-02")
    input.readSource = { _ in throw CocoaError(.fileReadNoPermission) }
    _ = try DailyBackup.make(input)
    let current = fixture.dailyRoot.appending(path: "2026-09-02").appending(path: path)
    let previousInfo = try FileManager.default.attributesOfItem(atPath: previous.path)
    let currentInfo = try FileManager.default.attributesOfItem(atPath: current.path)
    #expect((previousInfo[.systemFileNumber] as? NSNumber)?.uint64Value == (currentInfo[.systemFileNumber] as? NSNumber)?.uint64Value)
    let manifest = try #require(try DailyBackup.latestManifest(in: fixture.dailyRoot))
    #expect(manifest.warnings.contains(DailyBackupWarning(kind: .unreadable, path: path)))
  }

  @Test("database backup includes committed WAL rows and passes integrity check")
  func backsUpLiveWAL() throws {
    let fixture = try Fixture()
    try FileManager.default.createDirectory(at: fixture.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var configuration = Configuration()
    configuration.journalMode = .wal
    let writer = try DatabasePool(path: fixture.databaseURL.path, configuration: configuration)
    try writer.write { db in
      try db.execute(sql: "CREATE TABLE records (value TEXT NOT NULL)")
      try db.execute(sql: "INSERT INTO records VALUES ('first')")
    }
    try writer.write { db in try db.execute(sql: "INSERT INTO records VALUES ('while-open')") }

    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    let copy = try DatabaseQueue(path: fixture.dailyRoot.appending(path: "2026-09-01/VinylFever.sqlite").path)
    let count = try copy.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM records") }
    let integrity = try copy.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
    #expect(count == 2)
    #expect(integrity == "ok")
  }

  @Test("checkpointed WAL database without sidecars backs up through immutable read-only mode")
  func backsUpWALDatabaseWithoutSidecars() throws {
    let fixture = try Fixture()
    try FileManager.default.createDirectory(at: fixture.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    var configuration = Configuration()
    configuration.journalMode = .wal
    do {
      let writer = try DatabasePool(path: fixture.databaseURL.path, configuration: configuration)
      try writer.write { db in
        try db.execute(sql: "CREATE TABLE records (value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO records VALUES ('saved')")
      }
      try writer.writeWithoutTransaction { db in
        try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
      }
    }
    for suffix in ["-wal", "-shm"] {
      let sidecar = URL(fileURLWithPath: fixture.databaseURL.path + suffix)
      if FileManager.default.fileExists(atPath: sidecar.path) { try FileManager.default.removeItem(at: sidecar) }
    }

    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    let copy = try DatabaseQueue(path: fixture.dailyRoot.appending(path: "2026-09-01/VinylFever.sqlite").path)
    let count = try copy.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM records") }
    #expect(count == 1)
  }

  @Test("same-day cloud database copy checks size without reading an equal-sized destination")
  func sameDayCloudCopySkipsEqualSizeRead() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    let cloudCopy = fixture.cloudBackupRoot
      .appending(path: "Test_Mac", directoryHint: .isDirectory)
      .appending(path: "VinylFever-2026-09-01.sqlite")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: cloudCopy.path)

    let result = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    #expect(result == .alreadyExists(date: "2026-09-01"))
    let permissions = try FileManager.default.attributesOfItem(atPath: cloudCopy.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0)
  }

  @Test("concurrent daily backup attempts leave one complete set")
  func concurrentRunsCreateOneSet() async throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    try fixture.write("play\n", to: "iCloud/Listening/fetches/log.jsonl")
    let input = fixture.input(day: "2026-09-01")
    let first = Task.detached { try DailyBackup.make(input) }
    let second = Task.detached { try DailyBackup.make(input) }
    let results = try await [first.value, second.value]
    #expect(results.filter { if case .created = $0 { true } else { false } }.count == 1)
    let sets = try FileManager.default.contentsOfDirectory(at: fixture.dailyRoot, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent == "2026-09-01" }
    #expect(sets.count == 1)
    #expect(FileManager.default.fileExists(atPath: sets[0].appending(path: "manifest.json").path))
  }

  @Test("a leftover partial set is removed before rebuilding today's set")
  func removesPartialSet() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    let partial = fixture.dailyRoot.appending(path: "2026-09-01.partial", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
    try fixture.write("abandoned", to: "iCloud/notes.jsonl")
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    #expect(!FileManager.default.fileExists(atPath: partial.path))
    #expect(FileManager.default.fileExists(atPath: fixture.dailyRoot.appending(path: "2026-09-01/manifest.json").path))
  }

  @Test("backup failure is saved for Settings and cleared after a successful retry")
  func recordsAndClearsFailure() throws {
    let fixture = try Fixture()
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    try DailyBackup.recordFailure("iCloud Drive is unavailable", at: instant, in: fixture.dailyRoot)
    #expect(DailyBackup.latestFailure(in: fixture.dailyRoot) == DailyBackupFailure(occurredAt: instant, message: "iCloud Drive is unavailable"))

    try fixture.writeDatabase()
    _ = try DailyBackup.make(fixture.input(day: "2026-09-01"))
    #expect(DailyBackup.latestFailure(in: fixture.dailyRoot) == nil)
  }

  @Test("pruning keeps 30 days, month starts, warning sets and their predecessors")
  func prunesAroundPinnedSets() throws {
    let fixture = try Fixture()
    try fixture.writeDatabase()
    let manager = FileManager.default
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    for offset in 0..<40 {
      let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 1))!
        .addingTimeInterval(Double(offset) * 24 * 60 * 60)
      let day = formatter.string(from: date)
      let folder = fixture.dailyRoot.appending(path: day, directoryHint: .isDirectory)
      try manager.createDirectory(at: folder, withIntermediateDirectories: true)
      let warning = day == "2026-01-05" ? #"[{"kind":"shrank","path":"iCloud/log.jsonl"}]"# : "[]"
      let manifest = #"{"format":"vf-backup-manifest","version":1,"createdAt":"\#(day)T12:00:00Z","host":"Test Mac","build":"old","files":[],"warnings":\#(warning)}"#
      try Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
    }
    let migrationBackup = fixture.dailyRoot.deletingLastPathComponent().appending(path: "VinylFever-old.sqlite")
    try Data("keep".utf8).write(to: migrationBackup)
    let cloudHostRoot = fixture.cloudBackupRoot.appending(path: "Test_Mac", directoryHint: .isDirectory)
    try manager.createDirectory(at: cloudHostRoot, withIntermediateDirectories: true)
    for offset in 0..<40 {
      let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 1))!
        .addingTimeInterval(Double(offset) * 24 * 60 * 60)
      let day = formatter.string(from: date)
      try Data("database".utf8).write(to: cloudHostRoot.appending(path: "VinylFever-\(day).sqlite"))
    }

    _ = try DailyBackup.make(fixture.input(day: "2026-02-10"))

    let sets = try manager.contentsOfDirectory(at: fixture.dailyRoot, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
    #expect(sets.count == 33)
    #expect(manager.fileExists(atPath: fixture.dailyRoot.appending(path: "2026-01-01").path))
    #expect(manager.fileExists(atPath: fixture.dailyRoot.appending(path: "2026-02-01").path))
    #expect(manager.fileExists(atPath: fixture.dailyRoot.appending(path: "2026-01-04").path))
    #expect(manager.fileExists(atPath: fixture.dailyRoot.appending(path: "2026-01-05").path))
    #expect(manager.fileExists(atPath: migrationBackup.path))
    let cloudCopies = try manager.contentsOfDirectory(at: cloudHostRoot, includingPropertiesForKeys: nil)
    #expect(cloudCopies.count == 17)
    #expect(manager.fileExists(atPath: cloudHostRoot.appending(path: "VinylFever-2026-01-01.sqlite").path))
    #expect(manager.fileExists(atPath: cloudHostRoot.appending(path: "VinylFever-2026-01-04.sqlite").path))
    #expect(manager.fileExists(atPath: cloudHostRoot.appending(path: "VinylFever-2026-01-05.sqlite").path))
  }

  private struct Fixture {
    let root: URL
    let databaseURL: URL
    let dailyRoot: URL
    let iCloudRoot: URL
    let inboxRoot: URL
    let cloudBackupRoot: URL

    init() throws {
      root = FileManager.default.temporaryDirectory.appending(path: "DailyBackup-\(UUID().uuidString)", directoryHint: .isDirectory)
      databaseURL = root.appending(path: "live/VinylFever.sqlite")
      dailyRoot = root.appending(path: "support/Backups/Daily", directoryHint: .isDirectory)
      iCloudRoot = root.appending(path: "iCloud/Vinyl Fever", directoryHint: .isDirectory)
      inboxRoot = root.appending(path: "support/PlaylistInbox/Processed", directoryHint: .isDirectory)
      cloudBackupRoot = root.appending(path: "iCloud/Vinyl Fever/Backups", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: iCloudRoot, withIntermediateDirectories: true)
    }

    func writeDatabase() throws {
      try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let database = try DatabaseQueue(path: databaseURL.path)
      try database.write { db in
        try db.execute(sql: "CREATE TABLE records (value TEXT NOT NULL)")
        try db.execute(sql: "INSERT INTO records VALUES ('saved')")
      }
    }

    func write(_ contents: String, to relativePath: String) throws {
      let url = (relativePath.hasPrefix("iCloud/") ? root : root)
        .appending(path: relativePath.hasPrefix("iCloud/") ? "iCloud/Vinyl Fever" : "support/PlaylistInbox/Processed")
        .appending(path: relativePath.replacingOccurrences(of: #"^(iCloud/|inbox/)"#, with: "", options: .regularExpression))
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: url)
    }

    func input(day: String) -> DailyBackupInput {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone.current
      formatter.dateFormat = "yyyy-MM-dd"
      return DailyBackupInput(
        databaseURL: databaseURL,
        dailyRoot: dailyRoot,
        iCloudRoot: iCloudRoot,
        processedInboxRoot: inboxRoot,
        iCloudDatabaseBackupRoot: cloudBackupRoot,
        host: "Test Mac",
        build: "test-build",
        now: formatter.date(from: day)!
      )
    }

    func sha256(_ data: Data) -> String {
      importCryptoSHA(data)
    }
  }
}

private func importCryptoSHA(_ data: Data) -> String {
  // Kept local to the fixture so the public manifest is checked without reusing backup internals.
  CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
