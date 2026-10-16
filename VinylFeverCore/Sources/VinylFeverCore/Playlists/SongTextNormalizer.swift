import Foundation

/// Shared normalization for catalog matching and library lookups.
enum SongTextNormalizer {
  static func artist(_ raw: String) -> String {
    text(
      raw.replacingOccurrences(
        of: #"\b(feat\.?|ft\.?|with)\b.*$"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
      ))
  }

  static func title(_ raw: String) -> String {
    var value = raw
    value = value.replacingOccurrences(
      of: #"\s*[\(\[]\s*(feat\.?|ft\.?|with)\b[^)\]]*[)\]]"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    value = value.replacingOccurrences(
      of: #"\s*[\(\[](?:(?:19|20)\d{2}\s+)?remaster(?:ed)?[^)\]]*[)\]]"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    value = value.replacingOccurrences(
      of: #"\s+[-–—]\s+(?:(?:19|20)\d{2}\s+)?remaster(?:ed)?(?:\s+(?:19|20)\d{2})?\s*$"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    return text(value)
  }

  /// Library metadata often stores a guest credit directly in the title. Keep this
  /// additional cleanup out of catalog scoring so its established score stays stable.
  static func libraryTitle(_ raw: String) -> String {
    text(
      raw.replacingOccurrences(
        of: #"\s+(?:feat\.?|ft\.?|featuring|with)\s+.*$"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
      ))
  }

  static func album(_ raw: String) -> String { text(raw) }

  static func text(_ raw: String) -> String {
    var value = raw.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    value = value.replacingOccurrences(of: "&", with: " and ")
    value = value.replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
    return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
