import Dependencies
import DependenciesMacros
import Foundation
import SQLiteData

@DependencyClient
public struct RunLogClient: Sendable {
  public var open: @Sendable (_ request: RunLogOpenRequest) async throws -> RunRecord
  public var appendFileOutcome: @Sendable (_ request: RunLogFileOutcomeRequest) async throws -> RunFileOutcome
  public var close: @Sendable (_ request: RunLogCloseRequest) async throws -> RunRecord
}

public struct RunLogOpenRequest: Equatable, Sendable {
  public var showRootPath: String
  public var kind: RunRecord.Kind
  public var command: String

  public init(showRootPath: String, kind: RunRecord.Kind, command: String) {
    self.showRootPath = showRootPath
    self.kind = kind
    self.command = command
  }
}

public struct RunLogFileOutcomeRequest: Equatable, Sendable {
  public var runID: RunRecord.ID
  public var sourcePath: String
  public var producedPath: String?
  public var status: RunFileOutcome.Status
  public var note: String

  public init(
    runID: RunRecord.ID,
    sourcePath: String,
    producedPath: String? = nil,
    status: RunFileOutcome.Status,
    note: String
  ) {
    self.runID = runID
    self.sourcePath = sourcePath
    self.producedPath = producedPath
    self.status = status
    self.note = note
  }
}

public struct RunLogCloseRequest: Equatable, Sendable {
  public var runID: RunRecord.ID
  public var exitSummary: String

  public init(runID: RunRecord.ID, exitSummary: String) {
    self.runID = runID
    self.exitSummary = exitSummary
  }
}

extension RunLogClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension RunLogClient {
  public static var liveValue: Self {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date

    return Self(
      open: { request in
        let record = RunRecord(
          id: uuid(),
          showRootPath: request.showRootPath,
          kind: request.kind,
          startedAt: date(),
          command: request.command
        )
        try await database.write { db in
          try RunRecord.upsert { record }.execute(db)
        }
        return record
      },
      appendFileOutcome: { request in
        let outcome = RunFileOutcome(
          id: uuid(),
          runID: request.runID,
          sourcePath: request.sourcePath,
          producedPath: request.producedPath,
          status: request.status,
          note: request.note
        )
        try await database.write { db in
          try RunFileOutcome.upsert { outcome }.execute(db)
        }
        return outcome
      },
      close: { request in
        try await database.write { db in
          guard var record = try RunRecord.find(request.runID).fetchOne(db) else {
            throw RunLogError.runNotFound(request.runID)
          }
          record.finishedAt = date()
          record.exitSummary = request.exitSummary
          try RunRecord.upsert { record }.execute(db)
          return record
        }
      }
    )
  }
}

extension DependencyValues {
  public var runLogClient: RunLogClient {
    get { self[RunLogClient.self] }
    set { self[RunLogClient.self] = newValue }
  }
}

public enum RunLogError: LocalizedError, Equatable, Sendable {
  case runNotFound(RunRecord.ID)

  public var errorDescription: String? {
    switch self {
    case let .runNotFound(id):
      "Run \(id.uuidString) was not found."
    }
  }
}
