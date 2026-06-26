import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct SourceLabelTests {
  @Test
  func seedsBuiltInVocabularyIdempotently() throws {
    let database = try VinylFeverDatabase.open()

    try VinylFeverDatabase.seedBuiltInSourceLabels(in: database)

    let sourceLabels = try database.read { db in
      try SourceLabel.order(by: \.token).fetchAll(db)
    }

    expectNoDifference(
      SourceLabel.deduplicated(sourceLabels).map(\.token),
      SourceLabel.builtInTokens
    )
    expectNoDifference(sourceLabels.count, SourceLabel.builtInTokens.count)
  }

  @Test
  func builtInIDsAreDeterministicAndDistinct() {
    let firstIDs = SourceLabel.builtIns.map(\.id)
    let secondIDs = SourceLabel.builtIns.map(\.id)

    expectNoDifference(firstIDs, secondIDs)
    expectNoDifference(Set(firstIDs).count, SourceLabel.builtInTokens.count)
  }

  @Test
  func deduplicatesByNormalizedTokenOnRead() {
    let userDuplicate = SourceLabel(id: UUID(0), token: "(sbd)", isBuiltIn: false)
    let userMTX = SourceLabel(id: UUID(2), token: "MTX", isBuiltIn: false)
    let earlierUserMTX = SourceLabel(id: UUID(1), token: "mtx", isBuiltIn: false)

    let sourceLabels = SourceLabel.deduplicated(
      [userDuplicate, userMTX, earlierUserMTX] + SourceLabel.builtIns
    )

    expectNoDifference(
      sourceLabels.first { $0.normalizedTokenKey == "sbd" },
      SourceLabel.builtIns.first { $0.token == "SBD" }
    )
    expectNoDifference(
      sourceLabels.first { $0.normalizedTokenKey == "mtx" },
      earlierUserMTX
    )
  }

  @Test
  func vocabularyPersistsAcrossDatabaseLaunches() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("VinylFeverCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory
      .appendingPathComponent("VinylFever.sqlite")
      .path(percentEncoded: false)
    let userSourceLabel = SourceLabel(id: UUID(1), token: "MTX", isBuiltIn: false)

    do {
      let database = try VinylFeverDatabase.open(path: path)
      try database.write { db in
        try SourceLabel.upsert { userSourceLabel }.execute(db)
      }
    }

    do {
      let database = try VinylFeverDatabase.open(path: path)
      let sourceLabels = try database.read { db in
        try SourceLabel.order(by: \.token).fetchAll(db)
      }

      expectNoDifference(
        SourceLabel.deduplicated(sourceLabels).contains(userSourceLabel),
        true
      )
    }
  }
}
