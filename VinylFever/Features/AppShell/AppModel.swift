import AppKit
import Dependencies
import Foundation
import LLMClientKit
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
  @ObservationIgnored
  @Dependency(\.setlistNormalizer) private var setlistNormalizer
  @ObservationIgnored
  @Dependency(\.apiKeyStore) private var apiKeyStore

  var selectedSection: AppSection = .liveShows
  var destination: Destination?
  var scannedShowFolder: ScannedShowFolder?
  var scanErrorMessage: String?
  var setlistInput = ""
  var setlistDraft: SetlistDraft?
  var setlistErrorMessage: String?
  var setlistNormalizationState: SetlistNormalizationRunState = .idle
  var frontierKeyPreview: String?
  var frontierKeyErrorMessage: String?
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
  /// True only just after a successful `cleanUpProducedFolders()`, so the completion UI
  /// swaps the "Clean Up Files" button for a done confirmation. Reset whenever a run is
  /// (re)started, since that recreates the folders.
  var didCleanUpProducedFolders = false
  var compilationSeedCandidates: [CompilationAlbumSeedCandidate] = []
  var selectedCompilationSeedCandidateIDs: Set<CompilationAlbumSeedCandidate.ID> = []
  var compilationSeedState: CollectionSeedState = .idle
  var compilationAppendFolder: URL?
  var compilationAppendFiles: [ScannedAudioFile] = []
  var compilationAppendMetadataByFileID: [ScannedAudioFile.ID: AudioMetadataLoadState] = [:]
  var compilationApplyPlan: CompilationApplyPlan?
  var compilationApplyState: ApplyRunState = .idle
  var compilationConversionState: ConversionRunState = .idle
  var compilationImportState: LibraryImportState = .idle
  var compilationCertificationState: CompilationCertificationState = .idle

  enum Destination: Hashable {
  }

  func scanShowFolder(at url: URL) {
    didCleanUpProducedFolders = false
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

  // MARK: - Pipeline stage rollup (derived — drives the M6 pipeline strip)

  /// Coarse "where am I" over the five independent run states, most-advanced wins.
  /// Derived, never stored. A run only counts toward its stage once it has *succeeded*
  /// (a failed apply stays at `.planned`, a failed import at `.verified`, …) so the
  /// strip never reads green while the underlying step actually failed.
  enum PipelineStage: Int, Comparable {
    case setup, planned, applied, verified, imported, resolved

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  var pipelineStage: PipelineStage {
    if case let .completed(result) = libraryReadState, result.didResolveAll {
      return .resolved
    }
    if case let .completed(result) = libraryImportState, result.didSucceed {
      return .imported
    }
    if case let .completed(result) = verificationState, result.didVerify {
      return .verified
    }
    if case let .completed(result) = applyState, result.didSucceed {
      return .applied
    }
    if setlistDraft != nil {
      return .planned
    }
    return .setup
  }

  /// Terminal state: the produced files are all resolved back in the Music library.
  var isShowComplete: Bool { pipelineStage == .resolved }

  /// Whether any live-show pipeline step is mid-run. Drives the sidebar spinner so the
  /// slower steps (Import into Music, Read Music) show activity even when the user has
  /// navigated away from the Output tab.
  var isLiveShowRunActive: Bool {
    applyState.isRunning
      || conversionState.isRunning
      || verificationState.isRunning
      || libraryImportState.isRunning
      || libraryReadState.isRunning
  }

  /// The resolved library read, when the show has reached its terminal state. Drives the
  /// completion pill's `resolved n/n` copy; `nil` until every produced file resolves.
  var completedLibraryResolution: LibraryResolutionResult? {
    guard case let .completed(result) = libraryReadState, result.didResolveAll else {
      return nil
    }
    return result
  }

  /// Reset just the pipeline run states (apply → resolve) plus the remembered apply plan,
  /// leaving the scanned folder and parsed setlist intact so a plan can be re-run.
  func resetPlanRun() {
    applyState = .idle
    conversionState = .idle
    verificationState = .idle
    libraryImportState = .idle
    libraryReadState = .idle
    lastSuccessfulApplyPlan = nil
    didCleanUpProducedFolders = false
  }

  /// Terminal "Done": drop the scanned show so `LiveShowsView` falls back to its empty
  /// state. Clears the folder, the raw + parsed setlist, per-file metadata, and every
  /// run state. (No persistent imported-show list — that's out of scope for M6.)
  func clearScannedShow() {
    scannedShowFolder = nil
    scanErrorMessage = nil
    setlistInput = ""
    setlistDraft = nil
    setlistErrorMessage = nil
    currentMetadataByFileID = [:]
    resetPlanRun()
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
    let draft = SetlistParser().parse(setlistInput)
    setlistDraft = draft
    setlistErrorMessage = nil
    syncSelectedSourceLabel(to: draft.tags.source)
  }

  /// Point the header Source picker at the source the parser/Normalizer inferred, so a
  /// show that already names its source (`… (FM)`) shows it without a manual pick. Only
  /// matches the built-in vocabulary; a custom inferred token still drives the album
  /// title via `ShowMetadata`'s fallback but leaves the picker on its current value.
  private func syncSelectedSourceLabel(to source: Field) {
    let key = SourceLabel.normalizedToken(source.text).lowercased()
    guard !key.isEmpty else { return }
    guard let match = SourceLabel.builtIns.first(where: { $0.normalizedTokenKey == key })
    else { return }
    selectedSourceLabelID = match.id
  }

  // MARK: - Setlist Normalizer (raw notes → setlist.txt)

  /// Whether a frontier key is configured. Derived from `frontierKeyPreview`, which is
  /// observable stored state (not a live Keychain read) so the UI actually re-renders
  /// when a key is saved or cleared.
  var isFrontierConfigured: Bool { frontierKeyPreview != nil }

  /// Refresh the masked preview from the store. Call when a settings/normalizer surface
  /// appears so the observed state reflects what's actually in the Keychain.
  func loadFrontierKeyPreview() {
    frontierKeyPreview = apiKeyStore.maskedKey(.anthropic)
  }

  func saveFrontierKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    apiKeyStore.setKey(trimmed, for: .anthropic)
    // Read back so a silently-failed Keychain write (e.g. a missing entitlement — the
    // store swallows the OSStatus) surfaces instead of looking like a no-op save.
    frontierKeyPreview = apiKeyStore.maskedKey(.anthropic)
    frontierKeyErrorMessage =
      frontierKeyPreview == nil
      ? "The key didn’t persist to the Keychain. Check the app’s keychain entitlement."
      : nil
  }

  func clearFrontierKey() {
    apiKeyStore.setKey(nil, for: .anthropic)
    frontierKeyPreview = apiKeyStore.maskedKey(.anthropic)
    frontierKeyErrorMessage = nil
  }

  /// Run the sandwich over the raw notes in `setlistInput`. Never writes — it produces
  /// a result the preview gate renders; the human approves before anything lands.
  func normalizeSetlistInput() async {
    let rawInput = setlistInput
    guard !rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      setlistNormalizationState = .failed("Paste or load raw notes before normalizing.")
      return
    }

    setlistNormalizationState = .running
    do {
      let result = try await setlistNormalizer.normalize(rawInput)
      setlistNormalizationState = .completed(result)
    } catch is CancellationError {
      setlistNormalizationState = .idle
    } catch {
      setlistNormalizationState = .failed(error.localizedDescription)
    }
  }

  /// Write the approved, rendered `setlist.txt`. The single write in the flow — only
  /// reachable from the preview's explicit Save.
  func writeNormalizedSetlist(_ result: SetlistNormalizationResult, to url: URL) async {
    do {
      try await fileOperationClient.writeData(Data(result.renderedText.utf8), url)
      // Fold the approved result into the parsed-setlist surface so the rest of the
      // live-show flow can pick it up.
      setlistInput = result.renderedText
      setlistDraft = result.draft
      syncSelectedSourceLabel(to: result.draft.tags.source)
      setlistNormalizationState = .saved(url)
      runLogErrorMessage = nil
    } catch {
      setlistNormalizationState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
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

  /// Delete the derived `Working/` and `Output/` folders once the show is fully
  /// resolved in Music. Gated on `isShowComplete` so the on-disk copies are only removed
  /// after Music holds the tracks — the source audio and setlist at the root are left
  /// untouched. `removeItem` is recursive and a no-op on a missing path, so an absent
  /// `Output/` (no conversion) is fine.
  func cleanUpProducedFolders() async {
    guard let scannedShowFolder, isShowComplete else {
      return
    }
    let root = scannedShowFolder.root
    do {
      try await fileOperationClient.removeItem(
        root.appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
      )
      try await fileOperationClient.removeItem(
        root.appendingPathComponent(ConversionPlan.outputDirectoryName, isDirectory: true)
      )
      didCleanUpProducedFolders = true
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

  func seedCompilationAlbums(from url: URL) async {
    compilationSeedState = .running(CompilationSeedProgress(url: url, completed: 0, total: 0))
    do {
      let candidates = try await CompilationAlbumSeeder().candidates(
        from: url,
        toolPaths: AudioToolPaths(statuses: toolStatuses)
      ) { [weak self] completed, total in
        await MainActor.run {
          guard let self, case .running = self.compilationSeedState else {
            return
          }
          self.compilationSeedState = .running(
            CompilationSeedProgress(url: url, completed: completed, total: total)
          )
        }
      }
      compilationSeedCandidates = candidates
      selectedCompilationSeedCandidateIDs = Set(candidates.map(\.id))
      compilationSeedState = .completed(candidates)
      runLogErrorMessage = nil
    } catch is CancellationError {
      compilationSeedState = .idle
    } catch {
      compilationSeedCandidates = []
      selectedCompilationSeedCandidateIDs = []
      compilationSeedState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  func persistSelectedCompilationSeedCandidates() {
    let albums = compilationSeedCandidates
      .filter { selectedCompilationSeedCandidateIDs.contains($0.id) }
      .map(\.album)
    guard !albums.isEmpty else {
      compilationSeedState = .failed("Select at least one album to save.")
      return
    }

    do {
      try database.write { db in
        try CompilationAlbumRegistry.upsert(albums, in: db)
      }
      compilationSeedState = .saved(albums.count)
      runLogErrorMessage = nil
    } catch {
      compilationSeedState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  /// Sets a curated cover for a registry album from a picked image file. The
  /// uploaded image becomes both the registry tile (`displayImage`) and the
  /// artwork stamped onto appended tracks (`fallbackArtwork`) — see
  /// docs/album-cover-upload.md for why both fields update.
  func setCompilationAlbumCover(album: CompilationAlbum, imageURL: URL) async {
    do {
      let data = try Data(contentsOf: imageURL)
      guard let normalized = Self.normalizedCoverData(data) else {
        runLogErrorMessage = "That file isn't a readable image."
        return
      }
      var updated = album
      updated.displayImage = normalized
      updated.fallbackArtwork = normalized
      let record = updated
      try await database.write { db in
        try CompilationAlbum.upsert { record }.execute(db)
      }
      runLogErrorMessage = nil
    } catch {
      runLogErrorMessage = error.localizedDescription
    }
  }

  func buildCompilationAppendPlan(entry: CompilationAlbum, sourceFolder: URL) async {
    compilationAppendFolder = sourceFolder
    compilationApplyPlan = nil
    compilationApplyState = .idle
    compilationConversionState = .idle
    compilationImportState = .idle
    compilationCertificationState = .idle
    do {
      let files = try fileSystemClient.scanAudioFolder(sourceFolder)
      compilationAppendFiles = files
      compilationAppendMetadataByFileID = Dictionary(
        uniqueKeysWithValues: files.map { ($0.id, .loading) }
      )
      let toolPaths = AudioToolPaths(statuses: toolStatuses)
      var currentTagsByFileID: [ScannedAudioFile.ID: AudioTags] = [:]
      for file in files {
        do {
          let tags = try await audioMetadataClient.read(
            AudioMetadataRequest(file: file, toolPaths: toolPaths)
          )
          currentTagsByFileID[file.id] = tags
          compilationAppendMetadataByFileID[file.id] = .loaded(tags)
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          compilationAppendMetadataByFileID[file.id] = .failed(error.localizedDescription)
        }
      }
      let fallbackArtworkURL =
        if let fallbackArtwork = entry.fallbackArtwork {
          sourceFolder
            .appendingPathComponent(ApplyPlan.workingDirectoryName, isDirectory: true)
            .appendingPathComponent("compilation-fallback-artwork.\(imageFileExtension(for: fallbackArtwork))")
        } else {
          URL?.none
        }
      compilationApplyPlan = CompilationApplyPlan(
        entry: entry,
        sourceRoot: sourceFolder,
        files: files,
        currentTagsByFileID: currentTagsByFileID,
        fallbackArtworkURL: fallbackArtworkURL
      )
      runLogErrorMessage = nil
    } catch is CancellationError {
      compilationApplyPlan = nil
    } catch {
      compilationApplyPlan = nil
      compilationApplyState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  func applyCompilationPlan(_ plan: CompilationApplyPlan) async {
    let applyPlan = ApplyPlan(compilationPlan: plan)
    compilationApplyState = .running(applyPlan)
    compilationConversionState = .idle
    compilationImportState = .idle
    compilationCertificationState = .idle

    do {
      if let artwork = plan.entry.fallbackArtwork,
        plan.tracks.contains(where: { $0.artwork == .applyFallback }),
        let fallbackArtworkURL = plan.tracks.first(where: { $0.fallbackArtworkURL != nil })?.fallbackArtworkURL
      {
        try await fileOperationClient.createDirectory(plan.workingDirectory)
        try await fileOperationClient.writeData(artwork, fallbackArtworkURL)
      }
      let result = try await ApplyExecutor().apply(
        applyPlan,
        toolPaths: AudioToolPaths(statuses: toolStatuses)
      )
      compilationApplyState = .completed(result)
      runLogErrorMessage = nil
      guard result.didSucceed else {
        return
      }
      await appendCompilationToMusic(plan, applyPlan: applyPlan)
    } catch is CancellationError {
      compilationApplyState = .idle
      compilationConversionState = .idle
      compilationImportState = .idle
      compilationCertificationState = .idle
    } catch {
      compilationApplyState = .failed(error.localizedDescription)
      compilationConversionState = .idle
      compilationImportState = .idle
      compilationCertificationState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  private func appendCompilationToMusic(_ plan: CompilationApplyPlan, applyPlan: ApplyPlan) async {
    let conversionPlan = ConversionPlan(applyPlan: applyPlan)
    let toolPaths = AudioToolPaths(statuses: toolStatuses)
    guard conversionPlan.requiredTools.allSatisfy({ toolStatus(for: $0).resolvedPath != nil }) else {
      compilationConversionState = .failed("Required conversion and verification tools are missing.")
      compilationCertificationState = .failed("Required conversion and verification tools are missing.")
      return
    }

    if conversionPlan.requiresConversion {
      compilationConversionState = .running(conversionPlan)
      do {
        let result = try await ConversionExecutor().convert(conversionPlan, toolPaths: toolPaths)
        compilationConversionState = .completed(result)
        guard result.didSucceed else {
          compilationCertificationState = .failed("Conversion did not finish cleanly.")
          return
        }
      } catch is CancellationError {
        compilationConversionState = .idle
        compilationImportState = .idle
        compilationCertificationState = .idle
        return
      } catch {
        compilationConversionState = .failed(error.localizedDescription)
        compilationCertificationState = .failed(error.localizedDescription)
        runLogErrorMessage = error.localizedDescription
        return
      }
    } else {
      compilationConversionState = .skipped("No FLAC tracks; importing Working files.")
    }

    compilationImportState = .requestingPermission
    let permission = await musicAppClient.requestAutomationPermission()
    guard permission == .authorized else {
      compilationImportState = .permission(permission)
      compilationCertificationState = .failed(permission.displayMessage)
      return
    }

    compilationImportState = .running(conversionPlan)
    compilationCertificationState = .running(plan.entry.identity)

    do {
      let request = MusicAlbumReadRequest(identity: plan.entry.identity, includesTitleSiblings: true)
      let preImportTracks = try await musicAppClient.readAlbumTracks(request)
      let importResult = try await importCompilationFiles(conversionPlan)
      compilationImportState = .completed(importResult)
      let postImportTracks = try await musicAppClient.readAlbumTracks(request)
      let verdict = AppendCertificationComparator.verdict(
        identity: plan.entry.identity,
        preImportTracks: preImportTracks,
        postImportTracks: postImportTracks,
        addedTrackCount: importResult.importedCount
      )
      let certification = try await recordCompilationCertification(
        plan: plan,
        preImportTracks: preImportTracks,
        postImportTracks: postImportTracks,
        addedTrackCount: importResult.importedCount,
        verdict: verdict
      )
      compilationCertificationState = .completed(certification)
      runLogErrorMessage = nil
      // A clean append consumes the Working copies, so the Append Preview is now
      // stale. Clear it (and the chosen folder) so the section resets instead of
      // lingering after the job is done.
      compilationApplyPlan = nil
      compilationAppendFolder = nil
    } catch is CancellationError {
      compilationImportState = .idle
      compilationCertificationState = .idle
    } catch {
      compilationImportState = .failed(error.localizedDescription)
      compilationCertificationState = .failed(error.localizedDescription)
      runLogErrorMessage = error.localizedDescription
    }
  }

  private func importCompilationFiles(_ plan: ConversionPlan) async throws -> ImportResult {
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.showRoot.path(percentEncoded: false),
        kind: .importLibrary,
        command: compilationImportCommandText(for: plan)
      )
    )

    do {
      let producedFiles = plan.tracks.map(\.verificationFile)
      let refs = try await musicAppClient.add(producedFiles)
      let importedTracks = CompilationImportReducer.importedTracks(
        plan: plan,
        addedRefs: refs
      )
      for track in importedTracks {
        _ = try await runLogClient.appendFileOutcome(
          RunLogFileOutcomeRequest(
            runID: run.id,
            sourcePath: track.sourceURL.path(percentEncoded: false),
            producedPath: track.libraryRef?.locationPath,
            status: track.runOutcomeStatus,
            note: track.note
          )
        )
      }
      let exitSummary = compilationImportExitSummary(for: importedTracks)
      let closedRun = try await runLogClient.close(
        RunLogCloseRequest(runID: run.id, exitSummary: exitSummary)
      )
      return ImportResult(run: closedRun, tracks: importedTracks, exitSummary: exitSummary)
    } catch {
      _ = try? await runLogClient.close(
        RunLogCloseRequest(runID: run.id, exitSummary: error.localizedDescription)
      )
      throw error
    }
  }

  private func compilationImportExitSummary(for tracks: [ImportedTrack]) -> String {
    if tracks.isEmpty {
      return "no files"
    }
    let importedCount = tracks.count { $0.status == .imported }
    let alreadyPresentCount = tracks.count { $0.status == .alreadyPresent }
    switch (importedCount, alreadyPresentCount) {
    case (0, _):
      return "already present"
    case (_, 0):
      return "imported"
    default:
      return "\(importedCount) imported, \(alreadyPresentCount) already present"
    }
  }

  private func recordCompilationCertification(
    plan: CompilationApplyPlan,
    preImportTracks: [ImportedTrackRef],
    postImportTracks: [ImportedTrackRef],
    addedTrackCount: Int,
    verdict: AppendVerdict
  ) async throws -> AppendCertification {
    let identity = plan.entry.identity
    let run = try await runLogClient.open(
      RunLogOpenRequest(
        showRootPath: plan.sourceRoot.path(percentEncoded: false),
        kind: .compilationCertify,
        command: compilationCertificationCommandText(identity: identity, addedTrackCount: addedTrackCount)
      )
    )
    let preCount = AppendCertificationComparator.exactMatches(identity: identity, in: preImportTracks).count
    let postCount = AppendCertificationComparator.exactMatches(identity: identity, in: postImportTracks).count
    _ = try await runLogClient.appendFileOutcome(
      RunLogFileOutcomeRequest(
        runID: run.id,
        sourcePath: plan.sourceRoot.path(percentEncoded: false),
        status: verdict.isCertified ? .created : .failed,
        note: verdict.displayMessage
      )
    )
    let closedRun = try await runLogClient.close(
      RunLogCloseRequest(runID: run.id, exitSummary: verdict.displayMessage)
    )
    return AppendCertification(
      run: closedRun,
      identity: identity,
      addedTrackCount: addedTrackCount,
      preImportTrackCount: preCount,
      postImportTrackCount: postCount,
      verdict: verdict
    )
  }

  private func compilationImportCommandText(for plan: ConversionPlan) -> String {
    plan.tracks
      .map { "add \($0.verificationFile.path(percentEncoded: false))" }
      .joined(separator: "\n")
  }

  private func compilationCertificationCommandText(
    identity: AlbumIdentity,
    addedTrackCount: Int
  ) -> String {
    """
    read Music album "\(identity.album)" / "\(identity.albumArtist)"
    certify added track count \(addedTrackCount)
    """
  }

  private func imageFileExtension(for data: Data) -> String {
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
      return "png"
    }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
      return "jpg"
    }
    if data.starts(with: [0x47, 0x49, 0x46]) {
      return "gif"
    }
    return "img"
  }

  /// Validates that `data` decodes as an image, then re-encodes it as JPEG
  /// (quality 0.9) with the longest edge capped at ~1000px so covers stay small
  /// as inline SQLite BLOBs. Returns `nil` for anything that isn't a readable
  /// image.
  private static func normalizedCoverData(_ data: Data) -> Data? {
    guard let image = NSImage(data: data) else {
      return nil
    }
    return jpegData(from: image, longestEdge: 1000, quality: 0.9)
  }

  /// Draws `image` into an RGBA bitmap rep sized so its longest edge is at most
  /// `longestEdge` (never upscaling), then encodes it as JPEG. Going through
  /// `NSBitmapImageRep` gives a predictable, resolution-independent result;
  /// `NSImage` has no built-in JPEG or downscale.
  private static func jpegData(from image: NSImage, longestEdge: CGFloat, quality: CGFloat) -> Data? {
    let sourceSize = image.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      return nil
    }
    let scale = min(1, longestEdge / max(sourceSize.width, sourceSize.height))
    let targetWidth = Int((sourceSize.width * scale).rounded())
    let targetHeight = Int((sourceSize.height * scale).rounded())
    guard targetWidth > 0, targetHeight > 0 else {
      return nil
    }
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: targetWidth,
      pixelsHigh: targetHeight,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }
    rep.size = NSSize(width: targetWidth, height: targetHeight)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
      return nil
    }
    NSGraphicsContext.current = context
    image.draw(
      in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
      from: .zero,
      operation: .copy,
      fraction: 1
    )
    context.flushGraphics()
    return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
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

enum SetlistNormalizationRunState: Equatable {
  case idle
  case running
  case completed(SetlistNormalizationResult)
  case saved(URL)
  case failed(String)

  var isRunning: Bool {
    if case .running = self {
      return true
    }
    return false
  }

  var result: SetlistNormalizationResult? {
    switch self {
    case let .completed(result):
      result
    default:
      nil
    }
  }
}

enum CollectionSeedState: Equatable {
  case idle
  case running(CompilationSeedProgress)
  case completed([CompilationAlbumSeedCandidate])
  case saved(Int)
  case failed(String)
}

struct CompilationSeedProgress: Equatable {
  var url: URL
  var completed: Int
  var total: Int
}

enum CompilationCertificationState: Equatable {
  case idle
  case running(AlbumIdentity)
  case completed(AppendCertification)
  case failed(String)

  var isRunning: Bool {
    if case .running = self {
      return true
    }
    return false
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
