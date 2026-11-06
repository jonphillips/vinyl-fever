import Foundation

public enum JSONLAppend {
  public static func errorDescription(step: String, to url: URL, underlying: Error) -> String {
    let components = url.pathComponents.suffix(2).joined(separator: "/")
    let error = underlying as NSError
    let cause = (error.userInfo[NSUnderlyingErrorKey] as? NSError) ?? error
    return "Couldn't save \(components) (\(step)): \(cause.domain) \(cause.code), \(cause.localizedDescription)"
  }

  public static func append(_ data: Data, to url: URL) throws {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      throw JSONLAppendError(step: "create folder", url: url, underlying: error)
    }

    let coordinator = NSFileCoordinator(filePresenter: nil)
    let targetIsDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    if FileManager.default.fileExists(atPath: url.path), !targetIsDirectory {
      var downloadError: NSError?
      coordinator.coordinate(readingItemAt: url, options: [], error: &downloadError) { _ in }
      if let downloadError {
        throw JSONLAppendError(step: "download", url: url, underlying: downloadError)
      }
    }

    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
      do {
        if !FileManager.default.fileExists(atPath: target.path),
          !FileManager.default.createFile(atPath: target.path, contents: nil) {
          throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
      } catch {
        writeError = error
      }
    }
    if let coordinationError {
      throw JSONLAppendError(step: "coordinate", url: url, underlying: coordinationError)
    }
    if let writeError {
      let step = FileManager.default.fileExists(atPath: url.path) ? "write" : "create file"
      throw JSONLAppendError(step: step, url: url, underlying: writeError)
    }
  }
}

private struct JSONLAppendError: LocalizedError {
  var step: String
  var url: URL
  var underlying: Error

  var errorDescription: String? {
    JSONLAppend.errorDescription(step: step, to: url, underlying: underlying)
  }
}
