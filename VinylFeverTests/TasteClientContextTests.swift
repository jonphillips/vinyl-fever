import Dependencies
import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct TasteClientContextTests {
  @Test("test hosts do not use live taste clients")
  func testHostDoesNotUseLiveTasteClients() async throws {
    @Dependency(\.newMusicCatalogClient) var newMusicClient
    @Dependency(\.tasteCurationClient) var curationClient
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try await curationClient.append(
      CurationChange(observedAt: .now, previousSnapshotAt: nil), "Test Mac", folder)

    #expect(!FileManager.default.fileExists(atPath: folder.path))
    await #expect(throws: NewMusicExposureError.notConfigured) {
      try await newMusicClient.fetch()
    }
  }
}
