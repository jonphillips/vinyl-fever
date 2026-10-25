import CryptoKit
import Darwin
import Foundation
import GRDB

public struct DailyBackupInput: Sendable {
  public var databaseURL: URL
  public var dailyRoot: URL
  public var iCloudRoot: URL
  public var processedInboxRoot: URL
  public var iCloudDatabaseBackupRoot: URL
  public var host: String
  public var build: String
  public var now: Date
  public var readSource: (@Sendable (URL) throws -> Data)?

  public init(
    databaseURL: URL,
    dailyRoot: URL,
    iCloudRoot: URL,
    processedInboxRoot: URL,
    iCloudDatabaseBackupRoot: URL,
    host: String,
    build: String,
    now: Date = .now,
    readSource: (@Sendable (URL) throws -> Data)? = nil
  ) {
    self.databaseURL = databaseURL
    self.dailyRoot = dailyRoot
    self.iCloudRoot = iCloudRoot
    self.processedInboxRoot = processedInboxRoot
    self.iCloudDatabaseBackupRoot = iCloudDatabaseBackupRoot
    self.host = host
    self.build = build
    self.now = now
    self.readSource = readSource
  }
}

public struct DailyBackupFile: Codable, Equatable, Sendable {
  public var path: String
  public var bytes: Int
  public var sha256: String
  public var lineCount: Int?

  public init(path: String, bytes: Int, sha256: String, lineCount: Int? = nil) {
    self.path = path
    self.bytes = bytes
    self.sha256 = sha256
    self.lineCount = lineCount
  }
}

public struct DailyBackupWarning: Codable, Equatable, Sendable {
  public var kind: Kind
  public var path: String

  public enum Kind: String, Codable, Sendable {
    case shrank
    case missing
    case unreadable
  }

  public init(kind: Kind, path: String) {
    self.kind = kind
    self.path = path
  }
}

public struct DailyBackupManifest: Codable, Equatable, Sendable {
  public var format = "vf-backup-manifest"
  public var version = 1
  public var createdAt: Date
  public var host: String
  public var build: String
  public var files: [DailyBackupFile]
  public var warnings: [DailyBackupWarning]

  public init(createdAt: Date, host: String, build: String, files: [DailyBackupFile], warnings: [DailyBackupWarning]) {
    self.createdAt = createdAt
    self.host = host
    self.build = build
    self.files = files
    self.warnings = warnings
  }
}

public struct DailyBackupFailure: Codable, Equatable, Sendable {
  public var occurredAt: Date
  public var message: String

  public init(occurredAt: Date, message: String) {
    self.occurredAt = occurredAt
    self.message = message
  }
}

public enum DailyBackupResult: Equatable, Sendable {
  case created(date: String, bytes: Int, warnings: [DailyBackupWarning])
  case alreadyExists(date: String)
  case anotherRunIsActive
}

public enum DailyBackup {
  public static func make(_ input: DailyBackupInput) throws -> DailyBackupResult {
    let manager = FileManager.default
    try manager.createDirectory(at: input.dailyRoot, withIntermediateDirectories: true)
    let lockURL = input.dailyRoot.appending(path: ".backup.lock")
    let lockFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard lockFD >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
      let lockError = errno
      close(lockFD)
      if lockError == EWOULDBLOCK || lockError == EAGAIN { return .anotherRunIsActive }
      throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EIO)
    }
    defer {
      _ = flock(lockFD, LOCK_UN)
      close(lockFD)
    }

    let day = dayString(input.now)
    let finalURL = input.dailyRoot.appending(path: day, directoryHint: .isDirectory)
    if manager.fileExists(atPath: finalURL.path) {
      try ensureCloudDatabaseCopy(
        from: finalURL.appending(path: "VinylFever.sqlite"), input: input, day: day, compareContents: false
      )
      try pruneLocalSets(in: input.dailyRoot)
      let cloudHostRoot = input.iCloudDatabaseBackupRoot.appending(path: safeComponent(input.host), directoryHint: .isDirectory)
      try pruneCloudCopies(in: cloudHostRoot, now: input.now, pinnedDates: pinnedDates(in: input.dailyRoot))
      try clearFailure(in: input.dailyRoot)
      return .alreadyExists(date: day)
    }

    let partialURL = input.dailyRoot.appending(path: "\(day).partial", directoryHint: .isDirectory)
    if manager.fileExists(atPath: partialURL.path) { try manager.removeItem(at: partialURL) }
    try manager.createDirectory(at: partialURL, withIntermediateDirectories: true)
    do {
      let previous = previousSet(in: input.dailyRoot, before: day)
      var files: [DailyBackupFile] = []
      var warnings: [DailyBackupWarning] = []

      let databaseCopy = partialURL.appending(path: "VinylFever.sqlite")
      try backupDatabase(from: input.databaseURL, to: databaseCopy)
      if let oldDatabase = previous?.appending(path: "VinylFever.sqlite"),
        manager.fileExists(atPath: oldDatabase.path),
        let currentData = try? Data(contentsOf: databaseCopy),
        let oldData = try? Data(contentsOf: oldDatabase),
        currentData.count == oldData.count,
        sha256(currentData) == sha256(oldData)
      {
        try manager.removeItem(at: databaseCopy)
        try manager.linkItem(at: oldDatabase, to: databaseCopy)
      }
      files.append(try metadata(for: databaseCopy, relativePath: "VinylFever.sqlite"))

      let sources = try collectSources(input)
      for (source, destinationRelativePath) in sources {
        let destination = partialURL.appending(path: destinationRelativePath)
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
          let data = try input.readSource?(source) ?? coordinatedRead(source)
          let oldFile = previous?.appending(path: destinationRelativePath)
          let digest = sha256(data)
          if let oldFile,
            manager.fileExists(atPath: oldFile.path),
            let oldData = try? Data(contentsOf: oldFile),
            oldData.count == data.count,
            sha256(oldData) == digest
          {
            try manager.linkItem(at: oldFile, to: destination)
          } else {
            try data.write(to: destination, options: .atomic)
          }
          files.append(try metadata(for: destination, relativePath: destinationRelativePath, data: data))
          if destinationRelativePath.hasSuffix(".jsonl"), let oldFile,
            manager.fileExists(atPath: oldFile.path),
            lineCount(data) < lineCount(try Data(contentsOf: oldFile))
          {
            warnings.append(DailyBackupWarning(kind: .shrank, path: destinationRelativePath))
          }
        } catch {
          if let oldFile = previous?.appending(path: destinationRelativePath), manager.fileExists(atPath: oldFile.path) {
            try manager.linkItem(at: oldFile, to: destination)
            let data = try Data(contentsOf: destination)
            files.append(try metadata(for: destination, relativePath: destinationRelativePath, data: data))
          }
          warnings.append(DailyBackupWarning(kind: .unreadable, path: destinationRelativePath))
        }
      }

      if let previous {
        let currentPaths = Set(sources.map(\.1))
        let previousManifest = try readManifest(at: previous)
        for oldFile in previousManifest.files where oldFile.path.hasSuffix(".jsonl") && !currentPaths.contains(oldFile.path) {
          warnings.append(DailyBackupWarning(kind: .missing, path: oldFile.path))
        }
      }

      let manifest = DailyBackupManifest(
        createdAt: input.now,
        host: input.host,
        build: input.build,
        files: files.sorted { $0.path < $1.path },
        warnings: warnings
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(manifest).write(to: partialURL.appending(path: "manifest.json"), options: .atomic)
      try manager.moveItem(at: partialURL, to: finalURL)

      try ensureCloudDatabaseCopy(from: finalURL.appending(path: "VinylFever.sqlite"), input: input, day: day)
      try pruneLocalSets(in: input.dailyRoot)
      let cloudHostRoot = input.iCloudDatabaseBackupRoot.appending(path: safeComponent(input.host), directoryHint: .isDirectory)
      try pruneCloudCopies(in: cloudHostRoot, now: input.now, pinnedDates: pinnedDates(in: input.dailyRoot))
      try clearFailure(in: input.dailyRoot)
      return .created(date: day, bytes: files.reduce(0) { $0 + $1.bytes }, warnings: warnings)
    } catch {
      try? manager.removeItem(at: partialURL)
      throw error
    }
  }

  public static func latestManifest(in dailyRoot: URL) throws -> DailyBackupManifest? {
    guard FileManager.default.fileExists(atPath: dailyRoot.path) else { return nil }
    let directories = try FileManager.default.contentsOfDirectory(
      at: dailyRoot, includingPropertiesForKeys: [.isDirectoryKey]
    ).filter { $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
    guard let latest = directories.first else { return nil }
    return try readManifest(at: latest)
  }

  public static func recentWarnings(in dailyRoot: URL, days: Int = 30) -> [DailyBackupWarning] {
    guard let directories = try? FileManager.default.contentsOfDirectory(at: dailyRoot, includingPropertiesForKeys: nil) else { return [] }
    return directories
      .filter { $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
      .prefix(days)
      .flatMap { (try? readManifest(at: $0).warnings) ?? [] }
  }

  public static func latestFailure(in dailyRoot: URL) -> DailyBackupFailure? {
    let url = dailyRoot.appending(path: "last-error.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(DailyBackupFailure.self, from: data)
  }

  public static func recordFailure(_ message: String, at date: Date = .now, in dailyRoot: URL) throws {
    try FileManager.default.createDirectory(at: dailyRoot, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(DailyBackupFailure(occurredAt: date, message: message))
      .write(to: dailyRoot.appending(path: "last-error.json"), options: .atomic)
  }

  private static func clearFailure(in dailyRoot: URL) throws {
    let url = dailyRoot.appending(path: "last-error.json")
    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
  }

  public static func dailyRoot(in applicationSupport: URL) -> URL {
    applicationSupport.appending(path: "VinylFever/Backups/Daily", directoryHint: .isDirectory)
  }

  public static func dayString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func collectSources(_ input: DailyBackupInput) throws -> [(URL, String)] {
    guard FileManager.default.fileExists(atPath: input.iCloudRoot.path) else { throw CocoaError(.fileNoSuchFile) }
    var result: [(URL, String)] = []
    for (root, prefix) in [(input.iCloudRoot, "iCloud/"), (input.processedInboxRoot, "PlaylistInbox/Processed/")]
    where FileManager.default.fileExists(atPath: root.path) {
      guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else {
        throw CocoaError(.fileReadNoPermission)
      }
      for case let url as URL in enumerator {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        let rootPrefixLength = rootPath.count + (rootPath.hasSuffix("/") ? 0 : 1)
        let relative = String(filePath.dropFirst(rootPrefixLength))
        if url.lastPathComponent == ".DS_Store" || (prefix == "iCloud/" && relative == "Backups") {
          if values.isDirectory == true { enumerator.skipDescendants() }
          continue
        }
        if prefix == "iCloud/", relative.hasPrefix("Backups/") { continue }
        guard values.isRegularFile == true else { continue }
        result.append((url, prefix + relative))
      }
    }
    return result.sorted { $0.1 < $1.1 }
  }

  private static func backupDatabase(from sourcePath: URL, to destinationURL: URL) throws {
    var configuration = Configuration()
    configuration.readonly = true
    let source: DatabaseQueue
    do {
      source = try DatabaseQueue(path: sourcePath.path, configuration: configuration)
    } catch let error as DatabaseError
      where error.resultCode.primaryResultCode == .SQLITE_CANTOPEN
        && !FileManager.default.fileExists(atPath: sourcePath.path + "-wal")
    {
      let uri = URL(fileURLWithPath: sourcePath.path).absoluteString + "?mode=ro&immutable=1"
      source = try DatabaseQueue(path: uri, configuration: configuration)
    }
    let destination = try DatabaseQueue(path: destinationURL.path)
    try source.backup(to: destination)
    let integrity = try destination.read { try String.fetchOne($0, sql: "PRAGMA integrity_check") }
    guard integrity == "ok" else { throw CocoaError(.fileReadCorruptFile) }
  }

  private static func coordinatedRead(_ url: URL) throws -> Data {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<Data, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      result = Result { try Data(contentsOf: coordinatedURL) }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileReadUnknown) }
    return try result.get()
  }

  private static func metadata(for url: URL, relativePath: String, data: Data? = nil) throws -> DailyBackupFile {
    let contents = try data ?? Data(contentsOf: url)
    return DailyBackupFile(
      path: relativePath,
      bytes: contents.count,
      sha256: sha256(contents),
      lineCount: relativePath.hasSuffix(".jsonl") ? lineCount(contents) : nil
    )
  }

  private static func readManifest(at directory: URL) throws -> DailyBackupManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(DailyBackupManifest.self, from: Data(contentsOf: directory.appending(path: "manifest.json")))
  }

  private static func previousSet(in root: URL, before day: String) -> URL? {
    (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
      .filter { $0.lastPathComponent < day && $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }.first
  }

  private static func pruneLocalSets(in root: URL) throws {
    let manager = FileManager.default
    let sets = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
    var keep = Set(sets.prefix(30).map(\.lastPathComponent))
    var monthly = Set<String>()
    for set in sets.reversed() {
      let month = String(set.lastPathComponent.prefix(7))
      if monthly.insert(month).inserted { keep.insert(set.lastPathComponent) }
    }
    for set in sets {
      let manifest = try? readManifest(at: set)
      if manifest?.warnings.isEmpty == false || manifest == nil {
        keep.insert(set.lastPathComponent)
        if let previous = previousSet(in: root, before: set.lastPathComponent) { keep.insert(previous.lastPathComponent) }
      }
    }
    for set in sets where !keep.contains(set.lastPathComponent) { try manager.removeItem(at: set) }
  }

  private static func pinnedDates(in root: URL) -> Set<String> {
    guard let sets = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter({ $0.lastPathComponent.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil })
    else { return [] }
    var dates: Set<String> = []
    for set in sets {
      let manifest = try? readManifest(at: set)
      guard manifest?.warnings.isEmpty == false || manifest == nil else { continue }
      dates.insert(set.lastPathComponent)
      if let previous = previousSet(in: root, before: set.lastPathComponent) { dates.insert(previous.lastPathComponent) }
    }
    return dates
  }

  private static func pruneCloudCopies(in directory: URL, now: Date, pinnedDates: Set<String>) throws {
    let manager = FileManager.default
    let copies = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.range(of: #"^VinylFever-\d{4}-\d{2}-\d{2}\.sqlite$"#, options: .regularExpression) != nil }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
    var keep = Set(copies.prefix(14).map(\.lastPathComponent))
    let monthFormatter = DateFormatter()
    monthFormatter.locale = Locale(identifier: "en_US_POSIX")
    monthFormatter.dateFormat = "yyyy-MM"
    let eligibleMonths = Set((0..<12).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: now) }.map(monthFormatter.string))
    var firstByMonth: Set<String> = []
    for copy in copies.reversed() {
      let day = String(copy.lastPathComponent.dropFirst("VinylFever-".count).prefix(10))
      if pinnedDates.contains(day) { keep.insert(copy.lastPathComponent) }
      let month = String(day.prefix(7))
      if eligibleMonths.contains(month), firstByMonth.insert(month).inserted { keep.insert(copy.lastPathComponent) }
    }
    for copy in copies where !keep.contains(copy.lastPathComponent) { try manager.removeItem(at: copy) }
  }

  private static func atomicCopy(from source: URL, to destination: URL) throws {
    try coordinatedWrite(Data(contentsOf: source), to: destination)
  }

  private static func ensureCloudDatabaseCopy(
    from source: URL, input: DailyBackupInput, day: String, compareContents: Bool = true
  ) throws {
    let destination = input.iCloudDatabaseBackupRoot
      .appending(path: safeComponent(input.host), directoryHint: .isDirectory)
      .appending(path: "VinylFever-\(day).sqlite")
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let manager = FileManager.default
    if manager.fileExists(atPath: destination.path),
      let sourceSize = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      let destinationSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      sourceSize == destinationSize
    {
      if !compareContents { return }
    } else if !compareContents {
      try atomicCopy(from: source, to: destination)
      return
    }
    if let sourceData = try? Data(contentsOf: source),
      let existingData = try? coordinatedRead(destination),
      sourceData.count == existingData.count,
      sha256(sourceData) == sha256(existingData)
    {
      return
    }
    try atomicCopy(from: source, to: destination)
  }

  private static func coordinatedWrite(_ data: Data, to url: URL) throws {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<Void, Error>?
    coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
      result = Result { try data.write(to: coordinatedURL, options: .atomic) }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileWriteUnknown) }
    try result.get()
  }

  private static func lineCount(_ data: Data) -> Int {
    let bytes = [UInt8](data)
    guard !bytes.isEmpty else { return 0 }
    return bytes.reduce(into: 0) { if $1 == 0x0A { $0 += 1 } } + (bytes.last == 0x0A ? 0 : 1)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func safeComponent(_ value: String) -> String {
    let safe = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_" }.joined()
    return safe.isEmpty ? "Mac" : safe
  }
}
