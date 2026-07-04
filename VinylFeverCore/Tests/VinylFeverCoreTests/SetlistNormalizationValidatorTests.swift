import CustomDump
import Testing
@testable import VinylFeverCore

@Suite
struct SetlistNormalizationValidatorTests {
  let validator = SetlistNormalizationValidator()

  static let cleanRawInput = """
    Bruce Hornsby and The Range - 1996-05-21
    Source: SBD -> DAT -> CDR
    1. The Way It Is
    2. Mandolin Rain
    """

  func draft(
    artist: String = "Bruce Hornsby and The Range",
    date: String = "1996-05-21",
    source: String = "SBD",
    sourceEvidence: String = "Source: SBD -> DAT -> CDR",
    tracks: [String] = ["The Way It Is", "Mandolin Rain"]
  ) -> NormalizedDraft {
    NormalizedDraft(
      tags: NormalizedTags(artist: artist, date: date, source: source),
      tracks: tracks.map { NormalizedTrack(title: $0) },
      sourceEvidence: sourceEvidence,
      confidence: .high,
      dropped: []
    )
  }

  @Test
  func cleanDraftHasNoIssues() {
    let issues = validator.validate(draft(), rawInput: Self.cleanRawInput)
    expectNoDifference(issues, [])
  }

  @Test
  func flagsMissingArtistAndDate() {
    let issues = validator.validate(
      draft(artist: "  ", date: "Unknown Date"),
      rawInput: Self.cleanRawInput
    )
    #expect(issues.contains(.missingTag("ARTIST")))
    #expect(issues.contains(.missingTag("DATE")))
  }

  @Test
  func flagsImpossibleDateAsBadDateNotAutoCorrected() {
    let issues = validator.validate(draft(date: "1997-22-05"), rawInput: Self.cleanRawInput)
    #expect(issues.contains(.badDate("1997-22-05")))
  }

  @Test
  func flagsSourceOutsideControlledVocabulary() {
    let issues = validator.validate(
      draft(source: "MyGreatRip", sourceEvidence: "MyGreatRip"),
      rawInput: "MyGreatRip\n1. A\n2. B"
    )
    #expect(issues.contains(.sourceNotInVocabulary("MyGreatRip")))
  }

  @Test
  func flagsInventedSourceWhenEvidenceAbsentFromInput() {
    let issues = validator.validate(
      draft(sourceEvidence: "recorded on a soundboard by the band"),
      rawInput: Self.cleanRawInput
    )
    #expect(issues.contains(.sourceEvidenceNotInInput))
  }

  @Test
  func unknownSourceNeedsNoEvidence() {
    let issues = validator.validate(
      draft(source: "unknown", sourceEvidence: ""),
      rawInput: Self.cleanRawInput
    )
    expectNoDifference(issues, [])
  }

  @Test
  func flagsEmptyTrackList() {
    let issues = validator.validate(draft(tracks: []), rawInput: Self.cleanRawInput)
    #expect(issues.contains(.emptyTrackList))
  }

  @Test
  func flagsImplausiblyShortTrackList() {
    let rawInput = (1...10).map { "\($0). Track \($0)" }.joined(separator: "\n")
    let issues = validator.validate(
      draft(tracks: ["Track 1", "Track 2"]),
      rawInput: "Source: SBD\n" + rawInput
    )
    #expect(issues.contains(.trackCountImplausible(drafted: 2, detected: 10)))
  }
}
