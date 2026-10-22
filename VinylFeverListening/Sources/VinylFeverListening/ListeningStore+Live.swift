import Foundation
import SystemConfiguration

extension ListeningStore {
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
    hostName: @escaping @Sendable () -> String = {
      SCDynamicStoreCopyComputerName(nil, nil) as String? ?? Host.current().localizedName ?? "Mac"
    }
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
      readHandoverFetches: { poller, now in
        let stream = iCloudFolder
          .appendingPathComponent("fetches", isDirectory: true)
          .appendingPathComponent(poller.uuidString, isDirectory: true)
        var records: [ListeningFetch] = []
        for month in Self.months(around: now) {
          let file = stream.appendingPathComponent(month + ".jsonl")
          guard let data = try ListeningCoordinatedFiles.readData(file) else { continue }
          records.append(contentsOf: try ListeningLogCodec.decodeJSONL(data))
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
      hostName: hostName
    )
  }

  private static func month(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
  }

  private static func months(around date: Date) -> [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let current = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    let previous = calendar.date(byAdding: .month, value: -1, to: current)!
    return [month(for: current), month(for: previous)]
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

  private struct PollerID: Codable {
    var poller: UUID
  }
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
