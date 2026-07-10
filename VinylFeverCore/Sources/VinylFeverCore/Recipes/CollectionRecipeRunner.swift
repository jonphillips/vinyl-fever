import Dependencies
import DependenciesMacros
import Foundation
import LLMClientKit

/// The proposal a recipe emits for one file. A `nil` return from the runner means
/// the recipe does not touch this file (no pattern match, an idempotent no-op, or
/// an unsupported target field). When there *is* a proposal, a non-empty `issues`
/// set forces the item into human review and is never auto-applied — mirroring the
/// setlist validator's "refuse to call it clean" rule.
public struct RecipeProposal: Equatable, Sendable {
  public var delta: ProposedTags
  public var reason: String
  public var issues: [RecipeIssue]

  public init(delta: ProposedTags, reason: String, issues: [RecipeIssue] = []) {
    self.delta = delta
    self.reason = reason
    self.issues = issues
  }
}

public enum RecipeIssue: Equatable, Sendable {
  /// The value to be written does not actually appear in the filename — the
  /// anti-hallucination tripwire. Vacuous in S0 (the value *is* the capture) and
  /// load-bearing in S2, when the model chooses the value.
  case valueNotInFilename
  /// The model returned something the decoder could not parse. Produced only on the
  /// `useModel` path (S2); listed now so the API is stable.
  case modelOutputUnparseable
}

/// Bookend seam so recipe execution is a config choice, not a call-site choice —
/// the same shape as `SetlistNormalizer`. The `liveValue` runs the deterministic
/// engine for model-off recipes and, behind `useModel`, the model classify stage
/// (S2) that reads `\.modelClient`.
@DependencyClient
public struct CollectionRecipeRunner: Sendable {
  public var run: @Sendable (
    _ recipe: CollectionRecipe,
    _ filename: String,
    _ current: AudioTags
  ) async throws -> RecipeProposal?
}

extension CollectionRecipeRunner: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension CollectionRecipeRunner {
  public static var liveValue: Self {
    @Dependency(\.modelClient) var modelClient
    let runner = LiveCollectionRecipeRunner(modelClient: modelClient)
    return Self { recipe, filename, current in
      try await runner.run(recipe: recipe, filename: filename, current: current)
    }
  }
}

extension DependencyValues {
  public var collectionRecipeRunner: CollectionRecipeRunner {
    get { self[CollectionRecipeRunner.self] }
    set { self[CollectionRecipeRunner.self] = newValue }
  }
}

/// The deterministic (model-off) pipeline, held as a plain struct so tests exercise
/// it directly — the way `LiveSetlistNormalizer` is tested without dependency
/// gymnastics. Four bookends: extract → validate → emit, with the classify stage a
/// verbatim pass-through until S2 wires the model in.
public struct CollectionRecipeEngine: Sendable {
  public init() {}

  public func run(
    recipe: CollectionRecipe,
    filename: String,
    current: AudioTags
  ) throws -> RecipeProposal? {
    guard recipe.enabled, recipe.targetField.isStringValued else { return nil }
    let currentValue = current.stringValue(for: recipe.targetField)

    switch recipe.op {
    case .strip:
      return try stripProposal(recipe: recipe, currentValue: currentValue)
    case .appendIfAbsent, .setIfEmpty, .replace:
      return try captureProposal(recipe: recipe, filename: filename, currentValue: currentValue)
    }
  }

  // MARK: - Capture ops (evidence: the filename)

  private func captureProposal(
    recipe: CollectionRecipe,
    filename: String,
    currentValue: String?
  ) throws -> RecipeProposal? {
    // 1. Extract.
    guard let value = try Self.capture(recipe.captureName, from: filename, pattern: recipe.pattern)
    else { return nil }
    // 2. Classify — model-off: the value is the capture, verbatim. (The `useModel`
    //    path in `LiveCollectionRecipeRunner` swaps this for the model's chosen value.)
    // 3 + 4. Validate + emit, via the stage shared with the model path.
    return Self.captureProposal(
      recipe: recipe,
      value: value,
      reason: nil,
      filename: filename,
      currentValue: currentValue,
      extraIssues: []
    )
  }

  /// Stages 3 (validate) and 4 (emit) of a capture op, shared by the deterministic
  /// path and the S2 model path so the verbatim guard and idempotency live in one
  /// place. `extraIssues` carries model-path guardrails (e.g. `.modelOutputUnparseable`);
  /// `reason` overrides the deterministic reason when the model supplies one. A `nil`
  /// return means the op is a no-op (value already present / field populated / unchanged).
  static func captureProposal(
    recipe: CollectionRecipe,
    value: String,
    reason: String?,
    filename: String,
    currentValue: String?,
    extraIssues: [RecipeIssue]
  ) -> RecipeProposal? {
    // 3. Validate — the verbatim guard. Tautological on the model-off path (the value
    //    *is* the capture); the load-bearing safety net when the model chose the value.
    var issues = extraIssues
    if !TextEvidence.appears(value, in: filename) {
      issues.append(.valueNotInFilename)
    }
    // 4. Emit — apply the op. A `nil` new value means "nothing to do" (idempotent).
    guard let newValue = applied(recipe.op, value: value, to: currentValue, affix: recipe.affixTemplate)
    else { return nil }
    let override = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    return RecipeProposal(
      delta: .delta(newValue, for: recipe.targetField),
      reason: (override?.isEmpty == false)
        ? override!
        : Self.reason(recipe.op, value: value, field: recipe.targetField),
      issues: issues
    )
  }

  // MARK: - Strip (evidence: the target field itself)

  private func stripProposal(
    recipe: CollectionRecipe,
    currentValue: String?
  ) throws -> RecipeProposal? {
    guard let base = currentValue, !base.isEmpty else { return nil }
    let regex = try Regex(recipe.pattern)
    let stripped = base.replacing(regex, with: "")
    let normalized = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    // No change ⇒ no-op (also the idempotent second-run case).
    guard normalized != base else { return nil }
    return RecipeProposal(
      delta: .delta(normalized, for: recipe.targetField),
      reason: "Stripped pattern from \(recipe.targetField.rawValue)."
    )
  }

  // MARK: - Helpers

  /// Run `pattern` over `filename` and return the named capture, or `nil` if the
  /// pattern doesn't match / the capture is absent. Throws only on an invalid regex.
  static func capture(_ name: String, from filename: String, pattern: String) throws -> String? {
    let regex = try Regex(pattern)
    guard
      let match = try regex.firstMatch(in: filename),
      let captured = match[name]?.substring
    else { return nil }
    let value = String(captured).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  /// Apply the transform. Returns the new field value, or `nil` when the op is a
  /// no-op (value already present, field already populated, or unchanged).
  static func applied(
    _ op: CollectionRecipe.Op,
    value: String,
    to currentValue: String?,
    affix: String
  ) -> String? {
    switch op {
    case .appendIfAbsent:
      let base = currentValue ?? ""
      guard !TextEvidence.appears(value, in: base) else { return nil }
      let suffix = affix.replacingOccurrences(of: "{value}", with: value)
      return base + suffix
    case .setIfEmpty:
      let isEmpty = (currentValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      return isEmpty ? value : nil
    case .replace:
      return currentValue == value ? nil : value
    case .strip:
      return nil // handled by stripProposal; never reached
    }
  }

  static func reason(_ op: CollectionRecipe.Op, value: String, field: ProposedTags.Field) -> String {
    switch op {
    case .appendIfAbsent:
      "Appended “\(value)” to \(field.rawValue)."
    case .setIfEmpty:
      "Set \(field.rawValue) to “\(value)”."
    case .replace:
      "Replaced \(field.rawValue) with “\(value)”."
    case .strip:
      "Stripped pattern from \(field.rawValue)."
    }
  }
}

/// The `useModel` classify stage (S2). Holds its `ModelClient` as a stored property —
/// mirroring `LiveSetlistNormalizer` — so tests construct it directly with a
/// `StubModelClient` and no dependency-context gymnastics. Everything the model does
/// *not* touch (model-off recipes, `strip`, disabled/non-string recipes) delegates to
/// the deterministic `CollectionRecipeEngine`, which stays the sole owner of the ops.
struct LiveCollectionRecipeRunner: Sendable {
  var modelClient: any ModelClient
  private let engine = CollectionRecipeEngine()

  func run(
    recipe: CollectionRecipe,
    filename: String,
    current: AudioTags
  ) async throws -> RecipeProposal? {
    // The classify stage is defined only for enabled, string-valued **capture** ops
    // (evidence = the filename). Model-off, `strip`, disabled and non-string recipes
    // are the deterministic engine, unchanged from S0.
    guard recipe.useModel, recipe.enabled, recipe.targetField.isStringValued, recipe.op != .strip
    else {
      return try engine.run(recipe: recipe, filename: filename, current: current)
    }
    return try await classify(recipe: recipe, filename: filename, current: current)
  }

  /// The four bookends with the model at stage 2: extract (deterministic gate) →
  /// **model decides apply/value/reason** → validate (verbatim guard) → emit (apply
  /// the op). A malformed response degrades to review, never to disk.
  private func classify(
    recipe: CollectionRecipe,
    filename: String,
    current: AudioTags
  ) async throws -> RecipeProposal? {
    // 1. Extract — the pattern still gates candidacy, so the model is only asked about
    //    files the rule already matched (no call spent on a non-candidate).
    guard let candidate = try CollectionRecipeEngine.capture(
      recipe.captureName, from: filename, pattern: recipe.pattern
    ) else { return nil }

    let currentValue = current.stringValue(for: recipe.targetField)

    // 2. Classify — an on-device call: this is a cheap, private, per-file judgment, and
    //    there is no on-device→frontier upgrade path, so `.onDevice` *is* the ledger's
    //    "onDevicePreferred". The system prompt forbids invention; stage 3 enforces it.
    let request = ModelRequest(
      tier: .onDevice,
      system: Self.systemPrompt,
      prompt: Self.userPrompt(recipe: recipe, filename: filename, candidate: candidate),
      maxTokens: 256
    )
    let response = try await modelClient.complete(request)

    guard let decision = Self.decode(response.text) else {
      // Degrade-to-review floor: a response we can't parse surfaces the deterministic
      // candidate as the proposed edit, **flagged** so it is preview-gated and never
      // auto-applied — the setlist normalizer's "refuse to call it clean" rule.
      return CollectionRecipeEngine.captureProposal(
        recipe: recipe,
        value: candidate,
        reason: nil,
        filename: filename,
        currentValue: currentValue,
        extraIssues: [.modelOutputUnparseable]
      )
    }

    // The model rejected this file (e.g. `[Live]`/`[Remaster]` for a covers recipe).
    guard decision.apply else { return nil }

    // A `value`-less "apply: true" falls back to the captured candidate — guaranteed to
    // be in the filename, so it passes the guard rather than being flagged as invented.
    let chosen = decision.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = (chosen?.isEmpty == false) ? chosen! : candidate

    // 3 + 4. Validate (the verbatim guard is the net for a hallucinated value) + emit.
    return CollectionRecipeEngine.captureProposal(
      recipe: recipe,
      value: value,
      reason: decision.reason,
      filename: filename,
      currentValue: currentValue,
      extraIssues: []
    )
  }
}

extension LiveCollectionRecipeRunner {
  /// The model's structured verdict for one file. Only `apply` is required; `value` and
  /// `reason` are optional so a terse `{"apply": false}` still decodes.
  struct Classification: Decodable, Equatable {
    var apply: Bool
    var value: String?
    var reason: String?
  }

  /// Recover the verdict from the model's text, tolerating prose or a ```json fence the
  /// way `SetlistNormalizer.decodeDraft` does. `nil` ⇒ unparseable ⇒ degrade to review.
  static func decode(_ text: String) -> Classification? {
    guard
      let open = text.firstIndex(of: "{"),
      let close = text.lastIndex(of: "}"),
      open < close,
      let data = String(text[open...close]).data(using: .utf8),
      let decoded = try? JSONDecoder().decode(Classification.self, from: data)
    else { return nil }
    return decoded
  }

  // MARK: - Prompts

  static let systemPrompt: String = """
    You are the classify stage of a metadata recipe. A deterministic rule has already \
    matched one file and pulled a candidate substring from its filename. Decide whether \
    the recipe should edit this file, and with what value.

    You are an extractor, never an inventor. The `value` you return MUST be copied \
    verbatim from the filename — never translate, reformat, correct, or invent it. If the \
    candidate does not fit the recipe's stated intent, return apply=false and leave value \
    empty. When in doubt, do not apply.

    Return ONLY a JSON object, no prose, in exactly this shape:
    {"apply": true, "value": "substring copied from the filename", "reason": "one short clause"}
    """

  static func userPrompt(recipe: CollectionRecipe, filename: String, candidate: String) -> String {
    """
    RECIPE INTENT:
    \(recipe.prompt)

    FILENAME:
    \(filename)

    CANDIDATE (matched by the recipe's pattern):
    \(candidate)

    Decide whether to apply the recipe to this file.
    """
  }
}
