import Foundation

struct ProbeLogWriter {
  private static let failureKey = "probe-previous-write-failure"

  var defaults: UserDefaults = .standard
  var appendData: (Data, URL) throws -> Void = Self.append

  @discardableResult
  func write(_ source: ProbeRecord, to url: URL) throws -> ProbeRecord {
    var record = source
    record.previousWriteFailure = Self.failure(in: defaults)?.error
    do {
      try appendData(ProbeRecord.encodeLine(record), url)
      defaults.removeObject(forKey: Self.failureKey)
      return record
    } catch {
      Self.saveFailure(time: record.time, error: error.localizedDescription, in: defaults)
      throw error
    }
  }

  static func saveFailure(time: Date, error: String, in defaults: UserDefaults = .standard) {
    let failure = ProbeWriteFailure(time: time, error: error)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(failure) {
      defaults.set(data, forKey: failureKey)
    }
  }

  private static func failure(in defaults: UserDefaults) -> ProbeWriteFailure? {
    guard let data = defaults.data(forKey: failureKey) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(ProbeWriteFailure.self, from: data)
  }

  private static func append(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { coordinatedURL in
      do {
        if FileManager.default.fileExists(atPath: coordinatedURL.path) {
          let handle = try FileHandle(forWritingTo: coordinatedURL)
          defer { try? handle.close() }
          try handle.seekToEnd()
          try handle.write(contentsOf: data)
        } else {
          try data.write(to: coordinatedURL, options: .atomic)
        }
      } catch {
        writeError = error
      }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }
}

private struct ProbeWriteFailure: Codable {
  var time: Date
  var error: String
}
