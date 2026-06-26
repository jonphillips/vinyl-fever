import Foundation

public struct ScannedShowFolder: Equatable, Sendable {
  public var root: URL
  public var audioFiles: [ScannedAudioFile]
  public var setlistCandidates: [URL]
  public var coverCandidates: [URL]

  public init(
    root: URL,
    audioFiles: [ScannedAudioFile],
    setlistCandidates: [URL],
    coverCandidates: [URL]
  ) {
    self.root = root
    self.audioFiles = audioFiles
    self.setlistCandidates = setlistCandidates
    self.coverCandidates = coverCandidates
  }
}
