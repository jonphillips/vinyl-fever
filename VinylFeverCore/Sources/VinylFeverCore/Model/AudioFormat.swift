import Foundation

public enum AudioFormat: String, CaseIterable, Equatable, Hashable, Sendable {
  case flac
  case mp3
  case m4a

  public init?(pathExtension: String) {
    self.init(rawValue: pathExtension.lowercased())
  }
}
