import Foundation

public struct ConversionPlan: Equatable, Sendable {
  public static let outputDirectoryName = "Output"

  public var showRoot: URL
  public var workingDirectory: URL
  public var outputDirectory: URL
  public var tracks: [ConversionTrackPlan]

  public init(
    showRoot: URL,
    workingDirectory: URL,
    outputDirectory: URL,
    tracks: [ConversionTrackPlan]
  ) {
    self.showRoot = showRoot
    self.workingDirectory = workingDirectory
    self.outputDirectory = outputDirectory
    self.tracks = tracks
  }

  public init(applyPlan: ApplyPlan) {
    let outputDirectory = applyPlan.showRoot
      .appendingPathComponent(Self.outputDirectoryName, isDirectory: true)
    self.init(
      showRoot: applyPlan.showRoot,
      workingDirectory: applyPlan.workingDirectory,
      outputDirectory: outputDirectory,
      tracks: applyPlan.tracks.map { track in
        ConversionTrackPlan(
          applyTrack: track,
          outputDirectory: outputDirectory
        )
      }
    )
  }

  public var requiresConversion: Bool {
    tracks.contains { $0.action == .convertToALAC }
  }

  public var convertibleTracks: [ConversionTrackPlan] {
    tracks.filter { $0.action == .convertToALAC }
  }

  public var requiredTools: Set<AudioTool> {
    guard !tracks.isEmpty else {
      return []
    }
    var tools: Set<AudioTool> = [.ffprobe]
    if requiresConversion {
      tools.insert(.ffmpeg)
    }
    return tools
  }

  public var verificationDirectoryRequirements: [VerificationDirectoryRequirement] {
    var requirements: [String: VerificationDirectoryRequirement] = [:]
    for track in tracks {
      let directory = track.verificationFile.deletingLastPathComponent()
      let key = directory.standardizedFileURL.path(percentEncoded: false)
      if requirements[key] == nil {
        requirements[key] = VerificationDirectoryRequirement(
          directory: directory,
          formats: []
        )
      }
      requirements[key]?.formats.insert(track.verificationFormat)
    }
    return requirements.values.sorted {
      $0.directory.path(percentEncoded: false) < $1.directory.path(percentEncoded: false)
    }
  }
}

public struct ConversionTrackPlan: Equatable, Identifiable, Sendable {
  public let id: ApplyTrackPlan.ID
  public var sourceFile: ScannedAudioFile
  public var workingFile: URL
  public var outputFile: URL
  public var tags: ProposedTags
  public var trackTotal: Int
  public var coverURL: URL?
  public var action: ConversionAction

  public init(
    id: ApplyTrackPlan.ID,
    sourceFile: ScannedAudioFile,
    workingFile: URL,
    outputFile: URL,
    tags: ProposedTags,
    trackTotal: Int,
    coverURL: URL?,
    action: ConversionAction
  ) {
    self.id = id
    self.sourceFile = sourceFile
    self.workingFile = workingFile
    self.outputFile = outputFile
    self.tags = tags
    self.trackTotal = trackTotal
    self.coverURL = coverURL
    self.action = action
  }

  public init(applyTrack: ApplyTrackPlan, outputDirectory: URL) {
    let action: ConversionAction =
      switch applyTrack.sourceFile.format {
      case .flac:
        .convertToALAC
      case .mp3, .m4a:
        .verifyWorkingOnly
      }
    let outputFile =
      switch action {
      case .convertToALAC:
        outputDirectory.appendingPathComponent(
          applyTrack.workingFile.deletingPathExtension().lastPathComponent + ".m4a"
        )
      case .verifyWorkingOnly:
        applyTrack.workingFile
      }
    self.init(
      id: applyTrack.id,
      sourceFile: applyTrack.sourceFile,
      workingFile: applyTrack.workingFile,
      outputFile: outputFile,
      tags: applyTrack.tags,
      trackTotal: applyTrack.trackTotal,
      coverURL: applyTrack.coverURL,
      action: action
    )
  }

  public var verificationFile: URL {
    switch action {
    case .convertToALAC:
      outputFile
    case .verifyWorkingOnly:
      workingFile
    }
  }

  public var verificationFormat: AudioFormat {
    switch action {
    case .convertToALAC:
      .m4a
    case .verifyWorkingOnly:
      sourceFile.format
    }
  }
}

public enum ConversionAction: String, Equatable, Sendable {
  case convertToALAC
  case verifyWorkingOnly
}

public struct VerificationDirectoryRequirement: Equatable, Sendable {
  public var directory: URL
  public var formats: Set<AudioFormat>

  public init(directory: URL, formats: Set<AudioFormat>) {
    self.directory = directory
    self.formats = formats
  }
}

public struct ConvertedTrack: Equatable, Identifiable, Sendable {
  public let id: ConversionTrackPlan.ID
  public var sourceURL: URL
  public var outputURL: URL
  public var status: RunFileOutcome.Status
  public var note: String

  public init(
    id: ConversionTrackPlan.ID,
    sourceURL: URL,
    outputURL: URL,
    status: RunFileOutcome.Status,
    note: String
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.outputURL = outputURL
    self.status = status
    self.note = note
  }
}

public struct ConversionResult: Equatable, Sendable {
  public var run: RunRecord
  public var convertedTracks: [ConvertedTrack]
  public var exitSummary: String

  public init(run: RunRecord, convertedTracks: [ConvertedTrack], exitSummary: String) {
    self.run = run
    self.convertedTracks = convertedTracks
    self.exitSummary = exitSummary
  }

  public var didSucceed: Bool {
    convertedTracks.allSatisfy { $0.status == .created }
  }
}
