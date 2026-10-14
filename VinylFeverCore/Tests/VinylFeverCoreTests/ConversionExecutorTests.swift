import CustomDump
import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct ConversionExecutorTests {
  @Test
  func convertsFLACAndRecordsOutcomes() async throws {
    let fileOperations = FileOperationRecorder()
    let scripts = ApplyCommandRecorder()
    let runLog = RunLogRecorder()
    let plan = makeConversionPlan(format: .flac)

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
      try await ConversionExecutor().convert(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
      )
    }

    expectNoDifference(result.run.kind, .convert)
    expectNoDifference(result.exitSummary, "ok")
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.convertedTracks.map(\.status), [.created])
    let fileOperationSnapshot = await fileOperations.snapshot()
    let scriptSnapshot = await scripts.snapshot()
    let outcomeSnapshots = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))

    expectNoDifference(
      fileOperationSnapshot,
      FileOperationRecorder.Snapshot(
        existenceChecks: ["/Shows/BruceHornsby/Output/01 - The Way It Is.m4a"],
        createdDirectories: ["/Shows/BruceHornsby/Output/"],
        copies: [],
        replacements: []
      )
    )
    expectNoDifference(scriptSnapshot.map(\.tool), [.ffmpeg])
    expectNoDifference(
      outcomeSnapshots,
      [
        RunOutcomeSnapshot(
          status: .created,
          producedPath: "/Shows/BruceHornsby/Output/01 - The Way It Is.m4a",
          note: "Converted to ALAC."
        ),
      ]
    )
  }

  @Test
  func reportsOutputConflictWithoutConverting() async throws {
    let fileOperations = FileOperationRecorder(existingPaths: [
      "/Shows/BruceHornsby/Output/01 - The Way It Is.m4a",
    ])
    let scripts = ApplyCommandRecorder()
    let plan = makeConversionPlan(format: .flac)

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
      $0.runLogClient = RunLogRecorder().client
    } operation: {
      try await ConversionExecutor().convert(
        plan,
        toolPaths: AudioToolPaths(paths: [.ffmpeg: "/tools/ffmpeg"])
      )
    }

    expectNoDifference(result.exitSummary, "1 conflict")
    expectNoDifference(result.didSucceed, false)
    expectNoDifference(result.convertedTracks.map(\.status), [.skipped])
    let fileOperationSnapshot = await fileOperations.snapshot()
    let scriptSnapshot = await scripts.snapshot()
    expectNoDifference(fileOperationSnapshot.createdDirectories, [])
    expectNoDifference(scriptSnapshot, [])
  }

  @Test
  func copiesPassthroughMP3IntoOutputWithoutEncoding() async throws {
    let fileOperations = FileOperationRecorder()
    let scripts = ApplyCommandRecorder()
    let runLog = RunLogRecorder()
    let plan = makeConversionPlan(format: .mp3)
    let m4aPlan = makeConversionPlan(format: .m4a)

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
      try await ConversionExecutor().convert(plan, toolPaths: AudioToolPaths(paths: [:]))
    }

    expectNoDifference(plan.requiresConversion, false)
    expectNoDifference(plan.tracks[0].outputFile.path(percentEncoded: false), "/Shows/BruceHornsby/Output/01 - The Way It Is.mp3")
    expectNoDifference(plan.tracks[0].verificationFile, plan.tracks[0].outputFile)
    expectNoDifference(m4aPlan.tracks[0].action, .copyToOutput)
    expectNoDifference(m4aPlan.tracks[0].outputFile.path(percentEncoded: false), "/Shows/BruceHornsby/Output/01 - The Way It Is.m4a")
    expectNoDifference(m4aPlan.tracks[0].verificationFile, m4aPlan.tracks[0].outputFile)
    expectNoDifference(result.didSucceed, true)
    expectNoDifference(result.convertedTracks.map(\.outputURL), [plan.tracks[0].outputFile])
    expectNoDifference(result.convertedTracks.map(\.note), ["Copied to Output."])
    let fileOperationSnapshot = await fileOperations.snapshot()
    let scriptSnapshot = await scripts.snapshot()
    let outcomeSnapshots = await runLog.fileOutcomes().map(RunOutcomeSnapshot.init(request:))

    expectNoDifference(
      fileOperationSnapshot,
      FileOperationRecorder.Snapshot(
        existenceChecks: ["/Shows/BruceHornsby/Output/01 - The Way It Is.mp3"],
        createdDirectories: ["/Shows/BruceHornsby/Output/"],
        copies: ["/Shows/BruceHornsby/Working/01 - The Way It Is.mp3 -> /Shows/BruceHornsby/Output/01 - The Way It Is.mp3"],
        replacements: []
      )
    )
    expectNoDifference(scriptSnapshot, [])
    expectNoDifference(
      outcomeSnapshots,
      [
        RunOutcomeSnapshot(
          status: .created,
          producedPath: "/Shows/BruceHornsby/Output/01 - The Way It Is.mp3",
          note: "Copied to Output."
        ),
      ]
    )
  }
}
