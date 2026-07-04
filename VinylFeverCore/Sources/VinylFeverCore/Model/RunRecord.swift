import Foundation
import SQLiteData

@Table
public struct RunRecord: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var showRootPath: String
  public var kind: Kind
  public var startedAt: Date
  public var finishedAt: Date?
  public var command: String
  public var exitSummary: String

  public init(
    id: UUID,
    showRootPath: String,
    kind: Kind,
    startedAt: Date,
    finishedAt: Date? = nil,
    command: String,
    exitSummary: String = ""
  ) {
    self.id = id
    self.showRootPath = showRootPath
    self.kind = kind
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.command = command
    self.exitSummary = exitSummary
  }

  public enum Kind: String, CaseIterable, Equatable, Hashable, QueryBindable, Sendable {
    case metadataRead
    case apply
    case convert
    case verify
    case importLibrary
    case verifyLibrary
    case compilationCertify

    public var displayName: String {
      switch self {
      case .metadataRead:
        "Metadata read"
      case .apply:
        "Apply"
      case .convert:
        "Convert"
      case .verify:
        "Verify"
      case .importLibrary:
        "Import library"
      case .verifyLibrary:
        "Verify library"
      case .compilationCertify:
        "Compilation certify"
      }
    }
  }
}

@Table
public struct RunFileOutcome: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var runID: RunRecord.ID
  public var sourcePath: String
  public var producedPath: String?
  public var status: Status
  public var note: String

  public init(
    id: UUID,
    runID: RunRecord.ID,
    sourcePath: String,
    producedPath: String? = nil,
    status: Status,
    note: String
  ) {
    self.id = id
    self.runID = runID
    self.sourcePath = sourcePath
    self.producedPath = producedPath
    self.status = status
    self.note = note
  }

  public enum Status: String, CaseIterable, Equatable, Hashable, QueryBindable, Sendable {
    case read
    case created
    case skipped
    case failed

    public var displayName: String {
      switch self {
      case .read:
        "Read"
      case .created:
        "Created"
      case .skipped:
        "Skipped"
      case .failed:
        "Failed"
      }
    }
  }
}

public struct RunHistoryEntry: Equatable, Identifiable, Sendable {
  public var run: RunRecord
  public var fileOutcomes: [RunFileOutcome]

  public init(run: RunRecord, fileOutcomes: [RunFileOutcome]) {
    self.run = run
    self.fileOutcomes = fileOutcomes
  }

  public var id: RunRecord.ID {
    run.id
  }
}

public struct RunFileOutcomeSummary: Equatable, Sendable {
  public var sourcePath: String
  public var status: RunFileOutcome.Status
  public var note: String

  public init(sourcePath: String, status: RunFileOutcome.Status, note: String) {
    self.sourcePath = sourcePath
    self.status = status
    self.note = note
  }

  public init(outcome: RunFileOutcome) {
    self.init(sourcePath: outcome.sourcePath, status: outcome.status, note: outcome.note)
  }
}

public struct RunHistoryRequest: FetchKeyRequest {
  public var limit: Int

  public struct Value: Equatable, Sendable {
    public var entries: [RunHistoryEntry] = []

    public init(entries: [RunHistoryEntry] = []) {
      self.entries = entries
    }
  }

  public init(limit: Int = RunHistory.defaultLimit) {
    self.limit = limit
  }

  public func fetch(_ db: Database) throws -> Value {
    try Value(entries: RunHistory.entries(in: db, limit: limit))
  }
}

public enum RunHistory {
  public static let defaultLimit = 50

  public static func entries(in db: Database, limit: Int = defaultLimit) throws -> [RunHistoryEntry] {
    let runs = try RunRecord
      .order { $0.startedAt.desc() }
      .limit(limit)
      .fetchAll(db)

    return try runs.map { run in
      let outcomes = try RunFileOutcome
        .where { $0.runID.eq(run.id) }
        .order(by: \.sourcePath)
        .fetchAll(db)
      return RunHistoryEntry(run: run, fileOutcomes: outcomes)
    }
  }

  public static func mostRecentMetadataReadOutcomes(
    showRootPath: String,
    in db: Database
  ) throws -> [RunFileOutcomeSummary]? {
    let latestMetadataRead = RunRecord
      .where { $0.showRootPath.eq(showRootPath) && $0.kind.eq(RunRecord.Kind.metadataRead) }
      .order { $0.startedAt.desc() }
      .limit(1)
    guard let run = try latestMetadataRead.fetchOne(db) else {
      return nil
    }

    return try RunFileOutcome
      .where { $0.runID.eq(run.id) }
      .order(by: \.sourcePath)
      .fetchAll(db)
      .map(RunFileOutcomeSummary.init(outcome:))
  }
}
