import Foundation
import SystemConfiguration

extension ListeningStore {
  public static func liveHostName() -> String {
    SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? "Mac"
  }

  public static var liveValue: Self {
    let localFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("VinylFever", isDirectory: true)
      .appendingPathComponent("Listening", isDirectory: true)
    let iCloudFolder = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Listening", isDirectory: true)
    return live(iCloudFolder: iCloudFolder, localFolder: localFolder)
  }

  public static func live(
    iCloudFolder: URL,
    localFolder: URL,
    hostName: @escaping @Sendable () -> String = { ListeningStore.liveHostName() }
  ) -> Self {
    return Self(
      pollerID: { try ListeningLocalState(folder: localFolder).pollerID() },
      readLease: {
        guard let data = try ListeningCoordinatedFiles.readData(iCloudFolder.appendingPathComponent("lease.json")) else {
          return nil
        }
        return try ListeningLogCodec.decodeLease(data)
      },
      writeLease: { lease in
        let data = try ListeningLogCodec.encode(lease)
        try ListeningCoordinatedFiles.write(data, to: iCloudFolder.appendingPathComponent("lease.json"))
      },
      readLastList: { try ListeningLocalState(folder: localFolder).lastList() },
      writeLastList: { items in try ListeningLocalState(folder: localFolder).writeLastList(items) },
      clearLastList: { try ListeningLocalState(folder: localFolder).clearLastList() },
      readHandoverMarker: { try ListeningLocalState(folder: localFolder).handoverMarker() },
      writeHandoverMarker: { marker in try ListeningLocalState(folder: localFolder).writeHandoverMarker(marker) },
      clearHandoverMarker: { try ListeningLocalState(folder: localFolder).clearHandoverMarker() },
      readRecentFetches: { now in
        let fetchesFolder = iCloudFolder.appendingPathComponent("fetches", isDirectory: true)
        let streams = try FileManager.default.contentsOfDirectory(
          at: fetchesFolder, includingPropertiesForKeys: [.isDirectoryKey]
        )
        let months = Self.months(around: now)
        var records: [ListeningFetch] = []
        for stream in streams {
          for month in months {
            let file = stream.appendingPathComponent(month + ".jsonl")
            guard let data = try ListeningCoordinatedFiles.readData(file) else { continue }
            records.append(contentsOf: try ListeningLogCodec.decodeJSONL(data))
          }
        }
        return records.sorted { $0.fetchedAt < $1.fetchedAt }
      },
      appendFetch: { fetch in
        let stream = iCloudFolder
          .appendingPathComponent("fetches", isDirectory: true)
          .appendingPathComponent(fetch.poller.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
        let file = stream.appendingPathComponent(Self.month(for: fetch.fetchedAt) + ".jsonl")
        try ListeningCoordinatedFiles.append(ListeningLogCodec.encode(fetch), to: file)
      },
      readFetches: {
        let fetchesFolder = iCloudFolder.appendingPathComponent("fetches", isDirectory: true)
        guard let files = FileManager.default.enumerator(
          at: fetchesFolder, includingPropertiesForKeys: [.isRegularFileKey]
        )?.compactMap({ $0 as? URL }).filter({ $0.pathExtension == "jsonl" }) else { return [] }
        var records: [ListeningFetch] = []
        for file in files {
          guard let data = try ListeningCoordinatedFiles.readData(file) else { continue }
          records.append(contentsOf: try ListeningLogCodec.decodeJSONL(data))
        }
        return records.sorted { $0.fetchedAt < $1.fetchedAt }
      },
      readLastPollError: { try ListeningLocalState(folder: localFolder).lastPollError() },
      writeLastPollError: { error in try ListeningLocalState(folder: localFolder).writePollError(error) },
      listeningFolder: { iCloudFolder },
      readNewMusicExposure: {
        let folder = iCloudFolder.deletingLastPathComponent()
          .appendingPathComponent("Taste Intelligence/exposure", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var files: [Data] = []
        for url in urls where url.pathExtension == "jsonl" {
          guard let data = try ListeningCoordinatedFiles.readData(url) else { continue }
          files.append(data)
        }
        return NewMusicExposureCodec.readFiles(files).records
      },
      appendNewMusicWeek: { week in
        let folder = iCloudFolder.deletingLastPathComponent()
          .appendingPathComponent("Taste Intelligence/exposure", isDirectory: true)
        try ListeningCoordinatedFiles.append(NewMusicExposureCodec.encode(week),
          to: folder.appendingPathComponent(Self.safeFileComponent(week.host) + ".jsonl"))
      },
      appendNewMusicGap: { gap in
        let folder = iCloudFolder.deletingLastPathComponent()
          .appendingPathComponent("Taste Intelligence/exposure", isDirectory: true)
        try ListeningCoordinatedFiles.append(NewMusicExposureCodec.encode(gap),
          to: folder.appendingPathComponent(Self.safeFileComponent(gap.host) + ".jsonl"))
      },
      readNewMusicAttemptAt: { try ListeningLocalState(folder: localFolder).newMusicAttemptAt() },
      writeNewMusicAttemptAt: { date in try ListeningLocalState(folder: localFolder).writeNewMusicAttemptAt(date) },
      hostName: hostName
    )
  }

  private static func month(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
  }

  private static func safeFileComponent(_ value: String) -> String {
    let safe = value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_" }.joined()
    return safe.isEmpty ? "Mac" : safe
  }

  private static func months(around date: Date) -> [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let current = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    let previous = calendar.date(byAdding: .month, value: -1, to: current)!
    return [month(for: current), month(for: previous)]
  }
}

public struct NewMusicExposureReadResult: Equatable, Sendable {
  public var records: [NewMusicExposureRecord]
  public var skippedLines: Int
  public init(records: [NewMusicExposureRecord], skippedLines: Int) {
    self.records = records; self.skippedLines = skippedLines
  }
}

public enum NewMusicExposureCodec {
  public static func encode(_ week: NewMusicWeek) throws -> Data { try line(week) }
  public static func encode(_ gap: NewMusicExposureGap) throws -> Data { try line(gap) }

  public static func decodeJSONL(_ data: Data) -> [NewMusicExposureRecord] {
    decodeJSONLReport(data).records
  }

  public static func decodeJSONLReport(_ data: Data) -> NewMusicExposureReadResult {
    let bytes = [UInt8](data)
    let complete = bytes.last == 0x0A ? bytes.count : (bytes.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0)
    guard complete > 0 else { return NewMusicExposureReadResult(records: [], skippedLines: 0) }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let iso = ISO8601DateFormatter()
      iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = iso.date(from: value) { return date }
      iso.formatOptions = [.withInternetDateTime]
      guard let date = iso.date(from: value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO timestamp") }
      return date
    }
    var records: [NewMusicExposureRecord] = []
    var skippedLines = 0
    for line in String(decoding: bytes[..<complete], as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
      guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      let lineData = Data(line.utf8)
      let header = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
      let format = header?["format"] as? String
      let version = header?["version"] as? Int
      if format == "vf-new-music-week", version == 1,
        let value = try? decoder.decode(NewMusicWeek.self, from: lineData) {
        records.append(.week(value)); continue
      }
      if format == "vf-new-music-exposure-gap", version == 1,
        let value = try? decoder.decode(NewMusicExposureGap.self, from: lineData) {
        records.append(.gap(value)); continue
      }
      skippedLines += 1
    }
    return NewMusicExposureReadResult(records: records, skippedLines: skippedLines)
  }

  public static func readFiles(_ files: [Data]) -> NewMusicExposureReadResult {
    let reports = files.map(decodeJSONLReport)
    let records = reports.flatMap(\.records)
    let weeks = Dictionary(grouping: records.compactMap { record -> (Date, NewMusicWeek)? in
      guard case let .week(week) = record else { return nil }
      return (week.lastModifiedDate, week)
    }, by: \.0).values.compactMap { $0.max(by: { $0.1.fetchedAt < $1.1.fetchedAt })?.1 }
    let gaps = records.compactMap { record -> NewMusicExposureRecord? in
      if case .gap = record { return record }; return nil
    }
    return NewMusicExposureReadResult(records: weeks.sorted { $0.lastModifiedDate > $1.lastModifiedDate }.map(NewMusicExposureRecord.week) + gaps,
      skippedLines: reports.reduce(0) { $0 + $1.skippedLines })
  }

  private static func line<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    var data = try encoder.encode(value); data.append(0x0A); return data
  }
}

private struct ListeningLocalState {
  var folder: URL

  func pollerID() throws -> UUID {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("poller.json")
    if FileManager.default.fileExists(atPath: url.path) {
      return try JSONDecoder().decode(PollerID.self, from: Data(contentsOf: url)).poller
    }
    let poller = UUID()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(PollerID(poller: poller)).write(to: url, options: .atomic)
    return poller
  }

  func lastList() throws -> [ListeningItem]? {
    let url = folder.appendingPathComponent("last-list.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode([ListeningItem].self, from: Data(contentsOf: url))
  }

  func writeLastList(_ items: [ListeningItem]) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(items).write(to: folder.appendingPathComponent("last-list.json"), options: .atomic)
  }

  func clearLastList() throws {
    let url = folder.appendingPathComponent("last-list.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  func handoverMarker() throws -> ListeningHandoverMarker? {
    let url = folder.appendingPathComponent("handover.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(ListeningHandoverMarker.self, from: Data(contentsOf: url))
  }

  func writeHandoverMarker(_ marker: ListeningHandoverMarker) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(marker).write(to: folder.appendingPathComponent("handover.json"), options: .atomic)
  }

  func clearHandoverMarker() throws {
    let url = folder.appendingPathComponent("handover.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  func lastPollError() throws -> String? {
    let url = folder.appendingPathComponent("last-poll-error.txt")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try String(contentsOf: url, encoding: .utf8)
  }

  func writePollError(_ error: String?) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("last-poll-error.txt")
    guard let error else {
      if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
      return
    }
    try Data(error.utf8).write(to: url, options: .atomic)
  }

  func newMusicAttemptAt() throws -> Date? {
    let url = folder.appendingPathComponent("new-music-last-attempt.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(NewMusicAttempt.self, from: Data(contentsOf: url)).at
  }

  func writeNewMusicAttemptAt(_ date: Date) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(NewMusicAttempt(at: date)).write(to: folder.appendingPathComponent("new-music-last-attempt.json"), options: .atomic)
  }

  private struct PollerID: Codable {
    var poller: UUID
  }
  private struct NewMusicAttempt: Codable { var at: Date }
}

private enum ListeningCoordinatedFiles {
  static func readData(_ url: URL) throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try coordinated(url, writing: false) { coordinatedURL in
      try Data(contentsOf: coordinatedURL)
    }
  }

  static func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try coordinated(url, writing: true, options: .forReplacing) { coordinatedURL in
      try data.write(to: coordinatedURL, options: .atomic)
    }
  }

  static func append(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try coordinated(url, writing: true, options: .forMerging) { coordinatedURL in
      if !FileManager.default.fileExists(atPath: coordinatedURL.path) {
        FileManager.default.createFile(atPath: coordinatedURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: coordinatedURL)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.synchronize()
    }
  }

  private static func coordinated<T>(
    _ url: URL,
    writing: Bool,
    options: NSFileCoordinator.WritingOptions = [],
    accessor: (URL) throws -> T
  ) throws -> T {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<T, Error>?
    if writing {
      coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
        result = Result { try accessor(target) }
      }
    } else {
      coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
        result = Result { try accessor(target) }
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileReadUnknown) }
    return try result.get()
  }
}
