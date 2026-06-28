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
    case metadataRead = "metadataRead"
    case apply
    case convert
    case verify

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

public struct RunHistoryRequest: FetchKeyRequest {
  public struct Value: Equatable, Sendable {
    public var entries: [RunHistoryEntry] = []

    public init(entries: [RunHistoryEntry] = []) {
      self.entries = entries
    }
  }

  public init() {
  }

  public func fetch(_ db: Database) throws -> Value {
    try Value(entries: RunHistory.entries(in: db))
  }
}

public enum RunHistory {
  public static func entries(in db: Database) throws -> [RunHistoryEntry] {
    let runs = try RunRecord
      .order { $0.startedAt.desc() }
      .fetchAll(db)
    let outcomes = try RunFileOutcome
      .order(by: \.sourcePath)
      .fetchAll(db)
    let outcomesByRunID = Dictionary(grouping: outcomes, by: \.runID)

    return runs.map { run in
      RunHistoryEntry(run: run, fileOutcomes: outcomesByRunID[run.id] ?? [])
    }
  }
}
