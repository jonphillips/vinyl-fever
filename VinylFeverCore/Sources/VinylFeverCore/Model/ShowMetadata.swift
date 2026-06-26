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

  private var sourceAlbumToken: String {
    guard
      let token = source.map({ SourceLabel.normalizedToken($0.token) }),
      !token.isEmpty
    else {
      return "unknown"
    }
    return token
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
