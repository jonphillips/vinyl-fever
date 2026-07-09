import Dependencies
import DependenciesMacros
import Foundation

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
/// the same shape as `SetlistNormalizer`. The S0 `liveValue` runs the model-off
/// engine and takes no dependencies; S2 adds the classify stage behind `useModel`.
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
    let engine = CollectionRecipeEngine()
    return Self { recipe, filename, current in
      try engine.run(recipe: recipe, filename: filename, current: current)
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

    // 2. Classify — model-off: the value is the capture, verbatim. (S2 replaces
    //    this line with the model's chosen value.)

    // 3. Validate — the verbatim guard. Tautological here; the safety net for S2.
    let issues: [RecipeIssue] =
      TextEvidence.appears(value, in: filename) ? [] : [.valueNotInFilename]

    // 4. Emit — apply the op. A `nil` new value means "nothing to do" (idempotent).
    guard let newValue = Self.applied(recipe.op, value: value, to: currentValue, affix: recipe.affixTemplate)
    else { return nil }

    return RecipeProposal(
      delta: .delta(newValue, for: recipe.targetField),
      reason: Self.reason(recipe.op, value: value, field: recipe.targetField),
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
