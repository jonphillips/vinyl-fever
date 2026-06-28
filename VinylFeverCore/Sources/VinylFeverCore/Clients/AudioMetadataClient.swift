import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct AudioMetadataClient: Sendable {
  public var read: @Sendable (_ request: AudioMetadataRequest) async throws -> AudioTags
}

public struct AudioMetadataRequest: Equatable, Sendable {
  public var url: URL
  public var format: AudioFormat
  public var toolPaths: AudioToolPaths

  public init(url: URL, format: AudioFormat, toolPaths: AudioToolPaths) {
    self.url = url
    self.format = format
    self.toolPaths = toolPaths
  }

  public init(file: ScannedAudioFile, toolPaths: AudioToolPaths) {
    self.init(url: file.url, format: file.format, toolPaths: toolPaths)
  }
}

extension AudioMetadataClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension AudioMetadataClient {
  public static var liveValue: Self {
    @Dependency(\.scriptClient) var scriptClient

    return Self { request in
      try await LiveAudioMetadataReader(scriptClient: scriptClient).read(request: request)
    }
  }
}

extension DependencyValues {
  public var audioMetadataClient: AudioMetadataClient {
    get { self[AudioMetadataClient.self] }
    set { self[AudioMetadataClient.self] = newValue }
  }
}

private struct LiveAudioMetadataReader: Sendable {
  var scriptClient: ScriptClient

  func read(request: AudioMetadataRequest) async throws -> AudioTags {
    switch request.format {
    case .flac:
      try await readFLAC(request: request)
    case .mp3, .m4a:
      try await readFFProbe(request: request)
    }
  }

  private func readFLAC(request: AudioMetadataRequest) async throws -> AudioTags {
    let tagResult = try await runSuccessful(
      AudioMetadataCommands.flacTagExport(url: request.url, toolPaths: request.toolPaths)
    )
    let streamResult = try await runSuccessful(
      AudioMetadataCommands.flacStreamInfo(url: request.url, toolPaths: request.toolPaths)
    )
    let pictureResult = try await runSuccessful(
      AudioMetadataCommands.flacPictureList(url: request.url, toolPaths: request.toolPaths)
    )

    return FLACMetadataParser.parse(
      tagsOutput: tagResult.standardOutputText,
      streamInfoOutput: streamResult.standardOutputText,
      pictureListOutput: pictureResult.standardOutputText
    )
  }

  private func readFFProbe(request: AudioMetadataRequest) async throws -> AudioTags {
    let result = try await runSuccessful(
      AudioMetadataCommands.ffprobeJSON(url: request.url, toolPaths: request.toolPaths)
    )
    return try FFProbeMetadataParser.parse(result.standardOutput)
  }

  private func runSuccessful(_ command: ScriptCommand) async throws -> ScriptResult {
    let result = try await scriptClient.run(command)
    guard result.isSuccessful else {
      throw AudioMetadataError.commandFailed(
        tool: command.tool,
        exitCode: result.exitCode,
        output: result.combinedOutputText
      )
    }
    return result
  }
}

public enum AudioMetadataError: LocalizedError, Equatable, Sendable {
  case missingTool(AudioTool)
  case commandFailed(tool: AudioTool, exitCode: Int32, output: String)
  case invalidFFProbeJSON

  public var errorDescription: String? {
    switch self {
    case let .missingTool(tool):
      return "\(tool.displayName) is not available. \(tool.installHint)."
    case let .commandFailed(tool, exitCode, output):
      let detail = output
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
      if let detail {
        return "\(tool.displayName) exited \(exitCode): \(detail)"
      }
      return "\(tool.displayName) exited \(exitCode)."
    case .invalidFFProbeJSON:
      return "ffprobe returned invalid JSON."
    }
  }
}
