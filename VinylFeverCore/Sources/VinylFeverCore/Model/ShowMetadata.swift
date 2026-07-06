import Foundation

public struct ShowMetadata: Equatable, Sendable {
  public var tags: ShowTags
  public var source: SourceLabel?
  public var albumTitleKind: AlbumTitleKind

  public init(
    tags: ShowTags,
    source: SourceLabel? = nil,
    albumTitleKind: AlbumTitleKind = .liveShow()
  ) {
    self.tags = tags
    self.source = source
    self.albumTitleKind = albumTitleKind
  }

  public var albumTitle: String {
    switch albumTitleKind {
    case let .liveShow(qualifier):
      let date = tags.date.albumTitleText
      let location = tags.location.albumText(unknown: "Unknown City")
      let venue = tags.venue.albumText(unknown: "Unknown Venue")
      var title = "\(date): \(location) - \(venue)"
      if let qualifier = qualifier.nonEmptyText {
        title += " (\(qualifier))"
      }
      title += " (\(sourceAlbumToken))"
      return title

    case let .compilation(title):
      return "\(title.albumText(unknown: "Unknown Album")) (Compilation)"
    }
  }

  public var sortAlbum: String {
    albumTitle
  }

  /// The `(Source)` suffix token. An explicitly chosen `SourceLabel` (the header
  /// picker) wins as an override; otherwise it falls back to the source the parser
  /// or Normalizer inferred into `tags.source`, matching `SetlistText`'s renderer so
  /// the live-app title agrees with the composed `setlist.txt`. `unknown` when absent.
  private var sourceAlbumToken: String {
    if let source {
      let token = SourceLabel.normalizedToken(source.token)
      if !token.isEmpty {
        return token
      }
    }
    let inferred = SourceLabel.normalizedToken(tags.source.text)
    return inferred.isEmpty ? "unknown" : inferred
  }
}

public enum AlbumTitleKind: Equatable, Sendable {
  case liveShow(qualifier: Field = .unknown)
  case compilation(title: Field)
}

extension Field {
  public var nonEmptyText: String? {
    switch self {
    case let .value(value):
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case .unknown:
      return nil
    }
  }

  public func albumText(unknown: String) -> String {
    nonEmptyText ?? unknown
  }
}

extension DateField {
  public var albumTitleText: String {
    switch self {
    case let .iso(year, month, day):
      "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
    case .unknown:
      "Unknown Date"
    }
  }
}
