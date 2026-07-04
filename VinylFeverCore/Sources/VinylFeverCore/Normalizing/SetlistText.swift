import Foundation

/// Renders a `SetlistDraft` into the canonical `setlist.txt` shape
/// (setlist-formatting-rules.md, *Standard Output Shape*). Pure and deterministic —
/// the same renderer drives the preview and the eventual write, so what Jon approves
/// is byte-for-byte what lands on disk.
public enum SetlistText {
  /// The composed `ALBUM:` value: `YYYY-MM-DD: Location - Venue (Source)`, with the
  /// documented per-field fallbacks (`Unknown Date`, `Unknown City`, `Unknown Venue`,
  /// `(unknown)`). If the draft already carries an explicit `album` (e.g. a curated
  /// compilation title), that verbatim value wins over composition.
  public static func composedAlbum(_ tags: ShowTags) -> String {
    if case let .value(album) = tags.album {
      return album
    }
    let date = value(tags.date.text, unknown: "Unknown Date")
    let location = value(tags.location.text, unknown: "Unknown City")
    let venue = value(tags.venue.text, unknown: "Unknown Venue")
    return "\(date): \(location) - \(venue) (\(sourceToken(tags.source)))"
  }

  /// The full `setlist.txt`: tags block, one blank line, then the plain stacked track
  /// titles (no numbers, no notes, no headers — the format keeps the list bare).
  public static func render(_ draft: SetlistDraft) -> String {
    let tags = draft.tags
    var lines = [
      "ARTIST: \(draft.tags.artist.text)",
      "ALBUM: \(composedAlbum(tags))",
      "ALBUMARTIST: \(draft.tags.albumArtist.text)",
      "DATE: \(value(tags.date.text, unknown: "Unknown Date"))",
      "VENUE: \(value(tags.venue.text, unknown: "Unknown Venue"))",
      "LOCATION: \(value(tags.location.text, unknown: "Unknown Location"))",
      "",
    ]
    lines += draft.tracks
      .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return lines.joined(separator: "\n") + "\n"
  }

  /// The bare source token for the `(Source)` suffix — the controlled-vocabulary
  /// token without parentheses, or `unknown` when absent.
  static func sourceToken(_ source: Field) -> String {
    let normalized = SourceLabel.normalizedToken(source.text)
    return normalized.isEmpty ? "unknown" : normalized
  }

  private static func value(_ text: String, unknown: String) -> String {
    text.isEmpty ? unknown : text
  }
}
