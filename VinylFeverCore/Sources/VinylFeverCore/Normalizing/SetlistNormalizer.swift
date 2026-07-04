import Dependencies
import DependenciesMacros
import Foundation
import LLMClientKit

/// Bookend 2 wired into the full sandwich: pre-segment → **frontier LLM** → validate.
/// The client seam so feature logic is testable with a stub model and the backend is
/// a config choice, not a call-site choice. Prompt-and-parse (the house style): the
/// model returns the `NormalizedDraft` JSON, which is defensively decoded and mapped
/// onto the domain `SetlistDraft` before the deterministic validator runs.
@DependencyClient
public struct SetlistNormalizer: Sendable {
  public var normalize: @Sendable (_ rawInput: String) async throws -> SetlistNormalizationResult
}

extension SetlistNormalizer: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension SetlistNormalizer {
  public static var liveValue: Self {
    @Dependency(\.modelClient) var modelClient
    @Dependency(\.uuid) var uuid

    let engine = LiveSetlistNormalizer(modelClient: modelClient, nextID: { uuid() })
    return Self { rawInput in try await engine.normalize(rawInput) }
  }
}

extension DependencyValues {
  public var setlistNormalizer: SetlistNormalizer {
    get { self[SetlistNormalizer.self] }
    set { self[SetlistNormalizer.self] = newValue }
  }
}

/// The concrete pipeline, holding its collaborators as stored properties (mirroring
/// `LiveAudioMetadataReader`) so tests construct it directly with a `StubModelClient`
/// and a controlled id source — no dependency-context gymnastics.
struct LiveSetlistNormalizer: Sendable {
  var modelClient: any ModelClient
  var nextID: @Sendable () -> UUID

  func normalize(_ rawInput: String) async throws -> SetlistNormalizationResult {
    let pre = SetlistPreSegmenter().segment(rawInput)
    let request = ModelRequest(
      tier: .frontier(.anthropic),
      system: SetlistNormalizer.systemPrompt,
      prompt: SetlistNormalizer.userPrompt(for: pre),
      maxTokens: 4096
    )
    let response = try await modelClient.complete(request)
    let normalized = SetlistNormalizer.decodeDraft(from: response.text)
    return SetlistNormalizationResult.make(
      normalized: normalized,
      rawInput: rawInput,
      removedHashLines: pre.removedHashLines,
      nextID: nextID
    )
  }
}

extension SetlistNormalizer {
  /// Recover the `NormalizedDraft` from the model's text. Frontier models often wrap
  /// JSON in prose or a ```json fence, so we slice the outer `{…}` and decode that.
  /// Anything that doesn't decode degrades to a low-confidence, track-less draft — the
  /// validator then forces review rather than the pipeline crashing.
  static func decodeDraft(from text: String) -> NormalizedDraft {
    guard
      let open = text.firstIndex(of: "{"),
      let close = text.lastIndex(of: "}"),
      open < close
    else {
      return degraded
    }
    let json = String(text[open...close])
    guard
      let data = json.data(using: .utf8),
      let draft = try? JSONDecoder().decode(NormalizedDraft.self, from: data)
    else {
      return degraded
    }
    return draft
  }

  /// The floor a malformed response lands on: no tracks, low confidence — guaranteed
  /// to fail validation and route to human review.
  static let degraded = NormalizedDraft(
    tags: NormalizedTags(),
    tracks: [],
    sourceEvidence: "",
    confidence: .low,
    dropped: []
  )

  // MARK: - Prompts

  static let systemPrompt: String = """
    You normalize a raw concert "trading note" into a structured setlist. You are an \
    extractor, never an inventor: every value must be grounded in the input. When in \
    doubt, drop to low confidence rather than guess.

    SOURCE OF TRUTH — THE MEDIA, NOT THE SHOW. A setlist reflects what is physically on \
    the recording. Use the structured numbered/disc track list. Ignore prose \
    "complete set" re-lists and songs marked "not recorded." If a release physically \
    holds two sub-sets (e.g. an early and a late show, or a main set plus a radio \
    session), keep both.

    TAGS. Extract artist (the credited live act), albumArtist (the primary catalog \
    artist — often the same), date as ISO YYYY-MM-DD, venue, and location as \
    "City, ST/Country". Leave a field empty when the input doesn't support it; do not \
    invent it.

    SOURCE. Choose exactly one token from this controlled vocabulary, inferring from \
    lineage/taper prose: \(controlledVocabularyList). Use "unknown" if the notes don't \
    say. Put the exact input substring you inferred it from in `sourceEvidence` — it \
    must appear verbatim in the input.

    TRACKS. Ordered as recorded. Keep numbered non-song items (intro, banter, tuning). \
    Attach a short `note` only for musical detail worth keeping (e.g. ">" segue, guest). \
    Fix an obvious song-title misspelling when the intended song is clear. Put every \
    discarded line in `dropped` so the human preview can audit it.

    Return ONLY a JSON object, no prose, in exactly this shape:
    {
      "tags": {"artist": "", "albumArtist": "", "date": "YYYY-MM-DD", "venue": "", "location": "", "source": "SBD"},
      "tracks": [{"title": "", "note": null, "confidence": "high"}],
      "sourceEvidence": "quoted lineage substring from the input",
      "confidence": "high",
      "dropped": ["discarded lines"]
    }
    """

  /// The controlled vocabulary rendered for the prompt — the single source of truth is
  /// the registry's built-in tokens, so the prompt and the validator can never drift.
  static var controlledVocabularyList: String {
    (SourceLabel.builtInTokens + ["unknown"]).joined(separator: ", ")
  }

  static func userPrompt(for pre: PreSegmentedNotes) -> String {
    var sections = ["RAW NOTES (cleaned):", pre.cleanedText]
    if !pre.regions.isEmpty {
      let hints = pre.regions
        .map { "[\($0.kind.rawValue)]\n\($0.text)" }
        .joined(separator: "\n\n")
      sections += ["", "REGION HINTS (advisory — you may disagree):", hints]
    }
    return sections.joined(separator: "\n")
  }
}
