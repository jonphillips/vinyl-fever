import Foundation

public struct AudioTags: Equatable, Sendable {
  public var title: String?
  public var artist: String?
  public var album: String?
  public var albumArtist: String?
  public var trackNumber: Int?
  public var trackTotal: Int?
  public var discNumber: Int?
  public var durationSeconds: Double?
  public var hasAudioStream: Bool
  public var hasEmbeddedArtwork: Bool

  public init(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    albumArtist: String? = nil,
    trackNumber: Int? = nil,
    trackTotal: Int? = nil,
    discNumber: Int? = nil,
    durationSeconds: Double? = nil,
    hasAudioStream: Bool = false,
    hasEmbeddedArtwork: Bool = false
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.albumArtist = albumArtist
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.durationSeconds = durationSeconds
    self.hasAudioStream = hasAudioStream
    self.hasEmbeddedArtwork = hasEmbeddedArtwork
  }
}

public enum AudioMetadataLoadState: Equatable, Sendable {
  case notLoaded
  case loading
  case loaded(AudioTags)
  case failed(String)

  public var tags: AudioTags? {
    if case let .loaded(tags) = self {
      tags
    } else {
      nil
    }
  }
}
