import Foundation

public struct ImportedTrackRef: Equatable, Identifiable, Sendable {
  public let id: String
  public var title: String?
  public var album: String?
  public var albumArtist: String?
  public var trackNumber: Int?
  public var durationSeconds: Double?
  public var location: URL?

  public init(
    id: String,
    title: String? = nil,
    album: String? = nil,
    albumArtist: String? = nil,
    trackNumber: Int? = nil,
    durationSeconds: Double? = nil,
    location: URL? = nil
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.title = Self.normalizedOptionalText(title)
    self.album = Self.normalizedOptionalText(album)
    self.albumArtist = Self.normalizedOptionalText(albumArtist)
    self.trackNumber = trackNumber.flatMap { $0 > 0 ? $0 : nil }
    self.durationSeconds = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
    self.location = location?.standardizedFileURL
  }

  public var locationPath: String? {
    location.map(Self.normalizedFilePath)
  }

  public static func normalizedFilePath(_ url: URL) -> String {
    url.standardizedFileURL.path(percentEncoded: false)
  }

  private static func normalizedOptionalText(_ value: String?) -> String? {
    AudioTagVerifier.normalizedMetadataString(value)
  }
}

public struct ImportedTrack: Equatable, Identifiable, Sendable {
  public let id: ConversionTrackPlan.ID
  public var sourceURL: URL
  public var libraryRef: ImportedTrackRef?
  public var status: MusicImportStatus

  public init(
    id: ConversionTrackPlan.ID,
    sourceURL: URL,
    libraryRef: ImportedTrackRef?,
    status: MusicImportStatus
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.libraryRef = libraryRef
    self.status = status
  }

  public var didSucceed: Bool {
    status.didSucceed
  }

  public var runOutcomeStatus: RunFileOutcome.Status {
    status.runOutcomeStatus
  }

  public var note: String {
    switch status {
    case .imported:
      if let libraryRef {
        return "Imported as Music item \(libraryRef.id)."
      }
      return "Imported."
    case .alreadyPresent:
      if let libraryRef {
        return "Already present as Music item \(libraryRef.id)."
      }
      return "Already present."
    case .dropped:
      return "Dropped into Music's Automatically Add folder; Music will import it."
    case let .failed(message):
      return message
    }
  }
}

public enum MusicImportStatus: Equatable, Sendable {
  case imported
  case alreadyPresent
  /// The file was copied into Music's "Automatically Add" folder, but we could not confirm via
  /// scripting that Music had ingested it (a read timed out, or the track had not appeared before
  /// the deadline). The drop itself succeeded, so this is a success, not a failure — Music ingests
  /// the folder on its own schedule.
  case dropped
  case failed(String)

  public var didSucceed: Bool {
    switch self {
    case .imported, .alreadyPresent, .dropped:
      true
    case .failed:
      false
    }
  }

  public var runOutcomeStatus: RunFileOutcome.Status {
    switch self {
    case .imported:
      .created
    case .alreadyPresent:
      .skipped
    case .dropped:
      .created
    case .failed:
      .failed
    }
  }

  public var displayName: String {
    switch self {
    case .imported:
      "Imported"
    case .alreadyPresent:
      "Already present"
    case .dropped:
      "Dropped"
    case .failed:
      "Failed"
    }
  }
}

public struct ImportResult: Equatable, Sendable {
  public var run: RunRecord
  public var tracks: [ImportedTrack]
  public var exitSummary: String

  public init(run: RunRecord, tracks: [ImportedTrack], exitSummary: String) {
    self.run = run
    self.tracks = tracks
    self.exitSummary = exitSummary
  }

  public var didSucceed: Bool {
    !tracks.isEmpty && tracks.allSatisfy(\.didSucceed)
  }

  public var importedCount: Int {
    tracks.count { $0.status == .imported }
  }

  public var alreadyPresentCount: Int {
    tracks.count { $0.status == .alreadyPresent }
  }

  public var droppedCount: Int {
    tracks.count { $0.status == .dropped }
  }

  public var failedCount: Int {
    tracks.count { !$0.didSucceed }
  }
}

/// Builds the one-line run-log summary of an import's per-track outcomes. A single outcome
/// category reads as a bare label ("imported"); mixed categories are counted and joined
/// ("2 imported, 1 dropped (awaiting Music)").
public enum LibraryImportSummary {
  public static func text(for tracks: [ImportedTrack]) -> String {
    let failedCount = tracks.count { !$0.didSucceed }
    if failedCount > 0 {
      return "\(failedCount) of \(tracks.count) failed"
    }
    if tracks.isEmpty {
      return "no files"
    }
    var parts: [(count: Int, label: String)] = []
    let importedCount = tracks.count { $0.status == .imported }
    let droppedCount = tracks.count { $0.status == .dropped }
    let alreadyPresentCount = tracks.count { $0.status == .alreadyPresent }
    if importedCount > 0 {
      parts.append((importedCount, "imported"))
    }
    if droppedCount > 0 {
      parts.append((droppedCount, "dropped (awaiting Music)"))
    }
    if alreadyPresentCount > 0 {
      parts.append((alreadyPresentCount, "already present"))
    }
    if parts.count == 1 {
      return parts[0].label
    }
    return parts.map { "\($0.count) \($0.label)" }.joined(separator: ", ")
  }
}

public struct LibraryResolutionResult: Equatable, Sendable {
  public var albumTitle: String
  public var libraryTracks: [ImportedTrackRef]
  public var trackResolutions: [LibraryTrackResolution]

  public init(
    albumTitle: String,
    libraryTracks: [ImportedTrackRef],
    trackResolutions: [LibraryTrackResolution]
  ) {
    self.albumTitle = albumTitle
    self.libraryTracks = libraryTracks
    self.trackResolutions = trackResolutions
  }

  public var didResolveAll: Bool {
    !trackResolutions.isEmpty && trackResolutions.allSatisfy(\.isResolved)
  }

  public var resolvedCount: Int {
    trackResolutions.count { $0.isResolved }
  }
}

public struct LibraryTrackResolution: Equatable, Identifiable, Sendable {
  public let id: ConversionTrackPlan.ID
  public var producedFile: URL
  public var expectedAlbum: String
  public var expectedTitle: String
  public var expectedTrackNumber: Int
  public var libraryRef: ImportedTrackRef?
  public var strategy: LibraryTrackMatchStrategy?
  public var failure: LibraryTrackResolutionFailure?

  public init(
    id: ConversionTrackPlan.ID,
    producedFile: URL,
    expectedAlbum: String,
    expectedTitle: String,
    expectedTrackNumber: Int,
    libraryRef: ImportedTrackRef? = nil,
    strategy: LibraryTrackMatchStrategy? = nil,
    failure: LibraryTrackResolutionFailure? = nil
  ) {
    self.id = id
    self.producedFile = producedFile
    self.expectedAlbum = expectedAlbum
    self.expectedTitle = expectedTitle
    self.expectedTrackNumber = expectedTrackNumber
    self.libraryRef = libraryRef
    self.strategy = strategy
    self.failure = failure
  }

  public var isResolved: Bool {
    libraryRef != nil
  }
}

public enum LibraryTrackMatchStrategy: String, Equatable, Sendable {
  case location
  case albumTrackTitle

  public var displayName: String {
    switch self {
    case .location:
      "file location"
    case .albumTrackTitle:
      "album, track, title"
    }
  }
}

public enum LibraryTrackResolutionFailure: Equatable, Sendable {
  case notFound
  case ambiguous(strategy: LibraryTrackMatchStrategy, matches: [ImportedTrackRef.ID])

  public var displayMessage: String {
    switch self {
    case .notFound:
      "No matching Music library item was found."
    case let .ambiguous(strategy, matches):
      "Ambiguous \(strategy.displayName) match: \(matches.joined(separator: ", "))."
    }
  }
}

public enum MusicLibraryMatcher {
  public static func resolve(
    plan: ConversionPlan,
    libraryTracks: [ImportedTrackRef]
  ) -> LibraryResolutionResult {
    LibraryResolutionResult(
      albumTitle: plan.albumTitle,
      libraryTracks: libraryTracks,
      trackResolutions: plan.tracks.map { track in
        resolve(track: track, libraryTracks: libraryTracks)
      }
    )
  }

  public static func resolve(
    track: ConversionTrackPlan,
    libraryTracks: [ImportedTrackRef]
  ) -> LibraryTrackResolution {
    let locationMatches = libraryTracks.filter {
      $0.locationPath == ImportedTrackRef.normalizedFilePath(track.verificationFile)
    }
    if let locationResolution = resolution(
      track: track,
      matches: locationMatches,
      strategy: .location
    ) {
      return locationResolution
    }

    let expectedAlbum = AudioTagVerifier.normalizedMetadataString(track.tags.album)
    let expectedTitle = AudioTagVerifier.normalizedMetadataString(track.tags.title)
    let fallbackMatches = libraryTracks.filter { libraryTrack in
      AudioTagVerifier.normalizedMetadataString(libraryTrack.album) == expectedAlbum &&
        libraryTrack.trackNumber == track.tags.trackNumber &&
        AudioTagVerifier.normalizedMetadataString(libraryTrack.title) == expectedTitle
    }
    return resolution(
      track: track,
      matches: fallbackMatches,
      strategy: .albumTrackTitle
    ) ?? unresolved(track: track, failure: .notFound)
  }

  private static func resolution(
    track: ConversionTrackPlan,
    matches: [ImportedTrackRef],
    strategy: LibraryTrackMatchStrategy
  ) -> LibraryTrackResolution? {
    switch matches.count {
    case 0:
      return nil
    case 1:
      return LibraryTrackResolution(
        id: track.id,
        producedFile: track.verificationFile,
        expectedAlbum: track.tags.album ?? "",
        expectedTitle: track.tags.title ?? "",
        expectedTrackNumber: track.tags.trackNumber ?? 0,
        libraryRef: matches[0],
        strategy: strategy
      )
    default:
      return unresolved(
        track: track,
        failure: .ambiguous(strategy: strategy, matches: matches.map(\.id).sorted())
      )
    }
  }

  private static func unresolved(
    track: ConversionTrackPlan,
    failure: LibraryTrackResolutionFailure
  ) -> LibraryTrackResolution {
    LibraryTrackResolution(
      id: track.id,
      producedFile: track.verificationFile,
      expectedAlbum: track.tags.album ?? "",
      expectedTitle: track.tags.title ?? "",
      expectedTrackNumber: track.tags.trackNumber ?? 0,
      failure: failure
    )
  }
}

extension ConversionPlan {
  public var albumTitle: String {
    tracks.first?.tags.album ?? ""
  }
}
