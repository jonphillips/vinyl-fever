import Foundation

public enum ListeningLogCodecError: Error, Equatable, Sendable {
  case newerVersion(Int)
  case unexpectedFormat(String)
  case malformedLine(Int)
}

public enum ListeningLogCodec {
  public static func encode(_ fetch: ListeningFetch) throws -> Data {
    var data = try encoder().encode(fetch)
    data.append(0x0A)
    return data
  }

  public static func encode(_ lease: ListeningLease) throws -> Data {
    try encoder().encode(lease)
  }

  public static func decodeFetch(_ data: Data) throws -> ListeningFetch {
    try decodeFetch(data, using: decoder())
  }

  public static func decodeLease(_ data: Data) throws -> ListeningLease {
    try checkHeader(data, format: ListeningLease.formatName)
    return try decoder().decode(ListeningLease.self, from: data)
  }

  /// Reads complete newline-terminated records. A non-terminated final fragment is an iCloud
  /// mid-append and is ignored; malformed complete lines remain an error.
  public static func decodeJSONL(_ data: Data) throws -> [ListeningFetch] {
    guard !data.isEmpty else { return [] }
    let bytes = [UInt8](data)
    let terminated = bytes.last == 0x0A
    let completeBytes = terminated ? bytes.count : (bytes.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0)
    guard completeBytes > 0 else { return [] }

    let text = String(decoding: bytes[..<completeBytes], as: UTF8.self)
    var records: [ListeningFetch] = []
    let jsonDecoder = decoder()
    for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
      do {
        records.append(try decodeFetch(Data(line.utf8), using: jsonDecoder))
      } catch let error as ListeningLogCodecError {
        throw error
      } catch {
        throw ListeningLogCodecError.malformedLine(offset + 1)
      }
    }
    return records
  }

  private static func decodeFetch(_ data: Data, using decoder: JSONDecoder) throws -> ListeningFetch {
    let fetch: ListeningFetch
    do {
      fetch = try decoder.decode(ListeningFetch.self, from: data)
    } catch {
      // Preserve typed format/version diagnostics even when a future record has fields this
      // reader cannot decode yet. The common valid-record path only decodes once.
      try checkHeader(data, format: ListeningFetch.formatName)
      throw error
    }
    guard fetch.format == ListeningFetch.formatName else {
      throw ListeningLogCodecError.unexpectedFormat(fetch.format)
    }
    guard fetch.version <= ListeningFetch.currentVersion else {
      throw ListeningLogCodecError.newerVersion(fetch.version)
    }
    return fetch
  }

  private static func checkHeader(_ data: Data, format: String) throws {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let fields = object as? [String: Any] else {
      throw ListeningLogCodecError.unexpectedFormat("<non-object>")
    }
    let actualFormat = fields["format"] as? String ?? "<missing>"
    guard actualFormat == format else {
      throw ListeningLogCodecError.unexpectedFormat(actualFormat)
    }
    let version = fields["version"] as? Int ?? 0
    let currentVersion = format == ListeningFetch.formatName
      ? ListeningFetch.currentVersion : ListeningLease.currentVersion
    guard version <= currentVersion else {
      throw ListeningLogCodecError.newerVersion(version)
    }
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(TimestampFormatters.fractional.formatter.string(from: date))
    }
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let string = try container.decode(String.self)
      guard let date = TimestampFormatters.fractional.formatter.date(from: string)
        ?? TimestampFormatters.wholeSecond.formatter.date(from: string)
      else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 timestamp")
      }
      return date
    }
    return decoder
  }

  private enum TimestampFormatters {
    static let fractional = ISO8601FormatterHolder(options: [.withInternetDateTime, .withFractionalSeconds])
    static let wholeSecond = ISO8601FormatterHolder(options: [.withInternetDateTime])
  }
}

private final class ISO8601FormatterHolder: @unchecked Sendable {
  let formatter: ISO8601DateFormatter

  init(options: ISO8601DateFormatter.Options) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = options
    self.formatter = formatter
  }
}
