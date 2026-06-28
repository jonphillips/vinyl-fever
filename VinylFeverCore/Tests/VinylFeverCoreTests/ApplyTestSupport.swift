import Foundation
@testable import VinylFeverCore

let applyShowRoot = URL(fileURLWithPath: "/Shows/BruceHornsby")

let standardShowTags = ShowTags(
  artist: .value("Bruce Hornsby and The Range"),
  albumArtist: .value("Bruce Hornsby"),
  date: .iso(year: 1996, month: 5, day: 21),
  venue: .value("Pearl Street Grill"),
  location: .value("Northampton, MA")
)

func makeShowPlan(files: [ScannedAudioFile], trackTitles: [String]) -> ShowPlan {
  ShowPlan(
    folder: ScannedShowFolder(
      root: applyShowRoot,
      audioFiles: files,
      setlistCandidates: [],
      coverCandidates: []
    ),
    setlist: SetlistDraft(
      tags: standardShowTags,
      tracks: trackTitles.enumerated().map { index, title in
        SetlistTrack(id: UUID(index + 101), title: title)
      }
    ),
    metadata: ShowMetadata(
      tags: standardShowTags,
      source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true)
    )
  )
}

func makeAudioFile(
  id: UUID,
  name: String,
  format: AudioFormat,
  sortKey: String
) -> ScannedAudioFile {
  ScannedAudioFile(
    id: id,
    url: applyShowRoot.appendingPathComponent(name),
    format: format,
    sortKey: sortKey
  )
}

func makeApplyTrack(format: AudioFormat, coverURL: URL?) -> ApplyTrackPlan {
  ApplyTrackPlan(
    id: UUID(1),
    sourceFile: makeAudioFile(
      id: UUID(1),
      name: "01.\(format.rawValue)",
      format: format,
      sortKey: "01.\(format.rawValue)"
    ),
    workingFile: applyShowRoot
      .appendingPathComponent("Working", isDirectory: true)
      .appendingPathComponent("01 - The Way It Is.\(format.rawValue)"),
    tags: ProposedTags(
      title: "The Way It Is",
      album: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
      sortAlbum: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
      artist: "Bruce Hornsby and The Range",
      albumArtist: "Bruce Hornsby",
      trackNumber: 1,
      discNumber: 1
    ),
    trackTotal: 2,
    coverURL: coverURL
  )
}

enum ApplyOperationSnapshot: Equatable {
  case copy(source: String, destination: String)
  case writeTags(
    file: String,
    format: AudioFormat,
    title: String,
    trackNumber: Int,
    trackTotal: Int,
    cover: String?
  )

  init(operation: FileOperation) {
    switch operation {
    case let .copy(source, destination):
      self = .copy(
        source: source.path(percentEncoded: false),
        destination: destination.path(percentEncoded: false)
      )
    case let .writeTags(track):
      self = .writeTags(
        file: track.workingFile.path(percentEncoded: false),
        format: track.sourceFile.format,
        title: track.tags.title,
        trackNumber: track.tags.trackNumber,
        trackTotal: track.trackTotal,
        cover: track.coverURL?.path(percentEncoded: false)
      )
    }
  }
}

actor FileOperationRecorder {
  struct Snapshot: Equatable {
    var existenceChecks: [String] = []
    var createdDirectories: [String] = []
    var copies: [String] = []
    var replacements: [String] = []
  }

  private var existingPaths: Set<String>
  private var state = Snapshot()

  init(existingPaths: Set<String> = []) {
    self.existingPaths = existingPaths
  }

  func fileExists(_ url: URL) -> Bool {
    let path = url.path(percentEncoded: false)
    state.existenceChecks.append(path)
    return existingPaths.contains(path)
  }

  func createDirectory(_ url: URL) {
    state.createdDirectories.append(url.path(percentEncoded: false))
  }

  func copyFile(_ source: URL, _ destination: URL) {
    state.copies.append(
      "\(source.path(percentEncoded: false)) -> \(destination.path(percentEncoded: false))"
    )
  }

  func replaceFile(_ source: URL, _ destination: URL) {
    state.replacements.append(
      "\(source.path(percentEncoded: false)) -> \(destination.path(percentEncoded: false))"
    )
  }

  func snapshot() -> Snapshot {
    state
  }
}

struct RunOutcomeSnapshot: Equatable {
  var status: RunFileOutcome.Status
  var producedPath: String?
  var note: String

  init(status: RunFileOutcome.Status, producedPath: String?, note: String) {
    self.status = status
    self.producedPath = producedPath
    self.note = note
  }

  init(request: RunLogFileOutcomeRequest) {
    status = request.status
    producedPath = request.producedPath
    note = request.note
  }
}

actor ApplyCommandRecorder {
  private var commands: [ScriptCommand] = []

  func append(_ command: ScriptCommand) {
    commands.append(command)
  }

  func snapshot() -> [ScriptCommand] {
    commands
  }
}

actor RunLogRecorder {
  private let run = RunRecord(
    id: UUID(999),
    showRootPath: "/Shows/BruceHornsby",
    kind: .apply,
    startedAt: Date(timeIntervalSince1970: 1_000),
    command: ""
  )
  private var outcomes: [RunLogFileOutcomeRequest] = []

  nonisolated var client: RunLogClient {
    RunLogClient(
      open: { _ in
        await self.open()
      },
      appendFileOutcome: { request in
        await self.appendFileOutcome(request)
      },
      close: { request in
        await self.close(request)
      }
    )
  }

  func fileOutcomes() -> [RunLogFileOutcomeRequest] {
    outcomes
  }

  private func open() -> RunRecord {
    run
  }

  private func appendFileOutcome(_ request: RunLogFileOutcomeRequest) -> RunFileOutcome {
    outcomes.append(request)
    return RunFileOutcome(
      id: UUID(outcomes.count),
      runID: request.runID,
      sourcePath: request.sourcePath,
      producedPath: request.producedPath,
      status: request.status,
      note: request.note
    )
  }

  private func close(_ request: RunLogCloseRequest) -> RunRecord {
    var closedRun = run
    closedRun.finishedAt = Date(timeIntervalSince1970: 1_001)
    closedRun.exitSummary = request.exitSummary
    return closedRun
  }
}

struct ProcessOutput {
  var exitCode: Int32
  var standardOutput: Data
  var standardError: Data
}

func firstExecutable(named name: String) -> URL? {
  let candidates = [
    "/opt/homebrew/bin/\(name)",
    "/usr/local/bin/\(name)",
  ]
  .map(URL.init(fileURLWithPath:))

  return candidates.first {
    FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false))
  }
}

func temporaryDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

func runProcess(executableURL: URL, arguments: [String]) throws -> ProcessOutput {
  let process = Process()
  process.executableURL = executableURL
  process.arguments = arguments

  let standardOutput = Pipe()
  let standardError = Pipe()
  process.standardOutput = standardOutput
  process.standardError = standardError

  try process.run()
  process.waitUntilExit()
  let output = ProcessOutput(
    exitCode: process.terminationStatus,
    standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
    standardError: standardError.fileHandleForReading.readDataToEndOfFile()
  )
  guard output.exitCode == 0 else {
    let detail = String(data: output.standardError, encoding: .utf8) ?? ""
    throw ProcessTestError(
      executableName: executableURL.lastPathComponent,
      exitCode: output.exitCode,
      detail: detail
    )
  }
  return output
}

struct ProcessTestError: LocalizedError {
  var executableName: String
  var exitCode: Int32
  var detail: String

  var errorDescription: String? {
    "\(executableName) exited \(exitCode): \(detail)"
  }
}
