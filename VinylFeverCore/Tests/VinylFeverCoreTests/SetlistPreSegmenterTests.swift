import CustomDump
import Testing
@testable import VinylFeverCore

@Suite
struct SetlistPreSegmenterTests {
  /// A representative raw trading note: bare identity header, a lineage block, a
  /// numbered disc/track list (including a `dNtNN` line), an FFP fingerprint block,
  /// and a trailing prose sentence.
  static let rawNote = """
    Bruce Hornsby and The Range
    Pearl Street Grill, Northampton, MA

    Source: SBD -> DAT -> CDR -> EAC -> FLAC
    Taped by John Smith

    Disc 1
    1. The Way It Is
    2. Mandolin Rain
    3. Every Little Kiss
    d1t04 The Valley Road

    hornsby96d1t01.flac:8f3a9c2b1e4d5a6f7890abcdef1234567890abcd
    hornsby96d1t02.flac:1234567890abcdef1234567890abcdef12345678

    This recording circulated widely among collectors.
    """

  @Test
  func excisesFingerprintHashLines() {
    let result = SetlistPreSegmenter().segment(Self.rawNote)

    #expect(result.removedHashLines.count == 2)
    #expect(!result.cleanedText.contains("8f3a9c2b"))
    #expect(!result.cleanedText.contains("1234567890abcdef"))
    // Non-hash content survives untouched.
    #expect(result.cleanedText.contains("The Way It Is"))
    #expect(result.cleanedText.contains("Source: SBD"))
  }

  @Test
  func labelsTracklistRegionIncludingStructuralAndDiscTrackLines() {
    let result = SetlistPreSegmenter().segment(Self.rawNote)

    let tracklist = result.regions.first { $0.kind == .tracklist }
    #expect(tracklist != nil)
    #expect(tracklist?.lines.contains("Disc 1") == true)
    #expect(tracklist?.lines.contains("1. The Way It Is") == true)
    #expect(tracklist?.lines.contains("d1t04 The Valley Road") == true)
  }

  @Test
  func labelsLineageRegion() {
    let result = SetlistPreSegmenter().segment(Self.rawNote)

    let lineage = result.regions.first { $0.kind == .lineage }
    #expect(lineage?.lines.contains("Source: SBD -> DAT -> CDR -> EAC -> FLAC") == true)
    #expect(lineage?.lines.contains("Taped by John Smith") == true)
  }

  @Test
  func normalizesCarriageReturnsAndStripsBOM() {
    let result = SetlistPreSegmenter().segment("\u{feff}ARTIST: U2\r\n1. Vertigo\r\n")

    #expect(!result.cleanedText.contains("\r"))
    #expect(!result.cleanedText.contains("\u{feff}"))
    #expect(result.cleanedText == "ARTIST: U2\n1. Vertigo")
  }

  @Test(arguments: [
    ("1. Song", true),
    ("12. Song", true),
    ("003 Song", true),
    ("d1t04 Song", true),
    ("d2t11. Song", true),
    ("1: Jim Ellis radio introduction", true),
    ("15: hot blooded", true),
    // Zero-padded numbers set off by tabs (column-aligned corpus notes).
    ("01\t\t\tIntro / Slow Turning", true),
    ("02\tReal Fine Love", true),
    ("Song Title", false),
    ("1997-05-21", false),
    ("3 blind mice at the show", false),
    // A bare inline time — no space after the colon — must not read as a track number.
    ("9:23", false),
    ("runtime: 89:00", false),
  ])
  func numberedTrackDetection(line: String, expected: Bool) {
    #expect(SetlistPreSegmenter.looksLikeNumberedTrack(line) == expected)
  }
}
