import Foundation
import VinylFeverNotes

public struct TrackRequest: Equatable, Sendable {
  public let index: Int
  public let artist: String
  public let title: String
  public let album: String?
  public let year: Int?

  public init(index: Int, artist: String, title: String, album: String? = nil, year: Int? = nil) {
    self.index = index
    self.artist = artist
    self.title = title
    self.album = album
    self.year = year
  }
}

public struct PlaylistRequest: Equatable, Sendable {
  public let name: String
  public let description: String?
  public let tracks: [TrackRequest]

  public init(name: String, description: String? = nil, tracks: [TrackRequest]) {
    self.name = name
    self.description = description
    self.tracks = tracks
  }
}
