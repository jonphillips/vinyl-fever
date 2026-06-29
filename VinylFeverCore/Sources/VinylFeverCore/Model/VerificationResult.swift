import Foundation

public struct VerificationResult: Equatable, Sendable {
  public var run: RunRecord
  public var expectedFileCount: Int
  public var actualFileCount: Int
  public var files: [VerificationFileResult]
  public var exitSummary: String

  public init(
    run: RunRecord,
    expectedFileCount: Int,
    actualFileCount: Int,
    files: [VerificationFileResult],
    exitSummary: String
  ) {
    self.run = run
    self.expectedFileCount = expectedFileCount
    self.actualFileCount = actualFileCount
    self.files = files
    self.exitSummary = exitSummary
  }

  public var didVerify: Bool {
    expectedFileCount == actualFileCount && files.allSatisfy(\.didVerify)
  }
}

public struct VerificationFileResult: Equatable, Identifiable, Sendable {
  public let id: ConversionTrackPlan.ID
  public var url: URL
  public var status: RunFileOutcome.Status
  public var note: String
  public var actualTags: AudioTags?
  public var mismatches: [VerificationMismatch]

  public init(
    id: ConversionTrackPlan.ID,
    url: URL,
    status: RunFileOutcome.Status,
    note: String,
    actualTags: AudioTags?,
    mismatches: [VerificationMismatch]
  ) {
    self.id = id
    self.url = url
    self.status = status
    self.note = note
    self.actualTags = actualTags
    self.mismatches = mismatches
  }

  public var didVerify: Bool {
    status == .read && mismatches.isEmpty
  }
}

public enum VerificationMismatch: Equatable, Sendable {
  case title(expected: String, actual: String?)
  case album(expected: String, actual: String?)
  case sortAlbum(expected: String, actual: String?)
  case artist(expected: String, actual: String?)
  case albumArtist(expected: String, actual: String?)
  case trackNumber(expected: Int, actual: Int?)
  case trackTotal(expected: Int, actual: Int?)
  case discNumber(expected: Int, actual: Int?)
  case missingAudioStream
  case durationNotPositive(Double?)

  public var message: String {
    switch self {
    case let .title(expected, actual):
      "Title expected \(expected), found \(Self.display(actual))."
    case let .album(expected, actual):
      "Album expected \(expected), found \(Self.display(actual))."
    case let .sortAlbum(expected, actual):
      "Sort album expected \(expected), found \(Self.display(actual))."
    case let .artist(expected, actual):
      "Artist expected \(expected), found \(Self.display(actual))."
    case let .albumArtist(expected, actual):
      "Album artist expected \(expected), found \(Self.display(actual))."
    case let .trackNumber(expected, actual):
      "Track expected \(expected), found \(Self.display(actual))."
    case let .trackTotal(expected, actual):
      "Track total expected \(expected), found \(Self.display(actual))."
    case let .discNumber(expected, actual):
      "Disc expected \(expected), found \(Self.display(actual))."
    case .missingAudioStream:
      "No audio stream found."
    case let .durationNotPositive(duration):
      "Duration must be greater than zero, found \(Self.display(duration))."
    }
  }

  private static func display(_ value: String?) -> String {
    value ?? "none"
  }

  private static func display(_ value: Int?) -> String {
    value.map(String.init) ?? "none"
  }

  private static func display(_ value: Double?) -> String {
    guard let value else {
      return "none"
    }
    return String(value)
  }
}

public enum AudioTagVerifier {
  public static func mismatches(
    expected tags: ProposedTags,
    trackTotal: Int,
    format: AudioFormat,
    actual: AudioTags
  ) -> [VerificationMismatch] {
    var mismatches: [VerificationMismatch] = []
    compareString(tags.title, actual.title, { .title(expected: $0, actual: $1) }, into: &mismatches)
    compareString(tags.album, actual.album, { .album(expected: $0, actual: $1) }, into: &mismatches)
    // The pinned M4A/ipod muxer does not round-trip sort_album through ffprobe
    // unless using mdta tags, which is not the pipeline recipe.
    if format != .m4a || actual.sortAlbum != nil {
      compareString(tags.sortAlbum, actual.sortAlbum, { .sortAlbum(expected: $0, actual: $1) }, into: &mismatches)
    }
    compareString(tags.artist, actual.artist, { .artist(expected: $0, actual: $1) }, into: &mismatches)
    compareString(tags.albumArtist, actual.albumArtist, { .albumArtist(expected: $0, actual: $1) }, into: &mismatches)
    compareInt(tags.trackNumber, actual.trackNumber, { .trackNumber(expected: $0, actual: $1) }, into: &mismatches)
    compareInt(trackTotal, actual.trackTotal, { .trackTotal(expected: $0, actual: $1) }, into: &mismatches)
    compareInt(tags.discNumber, actual.discNumber, { .discNumber(expected: $0, actual: $1) }, into: &mismatches)

    if !actual.hasAudioStream {
      mismatches.append(.missingAudioStream)
    }
    if (actual.durationSeconds ?? 0) <= 0 {
      mismatches.append(.durationNotPositive(actual.durationSeconds))
    }
    return mismatches
  }

  private static func compareString(
    _ expected: String,
    _ actual: String?,
    _ mismatch: (String, String?) -> VerificationMismatch,
    into mismatches: inout [VerificationMismatch]
  ) {
    let expected = normalizedMetadataString(expected)
    let actual = normalizedMetadataString(actual)
    if actual != expected {
      mismatches.append(mismatch(expected, actual))
    }
  }

  private static func compareInt(
    _ expected: Int,
    _ actual: Int?,
    _ mismatch: (Int, Int?) -> VerificationMismatch,
    into mismatches: inout [VerificationMismatch]
  ) {
    if actual != expected {
      mismatches.append(mismatch(expected, actual))
    }
  }

  public static func normalizedMetadataString(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func normalizedMetadataString(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
