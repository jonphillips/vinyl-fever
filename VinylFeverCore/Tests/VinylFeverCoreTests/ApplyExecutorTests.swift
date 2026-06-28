import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct ApplyExecutorTests {
  @Test
  func copiesTagsAndRecordsOutcomes() async throws {
    let fileOperations = FileOperationRecorder()
    let scripts = ApplyCommandRecorder()
    let runLog = RunLogRecorder()
    let showPlan = makeShowPlan(
      files: [
        makeAudioFile(id: UUID(1), name: "01.flac", format: .flac, sortKey: "01.flac"),
        makeAudioFile(id: UUID(2), name: "02.mp3", format: .mp3, sortKey: "02.mp3"),
      ],
      trackTitles: ["The Way It Is", "Mandolin Rain"]
    )
    let applyPlan = ApplyPlan(
      showPlan: showPlan,
      showRoot: applyShowRoot,
      coverURL: applyShowRoot.appendingPathComponent("front.jpg")
    )

    let result = try await withDependencies {
      $0.fileOperationClient.fileExists = { url in
        await fileOperations.fileExists(url)
      }
      $0.fileOperationClient.createDirectory = { url in
        await fileOperations.createDirectory(url)
      }
      $0.fileOperationClient.copyFile = { source, destination in
        await fileOperations.copyFile(source, destination)
      }
      $0.fileOperationClient.replaceFile = { source, destination in
        await fileOperations.replaceFile(source, destination)
      }
      $0.scriptClient.run = { command in
        await scripts.append(command)
        return ScriptResult(command: command, exitCode: 0, standardOutput: Data(), standardError: Data())
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await ApplyExecutor().apply(
        applyPlan,
        toolPaths: AudioToolPaths(paths: [.metaflac: "/tools/metaflac", .ffmpeg: "/tools/ffmpeg"])
      )
    }

    expectNoDifference(result.exitSummary, "ok")
    expectNoDifference(result.appliedTracks.map(\.status), [.created, .created])
    let fileOperationSnapshot = await fileOperations.snapshot()
    let scriptTools = await scripts.snapshot().map(\.tool)
    let outcomeSnapshots = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))

    expectNoDifference(
      fileOperationSnapshot,
      FileOperationRecorder.Snapshot(
        existenceChecks: [
          "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
          "/Shows/BruceHornsby/Working/02 - Mandolin Rain.mp3",
        ],
        createdDirectories: ["/Shows/BruceHornsby/Working/"],
        copies: [
          "/Shows/BruceHornsby/01.flac -> /Shows/BruceHornsby/Working/01 - The Way It Is.flac",
          "/Shows/BruceHornsby/02.mp3 -> /Shows/BruceHornsby/Working/02 - Mandolin Rain.mp3",
        ],
        replacements: [
          "/Shows/BruceHornsby/Working/02 - Mandolin Rain.mp3.tagtmp.mp3 -> /Shows/BruceHornsby/Working/02 - Mandolin Rain.mp3",
        ]
      )
    )
    expectNoDifference(scriptTools, [.metaflac, .metaflac, .metaflac, .ffmpeg])
    expectNoDifference(
      outcomeSnapshots,
      [
        RunOutcomeSnapshot(
          status: .created,
          producedPath: "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
          note: "Copied and tagged."
        ),
        RunOutcomeSnapshot(
          status: .created,
          producedPath: "/Shows/BruceHornsby/Working/02 - Mandolin Rain.mp3",
          note: "Copied and tagged."
        ),
      ]
    )
  }

  @Test
  func reportsConflictWithoutCopying() async throws {
    let fileOperations = FileOperationRecorder(existingPaths: [
      "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
    ])
    let scripts = ApplyCommandRecorder()
    let runLog = RunLogRecorder()
    let applyPlan = ApplyPlan(
      showPlan: makeShowPlan(
        files: [makeAudioFile(id: UUID(1), name: "01.flac", format: .flac, sortKey: "01.flac")],
        trackTitles: ["The Way It Is"]
      ),
      showRoot: applyShowRoot,
      coverURL: nil
    )

    let result = try await withDependencies {
      $0.fileOperationClient.fileExists = { url in
        await fileOperations.fileExists(url)
      }
      $0.fileOperationClient.createDirectory = { url in
        await fileOperations.createDirectory(url)
      }
      $0.fileOperationClient.copyFile = { source, destination in
        await fileOperations.copyFile(source, destination)
      }
      $0.scriptClient.run = { command in
        await scripts.append(command)
        return ScriptResult(command: command, exitCode: 0, standardOutput: Data(), standardError: Data())
      }
      $0.runLogClient = runLog.client
    } operation: {
      try await ApplyExecutor().apply(
        applyPlan,
        toolPaths: AudioToolPaths(paths: [.metaflac: "/tools/metaflac"])
      )
    }

    expectNoDifference(result.exitSummary, "1 conflict")
    expectNoDifference(result.appliedTracks.map(\.status), [.skipped])
    let conflictFileOperationSnapshot = await fileOperations.snapshot()
    let conflictScripts = await scripts.snapshot()
    let conflictOutcomes = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))

    expectNoDifference(conflictFileOperationSnapshot.copies, [])
    expectNoDifference(conflictScripts, [])
    expectNoDifference(
      conflictOutcomes,
      [
        RunOutcomeSnapshot(
          status: .skipped,
          producedPath: "/Shows/BruceHornsby/Working/01 - The Way It Is.flac",
          note: "Destination already exists."
        ),
      ]
    )
  }
}
