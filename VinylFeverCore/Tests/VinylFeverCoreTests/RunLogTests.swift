import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct RunLogTests {
  @Test
  func openAppendCloseRoundTrips() async throws {
    let database = try VinylFeverDatabase.open(path: temporaryDatabasePath())
    let now = Date(timeIntervalSince1970: 1_234)

    let (closedRun, outcomes) = try await withDependencies {
      $0.defaultDatabase = database
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      let client = RunLogClient.liveValue
      let run = try await client.open(
        RunLogOpenRequest(
          showRootPath: "/Shows/Bruce Hornsby/1996-05-21",
          kind: .metadataRead,
          command: "/tools/metaflac --export-tags-to=- 01.flac"
        )
      )
      let firstOutcome = try await client.appendFileOutcome(
        RunLogFileOutcomeRequest(
          runID: run.id,
          sourcePath: "/Shows/Bruce Hornsby/1996-05-21/01.flac",
          status: .read,
          note: "Read current tags."
        )
      )
      let secondOutcome = try await client.appendFileOutcome(
        RunLogFileOutcomeRequest(
          runID: run.id,
          sourcePath: "/Shows/Bruce Hornsby/1996-05-21/02.flac",
          status: .failed,
          note: "metaflac exited 1."
        )
      )
      let closedRun = try await client.close(
        RunLogCloseRequest(runID: run.id, exitSummary: "1 of 2 failed")
      )
      return (closedRun, [firstOutcome, secondOutcome])
    }

    let entries = try await database.read { db in
      try RunHistory.entries(in: db)
    }

    expectNoDifference(
      entries,
      [
        RunHistoryEntry(
          run: closedRun,
          fileOutcomes: outcomes
        ),
      ]
    )
    expectNoDifference(closedRun.startedAt, now)
    expectNoDifference(closedRun.finishedAt, now)
    expectNoDifference(closedRun.exitSummary, "1 of 2 failed")
  }

  @Test
  func historyRequestReturnsNewestRunsFirstWithChildOutcomes() throws {
    let database = try VinylFeverDatabase.open(path: temporaryDatabasePath())
    let olderRun = RunRecord(
      id: UUID(1),
      showRootPath: "/Shows/Older",
      kind: .apply,
      startedAt: Date(timeIntervalSince1970: 100),
      finishedAt: Date(timeIntervalSince1970: 110),
      command: "older command",
      exitSummary: "ok"
    )
    let newerRun = RunRecord(
      id: UUID(2),
      showRootPath: "/Shows/Newer",
      kind: .metadataRead,
      startedAt: Date(timeIntervalSince1970: 200),
      finishedAt: Date(timeIntervalSince1970: 210),
      command: "newer command",
      exitSummary: "ok"
    )
    let newerOutcome = RunFileOutcome(
      id: UUID(3),
      runID: newerRun.id,
      sourcePath: "/Shows/Newer/01.flac",
      status: .read,
      note: "Read current tags."
    )

    try database.write { db in
      try RunRecord.upsert { olderRun }.execute(db)
      try RunRecord.upsert { newerRun }.execute(db)
      try RunFileOutcome.upsert { newerOutcome }.execute(db)
    }

    let history = try database.read { db in
      try RunHistoryRequest().fetch(db)
    }

    expectNoDifference(
      history,
      RunHistoryRequest.Value(
        entries: [
          RunHistoryEntry(run: newerRun, fileOutcomes: [newerOutcome]),
          RunHistoryEntry(run: olderRun, fileOutcomes: []),
        ]
      )
    )
  }
}

private func temporaryDatabasePath() throws -> String {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
    .appendingPathComponent("VinylFever.sqlite")
    .path(percentEncoded: false)
}
