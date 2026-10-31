import Foundation

/// The canonical title-and-artist key shared by the Mac classifier and the mobile playlist view.
/// The Mac passes its alias-aware identity; the phone has no aliases and uses `.empty`.
public enum ListeningTrackKey {
  public static func make(artist: String, title: String, identity: ArtistIdentity = .empty) -> String {
    "\(identity.key(artist))|\(ListeningTextNormalizer.libraryTitle(title))"
  }
}
