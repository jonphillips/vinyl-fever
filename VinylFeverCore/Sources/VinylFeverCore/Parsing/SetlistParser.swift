import Dependencies
import Foundation

public struct SetlistParser: Sendable {
  @Dependency(\.uuid) private var uuid

  public init() {
  }

  public func parse(_ input: String) -> SetlistDraft {
    var tags = ShowTags()
    var tracks: [SetlistTrack] = []

    for rawLine in input.normalizedSetlistLines {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else {
        continue
      }

      if applyTag(line, to: &tags) {
        continue
      }

      guard let title = trackTitle(from: line) else {
        continue
      }
      tracks.append(SetlistTrack(id: uuid(), title: title))
    }

    return SetlistDraft(tags: tags, tracks: tracks)
  }

  private func applyTag(_ line: String, to tags: inout ShowTags) -> Bool {
    guard let delimiter = line.firstIndex(of: ":") else {
      return false
    }

    let key = line[..<delimiter]
      .trimmingCharacters(in: .whitespaces)
      .uppercased()
      .filter { !$0.isWhitespace }
    let value = String(line[line.index(after: delimiter)...])

    switch key {
    case "ARTIST":
      tags.artist = Field(value)
    case "ALBUM":
      tags.album = Field(value)
    case "ALBUMARTIST":
      tags.albumArtist = Field(value)
    case "DATE":
      tags.date = DateField(isoString: value)
    case "VENUE":
      tags.venue = Field(value)
    case "LOCATION":
      tags.location = Field(value)
    default:
      return false
    }

    return true
  }

  private func trackTitle(from line: String) -> String? {
    guard !isSeparator(line) else {
      return nil
    }

    if let numberedTitle = numberedTrackTitle(from: line) {
      return cleanedTitle(numberedTitle)
    }

    guard !isStructuralHeader(line) else {
      return nil
    }

    return cleanedTitle(line)
  }

  private func numberedTrackTitle(from line: String) -> String? {
    var index = line.startIndex

    if line[index].lowercased() == "d" {
      let afterD = line.index(after: index)
      var scan = afterD
      while scan < line.endIndex, line[scan].isNumber {
        scan = line.index(after: scan)
      }
      if scan < line.endIndex, line[scan].lowercased() == "t", scan > afterD {
        index = line.index(after: scan)
      }
    }

    let numberStart = index
    while index < line.endIndex, line[index].isNumber {
      index = line.index(after: index)
    }

    guard index > numberStart else {
      return nil
    }

    let digitCount = line.distance(from: numberStart, to: index)
    guard (1...3).contains(digitCount) else {
      return nil
    }

    if index == line.endIndex {
      return nil
    }

    let separator = line[index]
    if separator == "." || separator == ")" || separator == "-" || separator == ":" {
      let titleStart = line.index(after: index)
      return String(line[titleStart...])
    }

    if separator.isWhitespace {
      return String(line[index...])
    }

    return nil
  }

  private func cleanedTitle(_ title: String) -> String? {
    let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  private func isSeparator(_ line: String) -> Bool {
    let characters = line.filter { !$0.isWhitespace }
    guard characters.count >= 3 else {
      return false
    }
    return characters.allSatisfy { $0 == "-" || $0 == "=" || $0 == "_" || $0 == "*" }
  }

  private func isStructuralHeader(_ line: String) -> Bool {
    let normalized = line
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: ":", with: "")

    if normalized == "DISC ONE"
      || normalized == "DISC TWO"
      || normalized == "DISC THREE"
      || normalized == "CD ONE"
      || normalized == "CD TWO"
      || normalized == "SET ONE"
      || normalized == "SET TWO"
      || normalized == "SET THREE"
      || normalized == "SET I"
      || normalized == "SET II"
      || normalized == "ENCORE"
    {
      return true
    }

    return hasStructuralPrefix(normalized, prefix: "DISC ")
      || hasStructuralPrefix(normalized, prefix: "DISC")
      || hasStructuralPrefix(normalized, prefix: "CD ")
      || hasStructuralPrefix(normalized, prefix: "SET ")
      || hasStructuralPrefix(normalized, prefix: "ENCORE ")
      || hasStructuralPrefix(normalized, prefix: "END OF PART ")
  }

  private func hasStructuralPrefix(_ value: String, prefix: String) -> Bool {
    guard value.hasPrefix(prefix) else {
      return false
    }
    let remainder = value.dropFirst(prefix.count)
    return !remainder.isEmpty && remainder.allSatisfy { $0.isNumber }
  }
}

private extension String {
  var normalizedSetlistLines: [String] {
    replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        String(line).trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
      }
  }
}
