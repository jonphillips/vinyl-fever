import Foundation
import VinylFeverNotes

enum PlaylistListeningLogReader {
  static func read(
    folder: URL,
    from oldestDate: Date,
    now: Date,
    deadline: Date = Date().addingTimeInterval(8),
    startDownload: @escaping @Sendable (URL) throws -> Void = {
      try FileManager.default.startDownloadingUbiquitousItem(at: $0)
    },
    coordinatedRead: @escaping @Sendable (URL) throws -> Data = coordinatedRead
  ) throws -> [ListeningPlay] {
    let root = folder.appending(path: "Listening/fetches", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: root.path) else { throw CocoaError(.fileNoSuchFile) }
    let oldestMonth = monthKey(oldestDate)
    let latestMonth = monthKey(now)
    guard let enumerator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
      throw CocoaError(.fileReadUnknown)
    }

    var urls: [URL] = []
    for case let url as URL in enumerator {
      let filename = url.lastPathComponent
      let actual: String
      if filename.hasPrefix("."), filename.hasSuffix(".icloud") {
        actual = String(filename.dropFirst().dropLast(".icloud".count))
      } else if filename.hasSuffix(".icloud") {
        actual = String(filename.dropLast(".icloud".count))
      } else {
        actual = filename
      }
      guard actual.hasSuffix(".jsonl"), let month = actual.split(separator: ".").first.map(String.init),
        month.count == 7, month >= oldestMonth, month <= latestMonth else { continue }
      let readableURL = filename.hasSuffix(".icloud")
        ? url.deletingLastPathComponent().appendingPathComponent(actual)
        : url
      urls.append(readableURL)
    }
    urls.sort { $0.path < $1.path }

    let group = DispatchGroup()
    let results = PlaylistLogReadResults()
    for url in urls {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        defer { group.leave() }
        do {
          try startDownload(url)
          results.append(try coordinatedRead(url))
        } catch {
          results.fail(error)
        }
      }
    }
    guard group.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success else {
      throw PlaylistLogReadError.timedOut
    }
    let streams = try results.read()
    return try ListeningLog(jsonlStreams: streams, now: now).plays
  }

  private static func monthKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: date)
  }

  static func coordinatedRead(_ url: URL) throws -> Data {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var readError: Error?
    var data: Data?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      do { data = try Data(contentsOf: coordinatedURL) } catch { readError = error }
    }
    if let coordinationError { throw coordinationError }
    if let readError { throw readError }
    guard let data else { throw CocoaError(.fileReadUnknown) }
    return data
  }
}

private final class PlaylistLogReadResults: @unchecked Sendable {
  private let lock = NSLock()
  private var streams: [Data] = []
  private var firstError: Error?

  func append(_ data: Data) {
    lock.lock(); streams.append(data); lock.unlock()
  }

  func fail(_ error: Error) {
    lock.lock()
    if firstError == nil { firstError = error }
    lock.unlock()
  }

  func read() throws -> [Data] {
    lock.lock(); defer { lock.unlock() }
    if let firstError { throw firstError }
    return streams
  }
}

private enum PlaylistLogReadError: Error {
  case timedOut
}
