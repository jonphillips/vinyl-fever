import Dependencies
import Foundation
import Observation
import SQLiteData
import VinylFeverCore

@MainActor
@Observable
final class AppModel {
  @ObservationIgnored
  @Dependency(\.fileSystemClient) private var fileSystemClient
  @ObservationIgnored
  @Dependency(\.toolPathClient) private var toolPathClient
  @ObservationIgnored
  @Dependency(\.audioMetadataClient) private var audioMetadataClient
  @ObservationIgnored
  @Dependency(\.runLogClient) private var runLogClient
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid

  var selectedSection: AppSection = .liveShows
  var destination: Destination?
  var scannedShowFolder: ScannedShowFolder?
  var scanErrorMessage: String?
  var setlistInput = ""
  var setlistDraft: SetlistDraft?
  var setlistErrorMessage: String?
  var selectedSourceLabelID: SourceLabel.ID?
  var newSourceLabelToken = ""
  var sourceLabelErrorMessage: String?
  var toolStatuses = AudioTool.allCases.map { ToolStatus.missing(tool: $0) }
  var hasResolvedToolStatuses = false
  var toolStatusErrorMessage: String?
  var runLogErrorMessage: String?
  var currentMetadataByFileID: [ScannedAudioFile.ID: AudioMetadataLoadState] = [:]

  enum Destination: Hashable {
  }

  func scanShowFolder(at url: URL) {
    do {
      scannedShowFolder = try fileSystemClient.scanShowFolder(root: url)
      currentMetadataByFileID = [:]
      scanErrorMessage = nil
    } catch {
      scannedShowFolder = nil
      currentMetadataByFileID = [:]
      scanErrorMessage = error.localizedDescription
    }
  }

  func loadSetlistText(from url: URL) {
    do {
      setlistInput = try loadTextFile(at: url)
      parseSetlistInput()
      setlistErrorMessage = nil
    } catch {
      setlistErrorMessage = error.localizedDescription
    }
  }

  func parseSetlistInput() {
    setlistDraft = SetlistParser().parse(setlistInput)
    setlistErrorMessage = nil
  }

  func addSourceLabel() {
    let token = SourceLabel.normalizedToken(newSourceLabelToken)
    guard !token.isEmpty else {
      sourceLabelErrorMessage = "Enter a source label."
      return
    }

    do {
      let existingSourceLabels = try database.read { db in
        try SourceLabel.order(by: \.token).fetchAll(db)
      }
      guard !existingSourceLabels.contains(where: { $0.normalizedTokenKey == token.lowercased() })
      else {
        sourceLabelErrorMessage = "That source label already exists."
        return
      }

      let sourceLabel = SourceLabel(id: uuid(), token: token, isBuiltIn: false)
      try database.write { db in
        try SourceLabel.upsert { sourceLabel }.execute(db)
      }
      selectedSourceLabelID = sourceLabel.id
      newSourceLabelToken = ""
      sourceLabelErrorMessage = nil
    } catch {
      sourceLabelErrorMessage = error.localizedDescription
    }
  }

  func deleteSourceLabel(_ sourceLabel: SourceLabel) {
    guard !sourceLabel.isBuiltIn else {
      sourceLabelErrorMessage = "Built-in source labels cannot be removed."
      return
    }

    do {
      try database.write { db in
        try SourceLabel.find(sourceLabel.id).delete().execute(db)
      }
      if selectedSourceLabelID == sourceLabel.id {
        selectedSourceLabelID = nil
      }
      sourceLabelErrorMessage = nil
    } catch {
      sourceLabelErrorMessage = error.localizedDescription
    }
  }

  func toolStatus(for tool: AudioTool) -> ToolStatus {
    toolStatuses.first { $0.tool == tool } ?? .missing(tool: tool)
  }

  func refreshToolStatuses(settings: AppSetting) async {
    do {
      toolStatuses = try await toolPathClient.resolveTools(settings.toolPathOverrides)
      hasResolvedToolStatuses = true
      toolStatusErrorMessage = nil
    } catch is CancellationError {
    } catch {
      hasResolvedToolStatuses = false
      toolStatusErrorMessage = error.localizedDescription
    }
  }

  func refreshCurrentMetadata() async {
    guard let scannedShowFolder else {
      currentMetadataByFileID = [:]
      return
    }

    let files = scannedShowFolder.audioFiles
    guard hasResolvedToolStatuses else {
      currentMetadataByFileID = Dictionary(
        uniqueKeysWithValues: files.map { ($0.id, .notLoaded) }
      )
      return
    }

    currentMetadataByFileID = Dictionary(
      uniqueKeysWithValues: files.map { ($0.id, .loading) }
    )

    let toolPaths = AudioToolPaths(statuses: toolStatuses)
    let run = await openMetadataReadRun(
      folder: scannedShowFolder,
      files: files,
      toolPaths: toolPaths
    )
    let audioMetadataClient = self.audioMetadataClient
    var failedCount = 0
    await withTaskGroup(of: (ScannedAudioFile.ID, AudioMetadataLoadState).self) { group in
      for file in files {
        group.addTask {
          do {
            try Task.checkCancellation()
            let tags = try await audioMetadataClient.read(
              AudioMetadataRequest(file: file, toolPaths: toolPaths)
            )
            return (file.id, .loaded(tags))
          } catch is CancellationError {
            return (file.id, .notLoaded)
          } catch {
            return (file.id, .failed(error.localizedDescription))
          }
        }
      }

      for await (id, state) in group {
        currentMetadataByFileID[id] = state
        guard let file = files.first(where: { $0.id == id }) else {
          continue
        }
        let outcome = metadataReadOutcome(file: file, state: state)
        if outcome.status == .failed {
          failedCount += 1
        }
        await appendMetadataReadOutcome(outcome, to: run)
      }
    }

    await closeMetadataReadRun(run, fileCount: files.count, failedCount: failedCount)
  }

  func saveToolOverride(_ path: String?, for tool: AudioTool, settings: AppSetting) {
    let updatedSettings = settings.withOverridePath(path, for: tool)
    do {
      try database.write { db in
        try AppSetting.upsert { updatedSettings }.execute(db)
      }
      toolStatusErrorMessage = nil
    } catch {
      toolStatusErrorMessage = error.localizedDescription
    }
  }

  private func loadTextFile(at url: URL) throws -> String {
    var detectedEncoding = String.Encoding.utf8
    if let text = try? String(contentsOf: url, usedEncoding: &detectedEncoding) {
      return text
    }

    let data = try Data(contentsOf: url)
    for encoding in fallbackTextEncodings {
      if let text = String(data: data, encoding: encoding) {
        return text
      }
    }

    throw CocoaError(.fileReadInapplicableStringEncoding)
  }

  private var fallbackTextEncodings: [String.Encoding] {
    [
      .utf8,
      .windowsCP1252,
      .macOSRoman,
      .isoLatin1,
    ]
  }

  private func openMetadataReadRun(
    folder: ScannedShowFolder,
    files: [ScannedAudioFile],
    toolPaths: AudioToolPaths
  ) async -> RunRecord? {
    do {
      let run = try await runLogClient.open(
        RunLogOpenRequest(
          showRootPath: folder.root.path(percentEncoded: false),
          kind: .metadataRead,
          command: metadataReadCommandText(files: files, toolPaths: toolPaths)
        )
      )
      runLogErrorMessage = nil
      return run
    } catch {
      runLogErrorMessage = error.localizedDescription
      return nil
    }
  }

  private func appendMetadataReadOutcome(_ outcome: MetadataReadOutcome, to run: RunRecord?) async {
    guard let run else {
      return
    }

    do {
      _ = try await runLogClient.appendFileOutcome(
        RunLogFileOutcomeRequest(
          runID: run.id,
          sourcePath: outcome.file.url.path(percentEncoded: false),
          status: outcome.status,
          note: outcome.note
        )
      )
      runLogErrorMessage = nil
    } catch {
      runLogErrorMessage = error.localizedDescription
    }
  }

  private func closeMetadataReadRun(
    _ run: RunRecord?,
    fileCount: Int,
    failedCount: Int
  ) async {
    guard let run else {
      return
    }

    do {
      _ = try await runLogClient.close(
        RunLogCloseRequest(
          runID: run.id,
          exitSummary: metadataReadExitSummary(fileCount: fileCount, failedCount: failedCount)
        )
      )
      runLogErrorMessage = nil
    } catch {
      runLogErrorMessage = error.localizedDescription
    }
  }

  private func metadataReadOutcome(
    file: ScannedAudioFile,
    state: AudioMetadataLoadState
  ) -> MetadataReadOutcome {
    switch state {
    case .notLoaded:
      MetadataReadOutcome(file: file, status: .skipped, note: "Metadata read was cancelled.")
    case .loading:
      MetadataReadOutcome(file: file, status: .skipped, note: "Metadata read did not finish.")
    case .loaded:
      MetadataReadOutcome(file: file, status: .read, note: "Read current tags.")
    case let .failed(message):
      MetadataReadOutcome(file: file, status: .failed, note: message)
    }
  }

  private func metadataReadExitSummary(fileCount: Int, failedCount: Int) -> String {
    if failedCount == 0 {
      return "ok"
    }
    return "\(failedCount) of \(fileCount) failed"
  }

  private func metadataReadCommandText(
    files: [ScannedAudioFile],
    toolPaths: AudioToolPaths
  ) -> String {
    let commands = files.flatMap { file in
      metadataReadCommands(file: file, toolPaths: toolPaths)
    }
    guard !commands.isEmpty else {
      return "No metadata commands could be constructed; one or more tools are missing."
    }
    return commands.map(\.commandLine).joined(separator: "\n")
  }

  private func metadataReadCommands(
    file: ScannedAudioFile,
    toolPaths: AudioToolPaths
  ) -> [ScriptCommand] {
    do {
      switch file.format {
      case .flac:
        return [
          try AudioMetadataCommands.flacTagExport(url: file.url, toolPaths: toolPaths),
          try AudioMetadataCommands.flacStreamInfo(url: file.url, toolPaths: toolPaths),
          try AudioMetadataCommands.flacPictureList(url: file.url, toolPaths: toolPaths),
        ]
      case .mp3, .m4a:
        return [
          try AudioMetadataCommands.ffprobeJSON(url: file.url, toolPaths: toolPaths),
        ]
      }
    } catch {
      return []
    }
  }
}

private struct MetadataReadOutcome: Sendable {
  var file: ScannedAudioFile
  var status: RunFileOutcome.Status
  var note: String
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
  case liveShows
  case collections

  var id: Self { self }

  var title: String {
    switch self {
    case .liveShows:
      "Live Shows"
    case .collections:
      "Collections"
    }
  }

  var systemImage: String {
    switch self {
    case .liveShows:
      "music.note.list"
    case .collections:
      "rectangle.stack"
    }
  }
}
