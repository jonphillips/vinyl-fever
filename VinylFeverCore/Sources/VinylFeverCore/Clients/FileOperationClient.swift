import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct FileOperationClient: Sendable {
  public var fileExists: @Sendable (_ url: URL) async throws -> Bool
  public var createDirectory: @Sendable (_ url: URL) async throws -> Void
  public var directoryFiles: @Sendable (_ url: URL) async throws -> [URL]
  public var copyFile: @Sendable (_ source: URL, _ destination: URL) async throws -> Void
  public var replaceFile: @Sendable (_ source: URL, _ destination: URL) async throws -> Void
  /// Best-effort delete. Removing a URL that does not exist is a no-op, not an error,
  /// so failure-path cleanup can call it unconditionally.
  public var removeItem: @Sendable (_ url: URL) async throws -> Void
  public var writeData: @Sendable (_ data: Data, _ destination: URL) async throws -> Void
  public var reveal: @Sendable (_ url: URL) async throws -> Void
}

extension FileOperationClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension DependencyValues {
  public var fileOperationClient: FileOperationClient {
    get { self[FileOperationClient.self] }
    set { self[FileOperationClient.self] = newValue }
  }
}

public enum FileOperationError: LocalizedError, Equatable, Sendable {
  case destinationExists(URL)
  case replacementSourceMissing(URL)

  public var errorDescription: String? {
    switch self {
    case let .destinationExists(url):
      "\(url.path(percentEncoded: false)) already exists."
    case let .replacementSourceMissing(url):
      "Replacement file \(url.path(percentEncoded: false)) does not exist."
    }
  }
}
