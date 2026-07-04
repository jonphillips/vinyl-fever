import Foundation
import SQLiteData

public struct AlbumIdentity: Equatable, Hashable, Sendable {
  public var album: String
  public var albumArtist: String

  public init(album: String, albumArtist: String) {
    self.album = album
    self.albumArtist = albumArtist
  }
}

public struct CompilationRuleset: Equatable, Sendable {
  public static let groupingDelimiter = " | "

  public var stripTrackAndDisc: Bool
  public var setCompilationFlag: Bool
  public var groupingTokens: [String]

  public init(
    stripTrackAndDisc: Bool = true,
    setCompilationFlag: Bool = false,
    groupingTokens: [String] = []
  ) {
    self.stripTrackAndDisc = stripTrackAndDisc
    self.setCompilationFlag = setCompilationFlag
    self.groupingTokens = Self.normalizedGroupingTokens(groupingTokens)
  }

  public static func normalizedGroupingTokens(_ tokens: [String]) -> [String] {
    var seen: Set<String> = []
    var normalized: [String] = []
    for token in tokens {
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.contains("|") else {
        continue
      }
      let key = trimmed.lowercased()
      guard seen.insert(key).inserted else {
        continue
      }
      normalized.append(trimmed)
    }
    return normalized
  }
}

@Table
public struct CompilationAlbum: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var name: String
  public var album: String
  public var albumArtist: String
  public var displayImage: Data?
  public var fallbackArtwork: Data?
  public var stripTrackAndDisc: Bool
  public var setCompilationFlag: Bool
  public var groupingTokensText: String
  public var seedFolderPath: String?
  public var seedWarningsText: String

  public init(
    id: UUID,
    name: String,
    identity: AlbumIdentity,
    displayImage: Data? = nil,
    fallbackArtwork: Data? = nil,
    ruleset: CompilationRuleset = CompilationRuleset(),
    seedFolderPath: String? = nil,
    seedWarnings: [String] = []
  ) {
    self.id = id
    self.name = name
    self.album = identity.album
    self.albumArtist = identity.albumArtist
    self.displayImage = displayImage
    self.fallbackArtwork = fallbackArtwork
    self.stripTrackAndDisc = ruleset.stripTrackAndDisc
    self.setCompilationFlag = ruleset.setCompilationFlag
    self.groupingTokensText = ruleset.groupingTokens.joined(separator: CompilationRuleset.groupingDelimiter)
    self.seedFolderPath = seedFolderPath
    self.seedWarningsText = seedWarnings.joined(separator: "\n")
  }

  public var identity: AlbumIdentity {
    get { AlbumIdentity(album: album, albumArtist: albumArtist) }
    set {
      album = newValue.album
      albumArtist = newValue.albumArtist
    }
  }

  public var ruleset: CompilationRuleset {
    get {
      CompilationRuleset(
        stripTrackAndDisc: stripTrackAndDisc,
        setCompilationFlag: setCompilationFlag,
        groupingTokens: groupingTokensText
          .components(separatedBy: CompilationRuleset.groupingDelimiter)
      )
    }
    set {
      stripTrackAndDisc = newValue.stripTrackAndDisc
      setCompilationFlag = newValue.setCompilationFlag
      groupingTokensText = newValue.groupingTokens.joined(separator: CompilationRuleset.groupingDelimiter)
    }
  }

  public var seedWarnings: [String] {
    seedWarningsText
      .split(whereSeparator: \.isNewline)
      .map(String.init)
  }
}

public struct CompilationAlbumSeedCandidate: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var folderURL: URL
  public var album: CompilationAlbum
  public var trackCount: Int
  public var warnings: [String]

  public init(
    id: UUID,
    folderURL: URL,
    album: CompilationAlbum,
    trackCount: Int,
    warnings: [String]
  ) {
    self.id = id
    self.folderURL = folderURL
    self.album = album
    self.trackCount = trackCount
    self.warnings = warnings
  }
}
