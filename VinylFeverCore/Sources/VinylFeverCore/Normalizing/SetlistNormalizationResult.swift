import Foundation

/// The Normalizer's end-to-end output: the rendered-ready `SetlistDraft`, the raw
/// model contract it came from (for the preview's confidence/notes), the guardrail
/// issues, and the full drop audit. A result is **never auto-written** — the preview
/// gate consumes `isHighConfidence` only to sort attention, not to skip review.
public struct SetlistNormalizationResult: Equatable, Sendable {
  public var draft: SetlistDraft
  public var normalized: NormalizedDraft
  public var issues: [ValidationIssue]
  /// Mechanical checksum lines the pre-segmenter excised, folded into the audit.
  public var removedHashLines: [String]

  public init(
    draft: SetlistDraft,
    normalized: NormalizedDraft,
    issues: [ValidationIssue],
    removedHashLines: [String]
  ) {
    self.draft = draft
    self.normalized = normalized
    self.issues = issues
    self.removedHashLines = removedHashLines
  }

  /// Clean only when the model was confident *and* every guardrail passed.
  public var isHighConfidence: Bool { issues.isEmpty && normalized.confidence == .high }

  /// Everything discarded on the way to the draft — the model's own drops plus the
  /// excised hash lines — for the preview's "here's what was dropped" panel.
  public var allDropped: [String] { normalized.dropped + removedHashLines }

  /// The proposed `setlist.txt`, rendered from the draft.
  public var renderedText: String { SetlistText.render(draft) }
}

extension SetlistNormalizationResult {
  /// Map the model contract onto the domain `SetlistDraft` and validate it. Pure
  /// given an id source, so the mapping + validation are testable without a model
  /// call (the `SetlistNormalizer` client supplies `@Dependency(\.uuid)`).
  static func make(
    normalized: NormalizedDraft,
    rawInput: String,
    removedHashLines: [String],
    nextID: () -> UUID
  ) -> Self {
    let tags = ShowTags(
      artist: Field(normalized.tags.artist),
      albumArtist: Field(normalized.tags.albumArtist),
      date: DateField(isoString: normalized.tags.date),
      venue: Field(normalized.tags.venue),
      location: Field(normalized.tags.location),
      source: Field(normalized.tags.source)
    )
    let tracks = normalized.tracks
      .map { track in
        SetlistTrack(
          id: nextID(),
          title: track.title.trimmingCharacters(in: .whitespacesAndNewlines),
          note: track.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )
      }
      .filter { !$0.title.isEmpty }

    let issues = SetlistNormalizationValidator().validate(normalized, rawInput: rawInput)

    return SetlistNormalizationResult(
      draft: SetlistDraft(tags: tags, tracks: tracks),
      normalized: normalized,
      issues: issues,
      removedHashLines: removedHashLines
    )
  }
}

private extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}
