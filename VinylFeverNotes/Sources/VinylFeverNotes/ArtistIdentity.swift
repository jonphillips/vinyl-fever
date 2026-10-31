import Foundation

/// Shared artist normalization and credit matching for library and listening surfaces.
public struct ArtistIdentity: Equatable, Sendable {
  public static let empty = ArtistIdentity(aliases: [:], knownArtists: [])

  private let aliases: [String: String]
  private let knownArtists: Set<String>

  public init(aliases: [String: String] = [:], knownArtists: Set<String>) {
    let normalizedAliases = aliases.reduce(into: [String: String]()) { result, entry in
      let variant = Self.baseKey(entry.key)
      let canonical = Self.baseKey(entry.value)
      if !variant.isEmpty, !canonical.isEmpty, variant != canonical {
        // Alias input is expected to be canonicalized by the decision store, but
        // collapsing here keeps imported/exported maps safe as well.
        var target = canonical
        var visited: Set<String> = [variant]
        while let next = aliases[target].map(Self.baseKey), !next.isEmpty,
          visited.insert(target).inserted
        {
          target = next
        }
        result[variant] = target
      }
    }
    self.aliases = normalizedAliases
    self.knownArtists = Set(knownArtists.map(Self.baseKey).filter { !$0.isEmpty })
  }

  /// Normalizes spelling, leading/trailing articles, and band/live suffixes.
  public static func baseKey(_ raw: String) -> String {
    var value = raw
    for apostrophe in ["'", "’", "‘", "ʻ", "`", "´"] {
      value = value.replacingOccurrences(of: apostrophe, with: "")
    }
    value = value.replacingOccurrences(of: "+", with: " and ")
    var key = ListeningTextNormalizer.artist(value)
    guard !key.isEmpty else { return "" }

    if key.hasPrefix("the ") { key = String(key.dropFirst(4)) }
    if key.hasSuffix(" the") { key = String(key.dropLast(4)) }
    if key.isEmpty { return "the" }

    var previous: String
    repeat {
      previous = key
      for suffix in [" live", " solo"] where key.hasSuffix(suffix) {
        key = String(key.dropLast(suffix.count))
      }
      for marker in [" and the ", " and his ", " and her "] {
        if let range = key.range(of: marker) { key = String(key[..<range.lowerBound]) }
      }
      key = key.trimmingCharacters(in: .whitespaces)
    } while key != previous
    return key.isEmpty ? "the" : key
  }

  public func key(_ raw: String) -> String {
    let base = Self.baseKey(raw)
    return aliases[base] ?? base
  }

  /// Returns the artist's own key and any known collaborator credits.
  public func credits(_ raw: String) -> Set<String> {
    let base = Self.baseKey(raw)
    let artistKey = aliases[base] ?? base
    guard !artistKey.isEmpty else { return [] }
    var result: Set<String> = [artistKey]
    let foldedRaw = ListeningTextNormalizer.artist(
      raw.replacingOccurrences(of: "+", with: " and "))
    if [" and the ", " and his ", " and her "].contains(where: foldedRaw.contains) {
      return result
    }
    let withoutTrailingCredits = raw.replacingOccurrences(
      of: #"\b(feat\.?|ft\.?|with)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
    let separated = withoutTrailingCredits
      .replacingOccurrences(of: "&", with: " and ")
      .replacingOccurrences(of: "+", with: " and ")
      .replacingOccurrences(
        of: #"\s+(?:and|x|vs)\s+|,\s*"#, with: "|", options: [.regularExpression, .caseInsensitive])
    let parts = separated.split(separator: "|").map { Self.baseKey(String($0)) }
      .filter { !$0.isEmpty }
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard parts.count > 1 else { return result }
    let keyedParts = parts.map { aliases[$0] ?? $0 }
    for part in keyedParts where knownArtists.contains(part) && !Self.isGenericCredit(part) {
      let words = part.split(separator: " ")
      if words.count >= 2 || keyedParts.allSatisfy(knownArtists.contains) {
        result.insert(part)
      }
    }
    return result
  }

  public func matches(request: String, track: String) -> Bool {
    credits(track).contains(key(request))
  }

  private static func isGenericCredit(_ value: String) -> Bool {
    ["band", "friends", "others", "family", "orchestra", "guests"].contains(value)
  }
}
