import Dependencies
import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct TasteClientContextTests {
  @Test("test hosts do not use live taste clients")
  func testHostDoesNotUseLiveTasteClients() async {
    let newMusicClient = withDependencies { $0.context = .test } operation: {
      @Dependency(\.newMusicCatalogClient) var client
      return client
    }
    await #expect(throws: NewMusicExposureError.notConfigured) {
      try await newMusicClient.fetch()
    }

    let curationClient = withDependencies { $0.context = .test } operation: {
      @Dependency(\.tasteCurationClient) var client
      return client
    }
    await curationClient.append(CurationChange(observedAt: .now, previousSnapshotAt: nil), "Test Mac", URL(fileURLWithPath: "/tmp/test-curation"))
  }
}
