import Foundation

public struct ScannedAudioFile: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var url: URL
  public var format: AudioFormat
  public var sortKey: String

  public init(id: UUID, url: URL, format: AudioFormat, sortKey: String) {
    self.id = id
    self.url = url
    self.format = format
    self.sortKey = sortKey
  }
}
