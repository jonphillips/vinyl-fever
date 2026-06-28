import Foundation

public enum FFProbeMetadataParser {
  public static func parse(_ data: Data) throws -> AudioTags {
    let output: FFProbeOutput
    do {
      output = try JSONDecoder().decode(FFProbeOutput.self, from: data)
    } catch {
      throw AudioMetadataError.invalidFFProbeJSON
    }

    let formatTags = TagDictionary(output.format?.tags ?? [:])
    let streamTags = TagDictionary(output.streams.compactMap(\.tags).first ?? [:])
    let tags = formatTags.mergingFallbacks(from: streamTags)

    let trackValue = tags.firstValue(for: ["track", "tracknumber"])
    let discValue = tags.firstValue(for: ["disc", "discnumber"])
    let durationSeconds =
      output.format?.duration.flatMap(Double.init)
      ?? output.streams.lazy.compactMap { $0.duration.flatMap(Double.init) }.first

    return AudioTags(
      title: tags.joinedValues(for: ["title"]),
      artist: tags.joinedValues(for: ["artist"]),
      album: tags.joinedValues(for: ["album"]),
      sortAlbum: tags.joinedValues(for: ["sort_album", "album_sort", "albumsort"]),
      albumArtist: tags.joinedValues(for: ["album_artist", "album artist", "albumartist"]),
      trackNumber: TagValueParser.leadingInteger(trackValue),
      trackTotal: tags.firstValue(for: ["tracktotal", "totaltracks"]).flatMap(TagValueParser.leadingInteger)
        ?? TagValueParser.trailingTotal(trackValue),
      discNumber: TagValueParser.leadingInteger(discValue),
      durationSeconds: durationSeconds,
      hasAudioStream: output.streams.contains { $0.codecType == "audio" },
      hasEmbeddedArtwork: output.streams.contains { stream in
        stream.disposition?.attachedPic == 1
      }
    )
  }
}

private struct FFProbeOutput: Decodable {
  var streams: [FFProbeStream]
  var format: FFProbeFormat?
}

private struct FFProbeStream: Decodable {
  var codecType: String?
  var duration: String?
  var disposition: FFProbeDisposition?
  var tags: [String: String]?

  private enum CodingKeys: String, CodingKey {
    case codecType = "codec_type"
    case duration
    case disposition
    case tags
  }
}

private struct FFProbeDisposition: Decodable {
  var attachedPic: Int?

  private enum CodingKeys: String, CodingKey {
    case attachedPic = "attached_pic"
  }
}

private struct FFProbeFormat: Decodable {
  var duration: String?
  var tags: [String: String]?
}

private struct TagDictionary {
  var valuesByKey: [String: [String]]

  init(_ tags: [String: String]) {
    var valuesByKey: [String: [String]] = [:]
    for (key, value) in tags {
      let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else {
        continue
      }
      valuesByKey[normalizedKey, default: []].append(normalizedValue)
    }
    self.valuesByKey = valuesByKey
  }

  func mergingFallbacks(from fallback: Self) -> Self {
    var merged = fallback.valuesByKey
    for (key, values) in valuesByKey {
      merged[key] = values
    }
    return Self(valuesByKey: merged)
  }

  private init(valuesByKey: [String: [String]]) {
    self.valuesByKey = valuesByKey
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
