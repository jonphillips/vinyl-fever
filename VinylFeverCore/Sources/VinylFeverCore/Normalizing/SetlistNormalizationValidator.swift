import Foundation

/// A guardrail the validator raised. A non-empty set marks the draft **low-confidence
/// and forces human review** (setlist-formatting-rules.md, *Validate*) — the validator
/// never auto-fixes, it only refuses to call something clean.
public enum ValidationIssue: Equatable, Sendable {
  /// A required identity tag (`ARTIST`, `DATE`) is absent.
  case missingTag(String)
  /// A date was provided but isn't a real ISO `YYYY-MM-DD` (typo/impossible date —
  /// flagged to review, never auto-corrected, per the deferred-decisions note).
  case badDate(String)
  /// The `source` token isn't in the controlled vocabulary (`SourceLabel`).
  case sourceNotInVocabulary(String)
  /// A concrete source was claimed but its `sourceEvidence` doesn't appear in the
  /// input — the "no invented source" tripwire.
  case sourceEvidenceNotInInput
  /// The model returned no tracks — never a valid setlist.
  case emptyTrackList
  /// The drafted track count is implausibly short versus the numbered lines the raw
  /// input actually contains (likely a truncated extraction).
  case trackCountImplausible(drafted: Int, detected: Int)
}

extension ValidationIssue {
  /// A human-readable reason for the preview's "needs review" panel.
  public var displayMessage: String {
    switch self {
    case let .missingTag(tag):
      "Missing \(tag)."
    case let .badDate(date):
      "“\(date)” isn’t a valid date — left for review, not auto-corrected."
    case let .sourceNotInVocabulary(source):
      "Source “\(source)” isn’t in the controlled vocabulary."
    case .sourceEvidenceNotInInput:
      "The claimed source has no supporting evidence in the notes."
    case .emptyTrackList:
      "No tracks were extracted."
    case let .trackCountImplausible(drafted, detected):
      "Only \(drafted) tracks extracted but the notes list ~\(detected) numbered lines."
    }
  }
}

/// Bookend 3 of the sandwich: deterministic checks over the model's structured
/// output. Pure and model-free.
public struct SetlistNormalizationValidator: Sendable {
  public init() {}

  public func validate(_ draft: NormalizedDraft, rawInput: String) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    if draft.tags.artist.trimmed.isEmpty {
      issues.append(.missingTag("ARTIST"))
    }

    let dateText = draft.tags.date.trimmed
    if dateText.isEmpty || Self.isUnknownWord(dateText) {
      issues.append(.missingTag("DATE"))
    } else if case .unknown = DateField(isoString: dateText) {
      issues.append(.badDate(dateText))
    }

    issues += validateSource(draft.tags.source, evidence: draft.sourceEvidence, rawInput: rawInput)

    if draft.tracks.isEmpty {
      issues.append(.emptyTrackList)
    } else {
      let detected = Self.numberedLineCount(in: rawInput)
      if detected >= 3, draft.tracks.count * 2 < detected {
        issues.append(.trackCountImplausible(drafted: draft.tracks.count, detected: detected))
      }
    }

    return issues
  }

  private func validateSource(
    _ source: String, evidence: String, rawInput: String
  ) -> [ValidationIssue] {
    let token = SourceLabel.normalizedToken(source)
    // An absent or explicitly-unknown source is allowed — it renders as `(unknown)`
    // and needs no evidence.
    if token.isEmpty || Self.isUnknownWord(token) {
      return []
    }
    var issues: [ValidationIssue] = []
    if !Self.vocabularyKeys.contains(token.lowercased()) {
      issues.append(.sourceNotInVocabulary(source))
    }
    if !Self.evidenceAppears(evidence, in: rawInput) {
      issues.append(.sourceEvidenceNotInInput)
    }
    return issues
  }

  // MARK: - Helpers

  /// The controlled vocabulary, normalized to lowercase keys — the same tokens the
  /// registry ships as built-ins, so there is one source of truth for "valid source."
  static let vocabularyKeys: Set<String> = Set(
    SourceLabel.builtInTokens.map { SourceLabel.normalizedToken($0).lowercased() }
  )

  static func isUnknownWord(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower == "unknown" || lower == "unknown date" || lower == "n/a"
  }

  /// Evidence check with the same whitespace floor the input gets — the quoted line
  /// must actually be present, case- and spacing-insensitive, so a real inference
  /// passes while an invented one fails.
  static func evidenceAppears(_ evidence: String, in rawInput: String) -> Bool {
    let needle = collapseWhitespace(evidence)
    guard !needle.isEmpty else { return false }
    return collapseWhitespace(rawInput).contains(needle)
  }

  private static func collapseWhitespace(_ text: String) -> String {
    text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func numberedLineCount(in rawInput: String) -> Int {
    SetlistPreSegmenter.normalizedLines(rawInput)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { SetlistPreSegmenter.looksLikeNumberedTrack($0) }
      .count
  }
}

private extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
