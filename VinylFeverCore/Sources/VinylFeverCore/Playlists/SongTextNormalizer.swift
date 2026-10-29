#if os(macOS)
import VinylFeverListening

/// Compatibility facade for library matching; `VinylFeverListening` owns the shared rules.
enum SongTextNormalizer {
  static func artist(_ raw: String) -> String { ListeningTextNormalizer.artist(raw) }
  static func title(_ raw: String) -> String { ListeningTextNormalizer.title(raw) }
  static func libraryTitle(_ raw: String) -> String { ListeningTextNormalizer.libraryTitle(raw) }
  static func album(_ raw: String) -> String { ListeningTextNormalizer.album(raw) }
  static func text(_ raw: String) -> String { ListeningTextNormalizer.text(raw) }
}
#endif
