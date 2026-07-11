import Dependencies
import Foundation
import Testing
@testable import VinylFeverCore

@Suite(.serialized)
struct CollectionInboxClientTests {
  @Test
  func stagePreservesOriginalsAndCopiesIn() throws {
    let harness = try InboxHarness()
    let source = try harness.makeSource(named: "One-Hit Wonder.flac", contents: "audio")
    let albumID = UUID()

    let staged = try harness.client.stage(files: [source], albumID: albumID)

    // Original is untouched.
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    // Copy landed in the album's staging subfolder.
    #expect(staged.count == 1)
    #expect(staged[0].deletingLastPathComponent().lastPathComponent == albumID.uuidString)
    #expect(staged[0].lastPathComponent == "One-Hit Wonder.flac")
    #expect(try harness.contentsNames(albumID) == ["One-Hit Wonder.flac"])
  }

  @Test
  func nameCollisionSuffixesRatherThanOverwrites() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    let first = try harness.makeSource(named: "Track.mp3", contents: "first", subfolder: "a")
    let second = try harness.makeSource(named: "Track.mp3", contents: "second", subfolder: "b")
    let third = try harness.makeSource(named: "Track.mp3", contents: "third", subfolder: "c")

    _ = try harness.client.stage(files: [first], albumID: albumID)
    _ = try harness.client.stage(files: [second], albumID: albumID)
    _ = try harness.client.stage(files: [third], albumID: albumID)

    #expect(try harness.contentsNames(albumID) == ["Track (2).mp3", "Track (3).mp3", "Track.mp3"])
    // No overwrite — each distinct payload survived.
    let payloads = try harness.client.contents(albumID: albumID).map { try String(contentsOf: $0, encoding: .utf8) }
    #expect(Set(payloads) == ["first", "second", "third"])
  }

  @Test
  func extensionlessCollisionStillSuffixes() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    let first = try harness.makeSource(named: "README", contents: "1", subfolder: "a")
    let second = try harness.makeSource(named: "README", contents: "2", subfolder: "b")

    _ = try harness.client.stage(files: [first], albumID: albumID)
    _ = try harness.client.stage(files: [second], albumID: albumID)

    #expect(try harness.contentsNames(albumID) == ["README", "README (2)"])
  }

  @Test
  func contentsAndSummaryCountsMatchTheDirectory() throws {
    let harness = try InboxHarness()
    let albumA = UUID()
    let albumB = UUID()
    _ = try harness.client.stage(
      files: [
        try harness.makeSource(named: "1.flac", contents: "x", subfolder: "a1"),
        try harness.makeSource(named: "2.flac", contents: "y", subfolder: "a2"),
      ],
      albumID: albumA
    )
    _ = try harness.client.stage(
      files: [try harness.makeSource(named: "solo.mp3", contents: "z", subfolder: "b1")],
      albumID: albumB
    )

    #expect(try harness.client.contents(albumID: albumA).count == 2)
    #expect(try harness.client.contents(albumID: albumB).count == 1)

    let summary = try harness.client.summary()
    #expect(summary.count == 2)
    #expect(summary.first { $0.albumID == albumA }?.fileCount == 2)
    #expect(summary.first { $0.albumID == albumB }?.fileCount == 1)
  }

  @Test
  func summaryIsEmptyForACleanRoot() throws {
    let harness = try InboxHarness()
    #expect(try harness.client.summary().isEmpty)
  }

  @Test
  func drainTrashesAlbumFilesAndLeavesSubfolderAbsent() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    _ = try harness.client.stage(
      files: [try harness.makeSource(named: "gone.flac", contents: "bye")],
      albumID: albumID
    )
    let subfolder = try harness.client.stagingDirectory(albumID: albumID)
    #expect(FileManager.default.fileExists(atPath: subfolder.path(percentEncoded: false)))

    try harness.client.drain(albumID: albumID)

    #expect(!FileManager.default.fileExists(atPath: subfolder.path(percentEncoded: false)))
    #expect(try harness.client.contents(albumID: albumID).isEmpty)
    #expect(try harness.client.summary().isEmpty)
  }

  @Test
  func removeTrashesOnlyTheNamedFilesAndLeavesTheRest() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    _ = try harness.client.stage(
      files: [
        try harness.makeSource(named: "keep.flac", contents: "keep", subfolder: "s1"),
        try harness.makeSource(named: "drop.flac", contents: "drop", subfolder: "s2"),
      ],
      albumID: albumID
    )
    let staged = try harness.client.contents(albumID: albumID)
    let toRemove = try #require(staged.first { $0.lastPathComponent == "drop.flac" })

    try harness.client.remove(files: [toRemove], albumID: albumID)

    #expect(try harness.contentsNames(albumID) == ["keep.flac"])
    // A missing file is skipped rather than throwing, so removing again is a no-op.
    #expect(throws: Never.self) {
      try harness.client.remove(files: [toRemove], albumID: albumID)
    }
  }

  @Test
  func removeRefusesAFileOutsideTheAlbumSubfolder() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    let otherAlbumID = UUID()
    let staged = try harness.client.stage(
      files: [try harness.makeSource(named: "sibling.flac", contents: "x")],
      albumID: otherAlbumID
    )
    // A file that belongs to a *different* album still lives under the Inbox root, but must
    // not be removable through another album's queue.
    #expect(throws: CollectionInboxError.self) {
      try harness.client.remove(files: staged, albumID: albumID)
    }
    // The sibling album's file survives.
    #expect(try harness.contentsNames(otherAlbumID) == ["sibling.flac"])
  }

  @Test
  func drainIsANoOpForAnUnstagedAlbum() throws {
    let harness = try InboxHarness()
    // Never throws even though nothing was ever staged.
    try harness.client.drain(albumID: UUID())
  }

  @Test
  func drainRefusesAPathOutsideTheInboxRoot() throws {
    let harness = try InboxHarness()
    let store = CollectionInboxStore(root: harness.root)
    let outside = URL(fileURLWithPath: "/tmp/definitely-not-the-inbox")

    #expect(throws: CollectionInboxError.pathOutsideInboxRoot(outside)) {
      try store.assertUnderRoot(outside)
    }
    // The real album subfolder passes the guard.
    #expect(throws: Never.self) {
      try store.assertUnderRoot(store.albumDirectory(UUID()))
    }
  }

  @Test
  func roundTripStageListDrainEmpties() throws {
    let harness = try InboxHarness()
    let albumID = UUID()
    _ = try harness.client.stage(
      files: [
        try harness.makeSource(named: "a.flac", contents: "a", subfolder: "s1"),
        try harness.makeSource(named: "b.flac", contents: "b", subfolder: "s2"),
      ],
      albumID: albumID
    )
    #expect(try harness.client.contents(albumID: albumID).count == 2)

    try harness.client.drain(albumID: albumID)

    #expect(try harness.client.contents(albumID: albumID).isEmpty)
    #expect(try harness.client.summary().isEmpty)
  }
}

/// A temp Inbox root plus a scratch directory for source files, cleaned up on deinit.
private final class InboxHarness {
  let root: URL
  let sources: URL
  let client: CollectionInboxClient

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("InboxTests-\(UUID().uuidString)", isDirectory: true)
    root = base.appendingPathComponent("Inbox", isDirectory: true)
    sources = base.appendingPathComponent("Sources", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    client = .live(root: root)
  }

  deinit {
    try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
  }

  func makeSource(named name: String, contents: String, subfolder: String? = nil) throws -> URL {
    let directory = subfolder.map { sources.appendingPathComponent($0, isDirectory: true) } ?? sources
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(contents.utf8).write(to: url)
    return url
  }

  func contentsNames(_ albumID: CompilationAlbum.ID) throws -> [String] {
    try client.contents(albumID: albumID).map(\.lastPathComponent)
  }
}
