import Dependencies
import Foundation
import SQLiteData
import Testing
import VinylFeverCore

@testable import VinylFever

@MainActor
@Suite(.serialized)
struct ArtistAliasesModelTests {
  @Test("the sheet accepts either canonical spelling and undo restores the candidate")
  func decideSwapAndUndo() async throws {
    let databasePath = FileManager.default.temporaryDirectory
      .appending(path: "ArtistAliasesModel-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    let database = try VinylFeverDatabase.open(path: databasePath)
    let snapshot = snapshotFixture()
    let model = withDependencies {
      $0.defaultDatabase = database
      $0.librarySnapshotStore = LibrarySnapshotStore(
        read: { snapshot }, write: { _ in }, readAliases: { [:] },
        writeAliases: { _ in }, modifiedAt: { nil })
    } operation: {
      ArtistAliasesModel()
    }

    await model.load()
    let candidate = try #require(model.candidates.first)
    await model.decide(candidate, canonical: candidate.canonical)
    var rows = try await database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(ArtistAlias.acceptedMap(rows) == [candidate.variant: candidate.canonical])

    let swappedDatabase = try VinylFeverDatabase.open(path: FileManager.default.temporaryDirectory
      .appending(path: "ArtistAliasesSwap-\(UUID().uuidString).sqlite").path(percentEncoded: false))
    let swappedModel = withDependencies {
      $0.defaultDatabase = swappedDatabase
      $0.librarySnapshotStore = LibrarySnapshotStore(
        read: { snapshot }, write: { _ in }, readAliases: { [:] },
        writeAliases: { _ in }, modifiedAt: { nil })
    } operation: {
      ArtistAliasesModel()
    }
    await swappedModel.load()
    let swapped = try #require(swappedModel.candidates.first)
    await swappedModel.decide(swapped, canonical: swapped.variant, variant: swapped.canonical)
    rows = try await swappedDatabase.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(ArtistAlias.acceptedMap(rows) == [swapped.canonical: swapped.variant])

    await swappedModel.undo(rows[0])
    #expect(try await swappedDatabase.read { db in try ArtistAlias.all.fetchAll(db).isEmpty })
    #expect(swappedModel.candidates.count == 1)
  }

  private func snapshotFixture() -> LibrarySnapshot {
    let tracks = (1...4).flatMap { number in
      [
        LibraryTrack(persistentID: "variant-\(number)", name: "Shared Song \(number)", artist: "Alias Artist"),
        LibraryTrack(persistentID: "canonical-\(number)", name: "Shared Song \(number)", artist: "Canonical Artist"),
      ]
    } + (5...8).map {
      LibraryTrack(persistentID: "canonical-extra-\($0)", name: "Canonical Song \($0)", artist: "Canonical Artist")
    }
    return LibrarySnapshot(generatedAt: .now, tracks: tracks)
  }
}
