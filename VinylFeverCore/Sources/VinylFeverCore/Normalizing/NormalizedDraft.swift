import Foundation

/// The structured JSON the Normalizer's LLM leg emits (setlist-formatting-rules.md,
/// *LLM output contract*). The model does the semantic judgment and returns this
/// shape so the deterministic validator can inspect fields before any `setlist.txt`
/// is rendered — the model never emits finished text.
///
/// Decoding is deliberately **lenient** (see `init(from:)`): a frontier model that
/// omits an optional array or misspells a confidence value degrades to a
/// low-confidence draft rather than crashing the pipeline, honoring the spec's
/// "malformed output degrades to a low-confidence draft, never a crash."
public struct NormalizedDraft: Codable, Equatable, Sendable {
  public var tags: NormalizedTags
  public var tracks: [NormalizedTrack]
  /// The quoted input line the `source` label was inferred from. The validator
  /// confirms this string actually appears in the raw input — the mechanism that
  /// makes "no invented source" checkable.
  public var sourceEvidence: String
  public var confidence: DraftConfidence
  /// Lines the model discarded, surfaced in the preview so the drop is auditable.
  public var dropped: [String]

  public init(
    tags: NormalizedTags,
    tracks: [NormalizedTrack],
    sourceEvidence: String,
    confidence: DraftConfidence,
    dropped: [String]
  ) {
    self.tags = tags
    self.tracks = tracks
    self.sourceEvidence = sourceEvidence
    self.confidence = confidence
    self.dropped = dropped
  }

  private enum CodingKeys: String, CodingKey {
    case tags, tracks, sourceEvidence, confidence, dropped
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // `tags` is the only structurally-required field; everything else defaults so a
    // partial model response still yields a (low-confidence) draft.
    tags = try container.decodeIfPresent(NormalizedTags.self, forKey: .tags) ?? NormalizedTags()
    tracks = try container.decodeIfPresent([NormalizedTrack].self, forKey: .tracks) ?? []
    sourceEvidence = try container.decodeIfPresent(String.self, forKey: .sourceEvidence) ?? ""
    confidence = try container.decodeIfPresent(DraftConfidence.self, forKey: .confidence) ?? .low
    dropped = try container.decodeIfPresent([String].self, forKey: .dropped) ?? []
  }
}

public struct NormalizedTags: Codable, Equatable, Sendable {
  public var artist: String
  public var albumArtist: String
  /// ISO `YYYY-MM-DD`, or empty/`"Unknown Date"` when the model couldn't resolve it.
  public var date: String
  public var venue: String
  public var location: String
  /// A controlled-vocabulary source token (`SBD`, `AUD`, …) — validated against
  /// `SourceLabel.builtInTokens`, never rendered raw without that check.
  public var source: String

  public init(
    artist: String = "",
    albumArtist: String = "",
    date: String = "",
    venue: String = "",
    location: String = "",
    source: String = ""
  ) {
    self.artist = artist
    self.albumArtist = albumArtist
    self.date = date
    self.venue = venue
    self.location = location
    self.source = source
  }

  private enum CodingKeys: String, CodingKey {
    case artist, albumArtist, date, venue, location, source
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
    albumArtist = try container.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
    date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
    venue = try container.decodeIfPresent(String.self, forKey: .venue) ?? ""
    location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
    source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
  }
}

public struct NormalizedTrack: Codable, Equatable, Sendable {
  public var title: String
  public var note: String?
  public var confidence: DraftConfidence

  public init(title: String, note: String? = nil, confidence: DraftConfidence = .high) {
    self.title = title
    self.note = note
    self.confidence = confidence
  }

  private enum CodingKeys: String, CodingKey {
    case title, note, confidence
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    note = try container.decodeIfPresent(String.self, forKey: .note)
    confidence = try container.decodeIfPresent(DraftConfidence.self, forKey: .confidence) ?? .high
  }
}

/// The model's self-reported confidence. Unknown/misspelled values decode to `.low`
/// (see `init(from:)`) so an ambiguous signal always routes to human review, never
/// silently reads as high.
public enum DraftConfidence: String, Codable, Equatable, Sendable {
  case high
  case low

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = DraftConfidence(rawValue: raw.lowercased()) ?? .low
  }
}
