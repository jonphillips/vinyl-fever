import Foundation

public struct AudioTags: Equatable, Sendable {
  public var title: String?
  public var artist: String?
  public var album: String?
  public var sortAlbum: String?
  public var albumArtist: String?
  public var grouping: String?
  public var comments: String?
  public var isCompilation: Bool?
  public var trackNumber: Int?
  public var trackTotal: Int?
  public var discNumber: Int?
  public var durationSeconds: Double?
  public var hasAudioStream: Bool
  public var hasEmbeddedArtwork: Bool
  public var embeddedArtwork: Data?

  public init(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    sortAlbum: String? = nil,
    albumArtist: String? = nil,
    grouping: String? = nil,
    comments: String? = nil,
    isCompilation: Bool? = nil,
    trackNumber: Int? = nil,
    trackTotal: Int? = nil,
    discNumber: Int? = nil,
    durationSeconds: Double? = nil,
    hasAudioStream: Bool = false,
    hasEmbeddedArtwork: Bool = false,
    embeddedArtwork: Data? = nil
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.sortAlbum = sortAlbum
    self.albumArtist = albumArtist
    self.grouping = grouping
    self.comments = comments
    self.isCompilation = isCompilation
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.durationSeconds = durationSeconds
    self.hasAudioStream = hasAudioStream
    self.hasEmbeddedArtwork = hasEmbeddedArtwork
    self.embeddedArtwork = embeddedArtwork
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
