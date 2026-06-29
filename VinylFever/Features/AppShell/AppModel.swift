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
  @Dependency(\.fileOperationClient) private var fileOperationClient
  @ObservationIgnored
  @Dependency(\.toolPathClient) private var toolPathClient
  @ObservationIgnored
  @Dependency(\.audioMetadataClient) private var audioMetadataClient
  @ObservationIgnored
  @Dependency(\.runLogClient) private var runLogClient
  @ObservationIgnored
  @Dependency(\.musicAppClient) private var musicAppClient
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
  var applyState: ApplyRunState = .idle
  var conversionState: ConversionRunState = .idle
  var verificationState: VerificationRunState = .idle
  var libraryImportState: LibraryImportState = .idle
  var libraryReadState: LibraryReadState = .idle
  var lastSuccessfulApplyPlan: ApplyPlan?

  enum Destination: Hashable {
  }

  func scanShowFolder(at url: URL) {
    do {
      scannedShowFolder = try fileSystemClient.scanShowFolder(root: url)
      currentMetadataByFileID = [:]
      applyState = .idle
      conversionState = .idle
      verificationState = .idle
      libraryImportState = .idle
      libraryReadState = .idle
      lastSuccessfulApplyPlan = nil
      scanErrorMessage = nil
    } catch {
      scannedShowFolder = nil
      currentMetadataByFileID = [:]
      applyState = .idle
      conversionState = .idle
      verificationState = .idle
      libraryImportState = .idle
      libraryReadState = .idle
      lastSuccessfulApplyPlan = nil
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

  func hasRequiredApplyTools(for plan: ShowPlan?) -> Bool {
    guard let plan else {
      return false
    }
    let applyPlan = ApplyPlan(showPlan: plan, showRoot: scannedShowFolder?.root ?? URL(fileURLWithPath: "/"))
    return applyPlan.requiredTools.allSatisfy { tool in
      toolStatus(for: tool).resolvedPath != nil
    }
  }

  func hasRequiredConversionTools(for applyPlan: ApplyPlan?) -> Bool {
    guard let applyPlan else {
      return false
    }
    return ConversionPlan(applyPlan: applyPlan).requiredTools.allSatisfy { tool in
      toolStatus(for: tool).resolvedPath != nil
    }
  }

  func hasSuccessfulApply(for applyPlan: ApplyPlan) -> Bool {
    guard case let .completed(result) = applyState, result.didSucceed else {
      return false
    }
    return lastSuccessfulApplyPlan == applyPlan
  }

  func applyShowPlan(_ showPlan: ShowPlan, coverURL: URL?) async {
    guard let scannedShowFolder else {
      applyState = .failed("Open a show folder before applying.")
      return
    }

    let applyPlan = ApplyPlan(
      showPlan: showPlan,
      showRoot: scannedShowFolder.root,
      coverURL: coverURL
    )
    applyState = .running(applyPlan)
    conversionState = .idle
    verificationState = .idle
    libraryImportState = .idle
    libraryReadState = .idle
    lastSuccessfulApplyPlan = nil

    do {
      let result = try await ApplyExecutor().apply(
        applyPlan,
        toolPaths: AudioToolPaths(statuses: toolStatuses)
      )
      applyState = .completed(result)
      lastSuccessfulApplyPlan = result.didSucceed ? applyPlan : nil
      runLogErrorMessage = nil
    } catch is CancellationError {
      applyState = .idle
    } catch {
      applyState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  func convertAndVerify(_ applyPlan: ApplyPlan) async {
    guard hasSuccessfulApply(for: applyPlan) else {
      conversionState = .failed("Apply must finish successfully before conversion.")
      verificationState = .idle
      libraryImportState = .idle
      libraryReadState = .idle
      return
    }

    let conversionPlan = ConversionPlan(applyPlan: applyPlan)
    let toolPaths = AudioToolPaths(statuses: toolStatuses)
    guard conversionPlan.requiredTools.allSatisfy({ toolStatus(for: $0).resolvedPath != nil }) else {
      conversionState = .failed("Required conversion and verification tools are missing.")
      verificationState = .idle
      libraryImportState = .idle
      libraryReadState = .idle
      return
    }

    verificationState = .idle
    libraryImportState = .idle
    libraryReadState = .idle
    if conversionPlan.requiresConversion {
      conversionState = .running(conversionPlan)
      do {
        let result = try await ConversionExecutor().convert(conversionPlan, toolPaths: toolPaths)
        conversionState = .completed(result)
        runLogErrorMessage = nil
        guard result.didSucceed else {
          verificationState = .failed("Conversion did not finish cleanly.")
          libraryImportState = .idle
          libraryReadState = .idle
          return
        }
      } catch is CancellationError {
        conversionState = .idle
        libraryImportState = .idle
        libraryReadState = .idle
        return
      } catch {
        conversionState = .failed(error.localizedDescription)
        verificationState = .idle
        libraryImportState = .idle
        libraryReadState = .idle
        runLogErrorMessage = error.localizedDescription
        return
      }
    } else {
      conversionState = .skipped("No FLAC tracks; verifying Working files.")
    }

    verificationState = .running(conversionPlan)
    do {
      let result = try await VerificationExecutor().verify(conversionPlan, toolPaths: toolPaths)
      verificationState = .completed(result)
      runLogErrorMessage = nil
    } catch is CancellationError {
      verificationState = .idle
    } catch {
      verificationState = .failed(error.localizedDescription)
      libraryImportState = .idle
      libraryReadState = .idle
      runLogErrorMessage = error.localizedDescription
    }
  }

  func hasSuccessfulFileVerify(for plan: ConversionPlan) -> Bool {
    guard case let .completed(result) = verificationState, result.didVerify else {
      return false
    }
    return result.files.map(\.id) == plan.tracks.map(\.id)
  }

  func importIntoMusicLibrary(for plan: ConversionPlan) async {
    guard hasSuccessfulFileVerify(for: plan) else {
      libraryImportState = .failed("File verification must finish successfully before import.")
      libraryReadState = .idle
      return
    }

    libraryImportState = .requestingPermission
    let permission = await musicAppClient.requestAutomationPermission()
    guard permission == .authorized else {
      libraryImportState = .permission(permission)
      return
    }

    libraryImportState = .running(plan)
    libraryReadState = .idle
    do {
      let result = try await LibraryImportExecutor().importToLibrary(plan)
      libraryImportState = .completed(result)
      runLogErrorMessage = nil
    } catch is CancellationError {
      libraryImportState = .idle
    } catch {
      libraryImportState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  func readMusicLibrary(for plan: ConversionPlan) async {
    guard hasSuccessfulFileVerify(for: plan) else {
      libraryReadState = .failed("File verification must finish successfully before reading Music.")
      return
    }

    libraryReadState = .requestingPermission
    let permission = await musicAppClient.requestAutomationPermission()
    guard permission == .authorized else {
      libraryReadState = .permission(permission)
      return
    }

    libraryReadState = .running(plan)
    do {
      let libraryTracks = try await musicAppClient.readAlbumTracks(
        MusicAlbumReadRequest(albumTitle: plan.albumTitle)
      )
      libraryReadState = .completed(
        MusicLibraryMatcher.resolve(plan: plan, libraryTracks: libraryTracks)
      )
      runLogErrorMessage = nil
    } catch is CancellationError {
      libraryReadState = .idle
    } catch {
      libraryReadState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  func revealWorkingDirectory() async {
    guard let scannedShowFolder else {
      return
    }
    do {
      try await fileOperationClient.reveal(
        scannedShowFolder.root.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
      )
      runLogErrorMessage = nil
    } catch {
      runLogErrorMessage = error.localizedDescription
    }
  }

  func revealOutputDirectory() async {
    guard let scannedShowFolder else {
      return
    }
    do {
      try await fileOperationClient.reveal(
        scannedShowFolder.root.appendingPathComponent(ConversionPlan.outputDirectoryName, isDirectory: true)
      )
      runLogErrorMessage = nil
    } catch {
      runLogErrorMessage = error.localizedDescription
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
    let audioMetadataClient = self.audioMetadataClient
    var outcomes: [MetadataReadOutcome] = []
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
        outcomes.append(outcome)
      }
    }

    guard !Task.isCancelled else {
      return
    }
    guard shouldRecordMetadataReadRun(folder: scannedShowFolder, outcomes: outcomes) else {
      return
    }

    let run = await openMetadataReadRun(
      folder: scannedShowFolder,
      files: files,
      toolPaths: toolPaths
    )
    let sortedOutcomes = outcomes.sorted {
      $0.file.url.path(percentEncoded: false) < $1.file.url.path(percentEncoded: false)
    }
    for outcome in sortedOutcomes {
      await appendMetadataReadOutcome(outcome, to: run)
    }
    let failedCount = sortedOutcomes.count { $0.status == .failed }
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

  private func shouldRecordMetadataReadRun(
    folder: ScannedShowFolder,
    outcomes: [MetadataReadOutcome]
  ) -> Bool {
    do {
      let rootPath = folder.root.path(percentEncoded: false)
      let current = metadataReadSnapshots(from: outcomes)
      return try database.read { db in
        guard let previous = try RunHistory.mostRecentMetadataReadOutcomes(
          showRootPath: rootPath,
          in: db
        ) else {
          return true
        }
        return previous != current
      }
    } catch {
      runLogErrorMessage = error.localizedDescription
      return true
    }
  }

  private func metadataReadSnapshots(
    from outcomes: [MetadataReadOutcome]
  ) -> [RunFileOutcomeSummary] {
    outcomes
      .map { outcome in
        RunFileOutcomeSummary(
          sourcePath: outcome.file.url.path(percentEncoded: false),
          status: outcome.status,
          note: outcome.note
        )
      }
      .sorted { $0.sourcePath < $1.sourcePath }
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

enum ApplyRunState: Equatable {
  case idle
  case running(ApplyPlan)
  case completed(ApplyResult)
  case failed(String)

  var isRunning: Bool {
    if case .running = self {
      return true
    }
    return false
  }
}

enum ConversionRunState: Equatable {
  case idle
  case running(ConversionPlan)
  case skipped(String)
  case completed(ConversionResult)
  case failed(String)

  var isRunning: Bool {
    if case .running = self {
      return true
    }
    return false
  }
}

enum VerificationRunState: Equatable {
  case idle
  case running(ConversionPlan)
  case completed(VerificationResult)
  case failed(String)

  var isRunning: Bool {
    if case .running = self {
      return true
    }
    return false
  }
}

enum LibraryImportState: Equatable {
  case idle
  case requestingPermission
  case running(ConversionPlan)
  case permission(MusicAutomationPermission)
  case completed(ImportResult)
  case failed(String)

  var isRunning: Bool {
    switch self {
    case .requestingPermission, .running:
      true
    case .idle, .permission, .completed, .failed:
      false
    }
  }
}

enum LibraryReadState: Equatable {
  case idle
  case requestingPermission
  case running(ConversionPlan)
  case permission(MusicAutomationPermission)
  case completed(LibraryResolutionResult)
  case failed(String)

  var isRunning: Bool {
    switch self {
    case .requestingPermission, .running:
      true
    case .idle, .permission, .completed, .failed:
      false
    }
  }
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
