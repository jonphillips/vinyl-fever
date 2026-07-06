import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
@testable import VinylFeverCore

@Suite
struct SetlistNormalizerTests {
  static let rawInput = """
    Bruce Hornsby and The Range
    1996-05-21 Pearl Street Grill, Northampton, MA
    Source: SBD -> DAT
    1. The Way It Is
    2. Mandolin Rain
    """

  /// A well-formed model response for `rawInput`.
  static let goodJSON = """
    {"tags":{"artist":"Bruce Hornsby and The Range","albumArtist":"Bruce Hornsby",\
    "date":"1996-05-21","venue":"Pearl Street Grill","location":"Northampton, MA",\
    "source":"SBD"},"tracks":[{"title":"The Way It Is","note":null,"confidence":"high"},\
    {"title":"Mandolin Rain","note":"> segue","confidence":"high"}],\
    "sourceEvidence":"Source: SBD -> DAT","confidence":"high","dropped":[]}
    """

  func normalizer(returning text: String) -> LiveSetlistNormalizer {
    let ids = UUIDGenerator.incrementing
    return LiveSetlistNormalizer(
      modelClient: StubModelClient.constant(text),
      nextID: { ids() }
    )
  }

  @Test
  func mapsCleanModelResponseToADraftAndCertifiesHighConfidence() async throws {
    let result = try await normalizer(returning: Self.goodJSON).normalize(Self.rawInput)

    expectNoDifference(result.draft.tags.artist, .value("Bruce Hornsby and The Range"))
    expectNoDifference(result.draft.tags.source, .value("SBD"))
    // The composed ALBUM line is folded back into the draft's `album` field (not left
    // blank), so the editable Album field is populated after normalizing.
    expectNoDifference(
      result.draft.tags.album,
      .value("1996-05-21: Northampton, MA - Pearl Street Grill (SBD)"))
    expectNoDifference(result.draft.tags.date, .iso(year: 1996, month: 5, day: 21))
    expectNoDifference(result.draft.tracks.map(\.title), ["The Way It Is", "Mandolin Rain"])
    expectNoDifference(result.draft.tracks.map(\.note), [nil, "> segue"])
    expectNoDifference(result.issues, [])
    #expect(result.isHighConfidence)
    #expect(
      result.renderedText.contains(
        "ALBUM: 1996-05-21: Northampton, MA - Pearl Street Grill (SBD)"))
  }

  @Test
  func recoversJSONWrappedInProseAndCodeFence() async throws {
    let wrapped = """
      Here is the normalized setlist:
      ```json
      \(Self.goodJSON)
      ```
      Let me know if you need changes!
      """
    let result = try await normalizer(returning: wrapped).normalize(Self.rawInput)

    expectNoDifference(result.draft.tracks.map(\.title), ["The Way It Is", "Mandolin Rain"])
    #expect(result.isHighConfidence)
  }

  @Test
  func malformedResponseDegradesToLowConfidenceReviewNotACrash() async throws {
    let result = try await normalizer(returning: "I'm sorry, I can't help with that.")
      .normalize(Self.rawInput)

    expectNoDifference(result.normalized.confidence, .low)
    #expect(result.issues.contains(.emptyTrackList))
    #expect(result.issues.contains(.missingTag("ARTIST")))
    #expect(!result.isHighConfidence)
  }

  @Test
  func inventedSourceIsCaughtEndToEnd() async throws {
    let invented = """
      {"tags":{"artist":"U2","albumArtist":"U2","date":"1987-11-01","venue":"McNichols Arena",\
      "location":"Denver, CO","source":"SBD"},"tracks":[{"title":"Where the Streets Have No Name",\
      "note":null,"confidence":"high"}],"sourceEvidence":"pristine soundboard master",\
      "confidence":"high","dropped":[]}
      """
    let raw = """
      U2 1987-11-01 McNichols Arena, Denver, CO
      1. Where the Streets Have No Name
      """
    let result = try await normalizer(returning: invented).normalize(raw)

    #expect(result.issues.contains(.sourceEvidenceNotInInput))
    #expect(!result.isHighConfidence)
  }
}
