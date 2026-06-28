import Foundation

public struct ApplyPlan: Equatable, Sendable {
  public static let workingDirectoryName = "Working"

  public var showRoot: URL
  public var workingDirectory: URL
  public var coverURL: URL?
  public var tracks: [ApplyTrackPlan]
  public var operations: [FileOperation]

  public init(
    showRoot: URL,
    workingDirectory: URL,
    coverURL: URL?,
    tracks: [ApplyTrackPlan],
    operations: [FileOperation]
  ) {
    self.showRoot = showRoot
    self.workingDirectory = workingDirectory
    self.coverURL = coverURL
    self.tracks = tracks
    self.operations = operations
  }

  public init(showPlan: ShowPlan, showRoot: URL, coverURL: URL? = nil) {
    let showRoot = showRoot.standardizedFileURL
    let workingDirectory = showRoot.appendingPathComponent(Self.workingDirectoryName, isDirectory: true)
    let trackTotal = showPlan.tracks.count
    let tracks = showPlan.tracks.map { trackPlan in
      let workingFile = workingDirectory.appendingPathComponent(trackPlan.proposedFilename)
      return ApplyTrackPlan(
        id: trackPlan.id,
        sourceFile: trackPlan.sourceFile,
        workingFile: workingFile,
        tags: trackPlan.proposedTags,
        trackTotal: trackTotal,
        coverURL: coverURL?.standardizedFileURL
      )
    }
    self.init(
      showRoot: showRoot,
      workingDirectory: workingDirectory,
      coverURL: coverURL?.standardizedFileURL,
      tracks: tracks,
      operations: tracks.flatMap { track in
        [
          .copy(source: track.sourceFile.url, destination: track.workingFile),
          .writeTags(track),
        ]
      }
    )
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
}

public struct ApplyTrackPlan: Equatable, Identifiable, Sendable {
  public let id: TrackPlan.ID
  public var sourceFile: ScannedAudioFile
  public var workingFile: URL
  public var tags: ProposedTags
  public var trackTotal: Int
  public var coverURL: URL?

  public init(
    id: TrackPlan.ID,
    sourceFile: ScannedAudioFile,
    workingFile: URL,
    tags: ProposedTags,
    trackTotal: Int,
    coverURL: URL?
  ) {
    self.id = id
    self.sourceFile = sourceFile
    self.workingFile = workingFile
    self.tags = tags
    self.trackTotal = trackTotal
    self.coverURL = coverURL
  }
}

public enum FileOperation: Equatable, Sendable {
  case copy(source: URL, destination: URL)
  case writeTags(ApplyTrackPlan)
}

public struct AppliedTrack: Equatable, Identifiable, Sendable {
  public let id: ApplyTrackPlan.ID
  public var sourceURL: URL
  public var workingURL: URL
  public var status: RunFileOutcome.Status
  public var note: String

  public init(
    id: ApplyTrackPlan.ID,
    sourceURL: URL,
    workingURL: URL,
    status: RunFileOutcome.Status,
    note: String
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.workingURL = workingURL
    self.status = status
    self.note = note
  }
}

public struct ApplyResult: Equatable, Sendable {
  public var run: RunRecord
  public var appliedTracks: [AppliedTrack]
  public var exitSummary: String

  public init(run: RunRecord, appliedTracks: [AppliedTrack], exitSummary: String) {
    self.run = run
    self.appliedTracks = appliedTracks
    self.exitSummary = exitSummary
  }

  public var didSucceed: Bool {
    appliedTracks.allSatisfy { $0.status == .created }
  }
}
