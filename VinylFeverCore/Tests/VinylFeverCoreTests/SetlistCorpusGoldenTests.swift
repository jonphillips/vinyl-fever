import CustomDump
import Foundation
import Testing

@testable import VinylFeverCore

/// Golden-file regression pass over the real 18-file raw trading-note corpus
/// (`Fixtures/RawSetlists/`, the S0 plan's "per-corpus-file regression signal").
///
/// The model leg is non-deterministic, so this pins only the **deterministic bookend**:
/// `SetlistPreSegmenter`. For every corpus file it asserts (a) the segmenter runs without
/// crashing, (b) a `tracklist` region is found, (c) checksum blocks are excised from the
/// cleaned text, and (d) the full region classification matches a committed golden — so a
/// change in how any real note is segmented shows up as a reviewable diff, not a silent
/// drift.
///
/// **To regenerate goldens after an intentional pre-segmenter change:** flip `record` to
/// `true`, run the suite once (it rewrites the goldens and fails), eyeball the diff, flip
/// it back, and commit. A missing golden auto-records the same way, so a newly-added
/// fixture just needs one recording run.
@Suite
struct SetlistCorpusGoldenTests {
  /// Set to `true` to overwrite every golden from current segmenter output.
  static let record = false

  @Test(arguments: SetlistCorpusFixtures.rawFileNames)
  func segmentationMatchesGolden(fileName: String) throws {
    let raw = try SetlistCorpusFixtures.rawText(fileName)
    let segmented = SetlistPreSegmenter().segment(raw)

    // Structural invariants the plan calls for — checked directly, not just via the golden,
    // so a bad recording can't quietly bless a broken segmentation.
    #expect(
      segmented.regions.contains { $0.kind == .tracklist },
      "\(fileName): no tracklist region was found"
    )
    for hashLine in segmented.removedHashLines {
      #expect(
        !segmented.cleanedText.contains(hashLine),
        "\(fileName): an excised checksum line survived in the cleaned text"
      )
    }

    let rendered = SetlistCorpusFixtures.goldenText(for: segmented)
    let goldenURL = SetlistCorpusFixtures.goldenURL(for: fileName)

    if Self.record || !FileManager.default.fileExists(atPath: goldenURL.path) {
      try FileManager.default.createDirectory(
        at: goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try (rendered + "\n").write(to: goldenURL, atomically: true, encoding: .utf8)
      Issue.record("Recorded golden for \(fileName); re-run with `record = false` to verify.")
      return
    }

    let expected = try String(contentsOf: goldenURL, encoding: .utf8)
    expectNoDifference(rendered.trimmedTail, expected.trimmedTail)
  }
}

/// Fixture access + the deterministic golden renderer. The corpus lives beside this test
/// source, located via `#filePath` (the swift-snapshot-testing idiom) so no SPM resource
/// bundling is needed.
enum SetlistCorpusFixtures {
  static let directory = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures/RawSetlists", directoryHint: .isDirectory)

  /// Every `NN_..._raw.txt` fixture, sorted — the 18-file corpus. The manifest and the
  /// `Golden/` subdirectory are deliberately excluded.
  static let rawFileNames: [String] = {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return contents.filter { $0.hasSuffix("_raw.txt") }.sorted()
  }()

  static func rawText(_ fileName: String) throws -> String {
    try String(contentsOf: directory.appending(path: fileName), encoding: .utf8)
  }

  static func goldenURL(for fileName: String) -> URL {
    let base = fileName.hasSuffix(".txt") ? String(fileName.dropLast(4)) : fileName
    return directory.appending(path: "Golden/\(base).seg.txt")
  }

  /// A stable, reviewable dump of the segmentation: hash/line counts followed by each
  /// region's kind and its lines, in order.
  static func goldenText(for notes: PreSegmentedNotes) -> String {
    var out = """
      removedHashLines: \(notes.removedHashLines.count)
      cleanedLines: \(notes.cleanedText.split(separator: "\n", omittingEmptySubsequences: false).count)
      regionCount: \(notes.regions.count)
      """
    for (index, region) in notes.regions.enumerated() {
      out += "\n\n[\(index + 1)] \(region.kind.rawValue) (\(region.lines.count) lines)"
      for line in region.lines {
        out += "\n    \(line)"
      }
    }
    return out
  }
}

private extension String {
  /// Trailing-newline-insensitive comparison, so an editor re-save of a golden can't fail
  /// the suite.
  var trimmedTail: String {
    var copy = self
    while copy.last == "\n" || copy.last == "\r" { copy.removeLast() }
    return copy
  }
}
