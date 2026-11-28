import Foundation
import Testing
import VinylFeverListening
import VinylFeverNotes

@Suite("Tracked playlist exposure")
struct TrackedPlaylistExposureTests {
  @Test("resolves one library name and reports missing or duplicate names")
  func libraryResolution() {
    #expect(TrackedPlaylistCatalogResolver.resolve(name: "Antidote", library: [
      TrackedPlaylistLibraryEntry(name: "Antidote", catalogID: "catalog-a")
    ]) == .found("catalog-a"))
    #expect(TrackedPlaylistCatalogResolver.resolve(name: "Missing", library: []) == .gap(
      "Apple Music couldn't find this tracked catalog playlist."))
    #expect(TrackedPlaylistCatalogResolver.resolve(name: "Antidote", library: [
      TrackedPlaylistLibraryEntry(name: "Antidote", catalogID: "a"),
      TrackedPlaylistLibraryEntry(name: "Antidote", catalogID: "b"),
    ]) == .gap("Apple Music returned more than one library playlist with this name."))
  }

  @Test("caches a catalog ID only when a unique library playlist lacks its relationship")
  func cacheFallback() {
    #expect(TrackedPlaylistCatalogResolver.resolve(name: "Antidote", library: [
      TrackedPlaylistLibraryEntry(name: "Antidote", catalogID: nil)
    ], cachedID: "cached") == .found("cached"))
    #expect(TrackedPlaylistCatalogResolver.resolve(name: "Antidote", library: [], cachedID: "cached") != .found("cached"))
  }

  @Test("appends only when the playlist modification date changes")
  func modificationDatePolicy() {
    let first = makeSnapshot(modified: 10, fetched: 11)
    let unchanged = makeSnapshot(modified: 10, fetched: 20)
    let changed = makeSnapshot(modified: 12, fetched: 21)
    let records: [TrackedPlaylistRecord] = [.snapshot(first)]
    #expect(!TrackedPlaylistSnapshotPolicy.shouldAppend(unchanged, after: records))
    #expect(TrackedPlaylistSnapshotPolicy.shouldAppend(changed, after: records))
  }

  private func makeSnapshot(modified: TimeInterval, fetched: TimeInterval) -> TrackedPlaylistSnapshot {
    TrackedPlaylistSnapshot(name: "Antidote", catalogID: "catalog-a",
      lastModifiedDate: Date(timeIntervalSince1970: modified), fetchedAt: Date(timeIntervalSince1970: fetched),
      host: "Mac", tracks: [])
  }
}
