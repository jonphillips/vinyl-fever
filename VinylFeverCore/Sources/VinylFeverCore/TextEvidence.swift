import Foundation

/// Case- and whitespace-insensitive substring test: does `needle` actually appear
/// in `haystack`? A genuine quotation passes; an invented string fails.
///
/// Shared by two guards that ask the same question of a language model — "is this
/// value grounded in the input, or did you make it up?": the setlist normalizer's
/// `sourceEvidence` check and the collection-recipe verbatim guard. One
/// implementation so the two can never drift.
public enum TextEvidence {
  public static func appears(_ needle: String, in haystack: String) -> Bool {
    let needle = collapse(needle)
    guard !needle.isEmpty else { return false }
    return collapse(haystack).contains(needle)
  }

  /// Lowercased, with every run of whitespace flattened to a single space, so a
  /// real match survives spacing and case differences between the two texts.
  static func collapse(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
