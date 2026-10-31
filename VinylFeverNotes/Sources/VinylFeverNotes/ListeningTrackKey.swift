import Foundation

/// The canonical title-and-artist key shared by the Mac classifier and the mobile playlist view.
public enum ListeningTrackKey {
  public static func make(artist: String, title: String) -> String {
    "\(ArtistIdentity.baseKey(artist))|\(ListeningTextNormalizer.libraryTitle(title))"
  }
}
