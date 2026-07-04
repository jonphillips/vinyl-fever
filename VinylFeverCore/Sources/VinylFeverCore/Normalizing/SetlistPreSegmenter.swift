import Foundation

/// A candidate region the pre-segmenter labels for the model. These are **hints,
/// never decisions**: the segmenter never decides what is or isn't a track — it
/// annotates structure so the LLM leg has scaffolding, and the model is free to
/// disagree (it reads the cleaned text too).
public enum SetlistRegionKind: String, Equatable, Sendable, CaseIterable {
  /// Leading tag-ish / identity lines (artist, date, venue, `KEY: value`).
  case header
  /// Numbered items and disc/set/encore structural headers.
  case tracklist
  /// Recording provenance — source, taper, transfer chain, checksummed formats.
  case lineage
  /// Free paragraphs, "complete set" re-lists, trading chatter.
  case prose
}

public struct SetlistRegion: Equatable, Sendable {
  public var kind: SetlistRegionKind
  public var lines: [String]

  public init(kind: SetlistRegionKind, lines: [String]) {
    self.kind = kind
    self.lines = lines
  }

  public var text: String { lines.joined(separator: "\n") }
}

public struct PreSegmentedNotes: Equatable, Sendable {
  /// The raw input after CRLF/BOM/trailing-whitespace normalization and hash-block
  /// excision. This is what the model reads — nothing but mechanical checksum noise
  /// is removed.
  public var cleanedText: String
  public var regions: [SetlistRegion]
  /// The excised FFP/MD5/shntool lines, kept for the drop audit.
  public var removedHashLines: [String]

  public init(cleanedText: String, regions: [SetlistRegion], removedHashLines: [String]) {
    self.cleanedText = cleanedText
    self.regions = regions
    self.removedHashLines = removedHashLines
  }
}

/// Bookend 1 of the Normalizer sandwich (setlist-formatting-rules.md, *Pre-segment*):
/// normalize whitespace, excise mechanical hash blocks (FFP/MD5/shntool), and label
/// candidate regions. Pure and model-free.
public struct SetlistPreSegmenter: Sendable {
  public init() {}

  public func segment(_ raw: String) -> PreSegmentedNotes {
    let normalizedLines = Self.normalizedLines(raw)

    var keptLines: [String] = []
    var removedHashLines: [String] = []
    for line in normalizedLines {
      if Self.isHashLine(line) {
        removedHashLines.append(line)
      } else {
        keptLines.append(line)
      }
    }

    let cleanedText = keptLines
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return PreSegmentedNotes(
      cleanedText: cleanedText,
      regions: Self.regions(from: keptLines),
      removedHashLines: removedHashLines
    )
  }

  // MARK: - Normalization

  static func normalizedLines(_ raw: String) -> [String] {
    raw
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        String(line)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
          // Trailing whitespace only — leading indentation can carry meaning to the model.
          .replacingOccurrences(
            of: "[ \\t]+$", with: "", options: .regularExpression
          )
      }
  }

  // MARK: - Hash-block excision

  /// Mechanical checksum lines: shntool report rows, `.ffp` fingerprints, and `.md5`
  /// manifests. Token-heavy and semantically empty — excised so they don't cost model
  /// tokens or get mistaken for tracks. Detection is conservative: only lines that are
  /// clearly a checksum, never prose that merely mentions one.
  static func isHashLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }
    let lower = trimmed.lowercased()

    // `filename.flac:AABBCC…` FFP fingerprint, or `AABBCC…  filename` MD5 manifest.
    if let colon = trimmed.lastIndex(of: ":"),
      isLongHex(String(trimmed[trimmed.index(after: colon)...]))
    {
      return true
    }
    if let firstField = trimmed.split(whereSeparator: \.isWhitespace).first,
      isLongHex(String(firstField))
    {
      return true
    }
    // shntool `len expanded_size cdr wave problems filename` rows and its headers.
    if lower.hasPrefix("length") && lower.contains("expanded") { return true }
    if lower.contains("shntool") { return true }

    return false
  }

  private static func isLongHex(_ token: String) -> Bool {
    let hex = token.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
    guard hex.count >= 16 else { return false }
    return hex.allSatisfy(\.isHexDigit)
  }

  // MARK: - Region classification

  private static func regions(from lines: [String]) -> [SetlistRegion] {
    var regions: [SetlistRegion] = []
    var sawTrackContext = false

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      let kind = classify(trimmed, sawTrackContext: sawTrackContext)
      if kind == .tracklist { sawTrackContext = true }

      if var last = regions.last, last.kind == kind {
        last.lines.append(trimmed)
        regions[regions.count - 1] = last
      } else {
        regions.append(SetlistRegion(kind: kind, lines: [trimmed]))
      }
    }

    return regions
  }

  private static func classify(_ line: String, sawTrackContext: Bool) -> SetlistRegionKind {
    if looksLikeNumberedTrack(line) || isStructuralHeader(line) {
      return .tracklist
    }
    if isLineageLine(line) {
      return .lineage
    }
    if isHeaderTag(line) {
      return .header
    }
    // Once the track list has started, short bare lines are most likely un-numbered
    // tracks; long sentences are trailing prose. Before any track context, bare lines
    // near the top read as header identity.
    if sawTrackContext {
      return isSentenceLike(line) ? .prose : .tracklist
    }
    return .prose
  }

  static func looksLikeNumberedTrack(_ line: String) -> Bool {
    var scan = Substring(line)

    // Optional `dN` / `dNtNN` disc prefix.
    if let first = scan.first, first == "d" || first == "D" {
      var probe = scan.dropFirst()
      let digits = probe.prefix(while: \.isNumber)
      if !digits.isEmpty {
        probe = probe.dropFirst(digits.count)
        if let t = probe.first, t == "t" || t == "T" {
          scan = probe.dropFirst()
        }
      }
    }

    let digits = scan.prefix(while: \.isNumber)
    guard (1...3).contains(digits.count) else { return false }
    let rest = scan.dropFirst(digits.count)
    guard let separator = rest.first else { return false }

    if separator == "." || separator == ")" {
      // `NN. Title` / `NN) Title` — require something after the separator.
      return rest.dropFirst().contains(where: { !$0.isWhitespace })
    }
    // `01 Title` zero-padded with a space is also a common track shape.
    if separator == " ", digits.count > 1, digits.first == "0" {
      return rest.dropFirst().contains(where: { !$0.isWhitespace })
    }
    return false
  }

  private static func isStructuralHeader(_ line: String) -> Bool {
    let normalized = line.uppercased().replacingOccurrences(of: ":", with: "")
    let prefixes = ["DISC", "CD", "SET", "ENCORE", "END OF PART"]
    return prefixes.contains { prefix in
      normalized == prefix || normalized.hasPrefix(prefix + " ")
    }
  }

  private static let headerKeys: Set<String> = [
    "ARTIST", "ALBUM", "ALBUMARTIST", "DATE", "VENUE", "LOCATION", "TITLE", "CITY",
  ]

  private static func isHeaderTag(_ line: String) -> Bool {
    guard let colon = line.firstIndex(of: ":") else { return false }
    let key = line[..<colon]
      .trimmingCharacters(in: .whitespaces)
      .uppercased()
      .filter { !$0.isWhitespace }
    return headerKeys.contains(key)
  }

  private static let lineageMarkers: [String] = [
    "source:", "lineage:", "recording:", "transfer:", "taper", "microphone", "mics",
    "soundboard", "matrix", "neumann", "schoeps", "sennheiser", "->", " > ", "24bit",
    "16bit", "khz", "sample rate", "seeded", "eac ", "shntool", "flac fingerprint",
    "recorded by", "taped by", "dat master", "cassette master",
  ]

  private static func isLineageLine(_ line: String) -> Bool {
    let lower = " " + line.lowercased() + " "
    return lineageMarkers.contains { lower.contains($0) }
  }

  /// A rough "this is a sentence, not a title" test: multiple words ending in
  /// terminal punctuation, or conspicuously long. Only consulted after the track
  /// list has begun, to split trailing prose from un-numbered tracks.
  private static func isSentenceLike(_ line: String) -> Bool {
    if line.count > 60 { return true }
    let words = line.split(whereSeparator: \.isWhitespace)
    let last = line.last
    return words.count >= 6 && (last == "." || last == "!" || last == "?")
  }
}
