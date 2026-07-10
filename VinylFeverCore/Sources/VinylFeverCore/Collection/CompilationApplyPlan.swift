import Foundation

public enum ArtworkDecision: Equatable, Sendable {
  case keepExisting
  case applyFallback
}

public struct CompilationTagDiff: Equatable, Identifiable, Sendable {
  public var id: String { field }
  public var field: String
  public var current: String?
  public var proposed: String?

  public init(field: String, current: String?, proposed: String?) {
    self.field = field
    self.current = current
    self.proposed = proposed
  }
}

public struct CompilationTrackPlan: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var sourceFile: ScannedAudioFile
  public var workingFile: URL
  public var current: AudioTags
  public var proposed: ProposedTags
  public var artwork: ArtworkDecision
  public var fallbackArtworkURL: URL?
  public var diffs: [CompilationTagDiff]

  public init(
    id: UUID,
    sourceFile: ScannedAudioFile,
    workingFile: URL,
    current: AudioTags,
    proposed: ProposedTags,
    artwork: ArtworkDecision,
    fallbackArtworkURL: URL?,
    diffs: [CompilationTagDiff]
  ) {
    self.id = id
    self.sourceFile = sourceFile
    self.workingFile = workingFile
    self.current = current
    self.proposed = proposed
    self.artwork = artwork
    self.fallbackArtworkURL = fallbackArtworkURL
    self.diffs = diffs
  }
}

public struct CompilationApplyPlan: Equatable, Sendable {
  public var entry: CompilationAlbum
  public var sourceRoot: URL
  public var workingDirectory: URL
  public var tracks: [CompilationTrackPlan]

  public init(
    entry: CompilationAlbum,
    sourceRoot: URL,
    workingDirectory: URL? = nil,
    tracks: [CompilationTrackPlan]
  ) {
    let sourceRoot = sourceRoot.standardizedFileURL
    self.entry = entry
    self.sourceRoot = sourceRoot
    self.workingDirectory = workingDirectory?.standardizedFileURL
      ?? sourceRoot.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
    self.tracks = tracks
  }

  public init(
    entry: CompilationAlbum,
    sourceRoot: URL,
    files: [ScannedAudioFile],
    currentTagsByFileID: [ScannedAudioFile.ID: AudioTags],
    fallbackArtworkURL: URL? = nil,
    recipeDeltasByFileID: [ScannedAudioFile.ID: [ProposedTags]] = [:]
  ) {
    let sourceRoot = sourceRoot.standardizedFileURL
    let workingDirectory = sourceRoot.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
    let tracks = files.sorted { lhs, rhs in
      lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
    }
    .map { file in
      let current = currentTagsByFileID[file.id] ?? AudioTags()
      let artwork: ArtworkDecision = current.hasEmbeddedArtwork ? .keepExisting : .applyFallback
      let compilationDelta = Self.proposedTags(entry: entry, current: current)
      let proposed = RecipeTagMerge.merge(
        compilation: compilationDelta,
        recipes: recipeDeltasByFileID[file.id] ?? []
      )
      return CompilationTrackPlan(
        id: file.id,
        sourceFile: file,
        workingFile: workingDirectory.appendingPathComponent(file.lastPathComponentForWorkingCopy),
        current: current,
        proposed: proposed,
        artwork: artwork,
        fallbackArtworkURL: artwork == .applyFallback ? fallbackArtworkURL?.standardizedFileURL : nil,
        diffs: Self.diffs(current: current, proposed: proposed, artwork: artwork)
      )
    }
    self.init(entry: entry, sourceRoot: sourceRoot, workingDirectory: workingDirectory, tracks: tracks)
  }

  public var requiredTools: Set<AudioTool> {
    Set(
      tracks.map { track in
        switch track.sourceFile.format {
        case .flac:
          AudioTool.metaflac
        case .mp3, .m4a:
          AudioTool.ffmpeg
        }
      }
    )
  }

  private static func proposedTags(entry: CompilationAlbum, current: AudioTags) -> ProposedTags {
    let grouping = mergedGrouping(existing: current.grouping, addedTokens: entry.ruleset.groupingTokens)
    var clearedFields: Set<ProposedTags.Field> = [.isCompilation]
    if entry.ruleset.stripTrackAndDisc {
      clearedFields.formUnion([.trackNumber, .trackTotal, .discNumber])
    }
    return ProposedTags(
      album: entry.identity.album,
      albumArtist: entry.identity.albumArtist,
      grouping: grouping,
      isCompilation: entry.ruleset.setCompilationFlag ? true : false,
      trackNumber: entry.ruleset.stripTrackAndDisc ? nil : current.trackNumber,
      trackTotal: entry.ruleset.stripTrackAndDisc ? nil : current.trackTotal,
      discNumber: entry.ruleset.stripTrackAndDisc ? nil : current.discNumber,
      clearedFields: clearedFields
    )
  }

  private static func diffs(
    current: AudioTags,
    proposed: ProposedTags,
    artwork: ArtworkDecision
  ) -> [CompilationTagDiff] {
    [
      CompilationTagDiff(field: "Album", current: current.album, proposed: proposed.album),
      CompilationTagDiff(field: "Album Artist", current: current.albumArtist, proposed: proposed.albumArtist),
      CompilationTagDiff(field: "Grouping", current: current.grouping, proposed: proposed.grouping),
      CompilationTagDiff(
        field: "Compilation",
        current: current.isCompilation.map { $0 ? "true" : "false" },
        proposed: proposed.isCompilation.map { $0 ? "true" : "clear" }
      ),
      CompilationTagDiff(
        field: "Track Number",
        current: current.trackNumber.map(String.init),
        proposed: proposed.clearedFields.contains(.trackNumber)
          ? nil
          : proposed.trackNumber.map(String.init) ?? current.trackNumber.map(String.init)
      ),
      CompilationTagDiff(
        field: "Disc Number",
        current: current.discNumber.map(String.init),
        proposed: proposed.clearedFields.contains(.discNumber)
          ? nil
          : proposed.discNumber.map(String.init) ?? current.discNumber.map(String.init)
      ),
      CompilationTagDiff(
        field: "Artwork",
        current: current.hasEmbeddedArtwork ? "Embedded artwork" : "No embedded artwork",
        proposed: artwork == .keepExisting ? "Keep existing" : "Apply fallback"
      ),
    ]
  }

  public static func mergedGrouping(existing: String?, addedTokens: [String]) -> String? {
    let existingTokens = existing?
      .components(separatedBy: CompilationRuleset.groupingDelimiter) ?? []
    let tokens = CompilationRuleset.normalizedGroupingTokens(existingTokens + addedTokens)
    return tokens.isEmpty ? nil : tokens.joined(separator: CompilationRuleset.groupingDelimiter)
  }
}

public extension ApplyPlan {
  init(compilationPlan: CompilationApplyPlan) {
    let tracks = compilationPlan.tracks.map { track in
      ApplyTrackPlan(
        id: track.id,
        sourceFile: track.sourceFile,
        workingFile: track.workingFile,
        tags: track.proposed,
        trackTotal: track.current.trackTotal ?? 0,
        coverURL: track.fallbackArtworkURL
      )
    }
    self.init(
      showRoot: compilationPlan.sourceRoot,
      workingDirectory: compilationPlan.workingDirectory,
      coverURL: nil,
      tracks: tracks,
      operations: tracks.flatMap { track in
        [
          .copy(source: track.sourceFile.url, destination: track.workingFile),
          .writeTags(track),
        ]
      }
    )
  }
}

private extension ScannedAudioFile {
  var lastPathComponentForWorkingCopy: String {
    let component = url.lastPathComponent
    guard !component.isEmpty else {
      return "\(id.uuidString).\(format.rawValue)"
    }
    return component
  }
}
