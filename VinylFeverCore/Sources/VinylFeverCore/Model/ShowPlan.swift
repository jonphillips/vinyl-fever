import Foundation

public struct ShowPlan: Equatable, Sendable {
  public var metadata: ShowMetadata
  public var tracks: [TrackPlan]
  public var issues: [PlanIssue]

  public init(metadata: ShowMetadata, tracks: [TrackPlan], issues: [PlanIssue]) {
    self.metadata = metadata
    self.tracks = tracks
    self.issues = issues
  }

  public init(
    folder: ScannedShowFolder,
    setlist: SetlistDraft,
    metadata: ShowMetadata
  ) {
    let sortedAudioFiles = folder.audioFiles.sorted { lhs, rhs in
      lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
    }
    let zeroPadWidth = Self.zeroPadWidth(trackCount: setlist.tracks.count)

    self.init(
      metadata: metadata,
      tracks: zip(sortedAudioFiles, setlist.tracks).enumerated().map { index, pair in
        let (sourceFile, track) = pair
        let trackNumber = index + 1
        let proposedTags = ProposedTags(
          title: track.title,
          album: metadata.albumTitle,
          sortAlbum: metadata.sortAlbum,
          artist: metadata.tags.artist.displayText,
          albumArtist: metadata.tags.albumArtist.displayText,
          trackNumber: trackNumber,
          discNumber: Self.m1DiscNumber
        )
        return TrackPlan(
          id: track.id,
          sourceFile: sourceFile,
          track: track,
          proposedFilename: Self.proposedFilename(
            trackNumber: trackNumber,
            zeroPadWidth: zeroPadWidth,
            title: track.title,
            fileExtension: sourceFile.format.rawValue
          ),
          proposedTags: proposedTags
        )
      },
      issues: Self.issues(audioFileCount: sortedAudioFiles.count, tracks: setlist.tracks)
    )
  }

  public var isReadyToImport: Bool {
    issues.allSatisfy { !$0.isBlocking }
  }

  private static func zeroPadWidth(trackCount: Int) -> Int {
    max(2, String(trackCount).count)
  }

  private static let m1DiscNumber = 1

  private static func proposedFilename(
    trackNumber: Int,
    zeroPadWidth: Int,
    title: String,
    fileExtension: String
  ) -> String {
    let paddedTrackNumber = String(format: "%0\(zeroPadWidth)d", trackNumber)
    let filenameTitle = FilenameSanitizer.sanitizedFilenameComponent(title)
    return "\(paddedTrackNumber) - \(filenameTitle).\(fileExtension)"
  }

  private static func issues(audioFileCount: Int, tracks: [SetlistTrack]) -> [PlanIssue] {
    var issues: [PlanIssue] = []

    if audioFileCount == 0 {
      issues.append(.noAudioFiles)
    }
    if tracks.isEmpty {
      issues.append(.emptySetlist)
    }
    if audioFileCount != tracks.count {
      issues.append(.fileCountMismatch(files: audioFileCount, tracks: tracks.count))
    }
    for (index, track) in tracks.enumerated()
    where track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.missingTitle(trackIndex: index + 1))
    }

    return issues
  }
}

public struct TrackPlan: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var sourceFile: ScannedAudioFile
  public var track: SetlistTrack
  public var proposedFilename: String
  public var proposedTags: ProposedTags

  public init(
    id: UUID,
    sourceFile: ScannedAudioFile,
    track: SetlistTrack,
    proposedFilename: String,
    proposedTags: ProposedTags
  ) {
    self.id = id
    self.sourceFile = sourceFile
    self.track = track
    self.proposedFilename = proposedFilename
    self.proposedTags = proposedTags
  }
}

public struct ProposedTags: Equatable, Sendable {
  public var title: String?
  public var album: String?
  public var sortAlbum: String?
  public var artist: String?
  public var albumArtist: String?
  public var grouping: String?
  public var comments: String?
  public var isCompilation: Bool?
  public var trackNumber: Int?
  public var trackTotal: Int?
  public var discNumber: Int?
  public var clearedFields: Set<Field>

  public init(
    title: String? = nil,
    album: String? = nil,
    sortAlbum: String? = nil,
    artist: String? = nil,
    albumArtist: String? = nil,
    grouping: String? = nil,
    comments: String? = nil,
    isCompilation: Bool? = nil,
    trackNumber: Int? = nil,
    trackTotal: Int? = nil,
    discNumber: Int? = nil,
    clearedFields: Set<Field> = []
  ) {
    self.title = title
    self.album = album
    self.sortAlbum = sortAlbum
    self.artist = artist
    self.albumArtist = albumArtist
    self.grouping = grouping
    self.comments = comments
    self.isCompilation = isCompilation
    self.trackNumber = trackNumber
    self.trackTotal = trackTotal
    self.discNumber = discNumber
    self.clearedFields = clearedFields
  }

  public enum Field: String, CaseIterable, Equatable, Hashable, Sendable {
    case title
    case album
    case sortAlbum
    case artist
    case albumArtist
    case grouping
    case comments
    case isCompilation
    case trackNumber
    case trackTotal
    case discNumber
  }

  public func clearing(_ fields: Field...) -> Self {
    var copy = self
    copy.clearedFields.formUnion(fields)
    return copy
  }
}

public enum PlanIssue: Equatable, Hashable, Sendable {
  case noAudioFiles
  case emptySetlist
  case fileCountMismatch(files: Int, tracks: Int)
  case missingTitle(trackIndex: Int)

  public var isBlocking: Bool {
    true
  }

  public var message: String {
    switch self {
    case .noAudioFiles:
      "No audio files detected."
    case .emptySetlist:
      "No setlist tracks parsed."
    case let .fileCountMismatch(files, tracks):
      "\(files) audio files, \(tracks) setlist tracks."
    case let .missingTitle(trackIndex):
      "Track \(trackIndex) is missing a title."
    }
  }
}

public enum FilenameSanitizer {
  public static let illegalFilenameScalars = CharacterSet(charactersIn: "/:\u{0}")
  public static let illegalFilenameReplacement = " - "
  public static let untitledFilenameComponent = "Untitled"

  public static func sanitizedFilenameComponent(_ component: String) -> String {
    var sanitized = ""
    for scalar in component.unicodeScalars {
      if illegalFilenameScalars.contains(scalar) {
        sanitized += illegalFilenameReplacement
      } else {
        sanitized.append(Character(scalar))
      }
    }

    let collapsedWhitespace = sanitized
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return collapsedWhitespace.isEmpty ? untitledFilenameComponent : collapsedWhitespace
  }
}
