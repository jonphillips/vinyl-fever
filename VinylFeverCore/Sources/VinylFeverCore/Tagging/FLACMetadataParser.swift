import Foundation

public enum FLACMetadataParser {
  public static func parse(
    tagsOutput: String,
    streamInfoOutput: String,
    pictureListOutput: String
  ) -> AudioTags {
    let tags = VorbisCommentParser.parse(tagsOutput)
    let trackNumber = TagValueParser.leadingInteger(tags.firstValue(for: ["TRACKNUMBER", "TRACK"]))
    let trackTotal =
      TagValueParser.leadingInteger(tags.firstValue(for: ["TRACKTOTAL", "TOTALTRACKS"]))
      ?? TagValueParser.trailingTotal(tags.firstValue(for: ["TRACKNUMBER", "TRACK"]))
    let discNumber = TagValueParser.leadingInteger(tags.firstValue(for: ["DISCNUMBER", "DISC"]))
    let streamInfo = parseStreamInfo(streamInfoOutput)

    return AudioTags(
      title: tags.joinedValues(for: ["TITLE"]),
      artist: tags.joinedValues(for: ["ARTIST"]),
      album: tags.joinedValues(for: ["ALBUM"]),
      sortAlbum: tags.joinedValues(for: ["ALBUMSORT", "ALBUM SORT"]),
      albumArtist: tags.joinedValues(for: ["ALBUMARTIST", "ALBUM ARTIST"]),
      trackNumber: trackNumber,
      trackTotal: trackTotal,
      discNumber: discNumber,
      durationSeconds: streamInfo.durationSeconds,
      hasAudioStream: streamInfo.hasAudioStream,
      hasEmbeddedArtwork: hasPicture(pictureListOutput)
    )
  }

  private static func parseStreamInfo(_ output: String) -> FLACStreamInfo {
    // Kept in lockstep with AudioMetadataCommands.flacStreamInfo: line 0 is
    // total samples, line 1 is sample rate.
    let values = output
      .split(whereSeparator: \.isNewline)
      .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    let durationSeconds =
      if values.count >= 2, values[1] > 0 {
        values[0] / values[1]
      } else {
        Double?.none
      }
    return FLACStreamInfo(
      durationSeconds: durationSeconds,
      hasAudioStream: !values.isEmpty
    )
  }

  private struct FLACStreamInfo {
    var durationSeconds: Double?
    var hasAudioStream: Bool
  }

  private static func hasPicture(_ output: String) -> Bool {
    output
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .contains { line in
        line.hasPrefix("type:") || line.hasPrefix("mime type:")
      }
  }
}

private struct VorbisCommentParser {
  var valuesByKey: [String: [String]]

  static func parse(_ output: String) -> Self {
    var valuesByKey: [String: [String]] = [:]
    for line in output.split(whereSeparator: \.isNewline) {
      let text = String(line)
      guard let separator = text.firstIndex(of: "=") else {
        continue
      }
      let key = text[..<separator]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
      let value = text[text.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty, !value.isEmpty else {
        continue
      }
      valuesByKey[key, default: []].append(value)
    }
    return Self(valuesByKey: valuesByKey)
  }

  func firstValue(for keys: [String]) -> String? {
    keys.lazy.compactMap { valuesByKey[$0]?.first }.first
  }

  func joinedValues(for keys: [String]) -> String? {
    let values = keys.flatMap { valuesByKey[$0] ?? [] }
    guard !values.isEmpty else {
      return nil
    }
    return values.joined(separator: " / ")
  }
}

enum TagValueParser {
  static func leadingInteger(_ value: String?) -> Int? {
    guard let value else {
      return nil
    }
    let digits = value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(while: \.isNumber)
    return Int(digits)
  }

  static func trailingTotal(_ value: String?) -> Int? {
    guard let value, let slash = value.firstIndex(of: "/") else {
      return nil
    }
    let totalText = value[value.index(after: slash)...]
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(totalText.prefix(while: \.isNumber))
  }
}
