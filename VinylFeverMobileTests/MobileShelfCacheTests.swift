import Dependencies
import Foundation
import GRDB
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct MobileShelfCacheTests {
  @Test @MainActor
  func cachedShelfAndProgressShowBeforeTheReadAndFreshDataReplacesThem() async throws {
    let database = try makeDatabase()
    let archived = batch("Archived", at: date(-1_500_000))
    let pending = batch("Pending", at: date(100))
    _ = try ShelfCache.writeShelf(read([archived, pending]), to: database)
    try ShelfCache.replaceLibrary([], to: database)
    _ = try ShelfCache.replaceProgress([
      "Mac|100.0": PlaylistProgressResult(songs: ["Mac|100.0|0": .notHeard]),
    ], to: database)

    let gate = ShelfReadGate()
    let models = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(200)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.keepLibraryClient.readRoles = { throw CocoaError(.fileReadUnknown) }
      dependencies.playlistShelfClient.read = { try await gate.read() }
    }) {
      (PlaylistShelfModel(), PlaylistProgressModel())
    }
    models.1.loadCache()
    await models.1.refresh(models.0.playlists, libraryPlaylists: [])
    let refresh = Task { await models.0.refresh() }
    await gate.waitUntilRead()

    #expect(models.0.playlists.map(\.batch.playlist).compactMap { $0 }.sorted() == ["Archived", "Pending"])
    #expect(models.0.count(in: .archived) == 1)
    let pendingPlaylist = try #require(models.0.playlists.first { $0.batch.playlist == "Pending" })
    #expect(models.0.isNotInMusicYet(pendingPlaylist))
    #expect(models.1.results["Mac|100.0"]?.counts.notHeard == 1)

    await gate.release(read([batch("Fresh", at: date(200))]))
    await refresh.value
    #expect(models.0.playlists.map(\.batch.playlist).compactMap { $0 } == ["Fresh"])
  }

  @Test @MainActor
  func cleanReadReplacesAndRoundTripsShelfLibraryAndProgress() async throws {
    let database = try makeDatabase()
    _ = try ShelfCache.writeShelf(read([batch("Old", at: date(1))]), to: database)
    let fresh = batch("Fresh", at: date(2))
    let freshPlaylistID = "Mac|2.0"
    let freshSongID = "Mac|2.0|0"
    let first = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(3)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { [KeepLibraryPlaylist(id: "library-id", name: "Fresh")] }
      dependencies.keepLibraryClient.readRoles = { nil }
      dependencies.keepLibraryClient.tracks = { _ in [] }
      dependencies.playlistTasteNotesClient.read = { emptyNotes() }
      dependencies.playlistListeningLogClient.read = { _, _ in [] }
      dependencies.playlistShelfClient.read = { read([fresh]) }
    }) {
      (PlaylistShelfModel(), PlaylistProgressModel())
    }
    await first.0.refresh()
    await first.1.refresh(first.0.playlists, libraryPlaylists: first.0.libraryPlaylists)
    first.1.updateSavedKeeps([freshSongID: ["Keepers"]])

    let reopened = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(3)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.playlistShelfClient.read = { throw CocoaError(.fileReadUnknown) }
    }) {
      (PlaylistShelfModel(), PlaylistProgressModel())
    }
    reopened.0.loadCache()
    reopened.1.loadCache()
    #expect(reopened.0.playlists.map(\.batch.playlist).compactMap { $0 } == ["Fresh"])
    #expect(reopened.0.libraryPlaylists == [KeepLibraryPlaylist(id: "library-id", name: "Fresh")])
    #expect(reopened.1.results[freshPlaylistID]?.songs[freshSongID] == .kept(in: ["Keepers"]))
    #expect(reopened.1.results[freshPlaylistID]?.counts.kept == 1)
    let cachedBatchNames = try await database.read { try CachedBatch.all.fetchAll($0).compactMap { $0.batch?.playlist } }
    #expect(cachedBatchNames == ["Fresh"])
  }

  @Test
  func cacheRoundTripPreservesCodecTimestampAndShelfIDs() throws {
    let source = try preciseBatchFromLedgerLine()
    let before = shelfPlaylists([source]).first
    let database = try makeDatabase()

    _ = try ShelfCache.writeShelf(read([source]), to: database)

    let cached = try ShelfCache.load(from: database)
    let after = shelfPlaylists(cached.batches).first
    #expect(cached.batches.first?.recordedAt == source.recordedAt)
    #expect(after?.id == before?.id)
    #expect(after?.songs.map(\.id) == before?.songs.map(\.id))
  }

  @Test @MainActor
  func preciseCachedProgressAndSelectionSurviveFreshRead() async throws {
    let source = try preciseBatchFromLedgerLine()
    let cachedPlaylist = try #require(shelfPlaylists([source]).first)
    let database = try makeDatabase()
    _ = try ShelfCache.writeShelf(read([source]), to: database)
    try ShelfCache.replaceProgress([
      cachedPlaylist.id: PlaylistProgressResult(songs: [cachedPlaylist.songs[0].id: .kept(in: ["Keepers"])]),
    ], to: database)

    let gate = ShelfReadGate()
    let models = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(1_793_216_700)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.playlistShelfClient.read = { try await gate.read() }
    }) {
      (PlaylistShelfModel(), PlaylistProgressModel())
    }
    models.1.loadCache()
    let refresh = Task { await models.0.refresh() }
    await gate.waitUntilRead()

    models.0.selectedPlaylistID = cachedPlaylist.id
    #expect(models.0.playlists.first?.id == cachedPlaylist.id)
    #expect(models.1.results[cachedPlaylist.id]?.counts.kept == 1)

    await gate.release(read([source]))
    await refresh.value

    #expect(models.0.playlists.first?.id == cachedPlaylist.id)
    #expect(models.0.selectedPlaylistID == cachedPlaylist.id)
    #expect(models.1.results[cachedPlaylist.id]?.counts.kept == 1)
  }

  @Test @MainActor
  func partialReadMergesBatchesAndKeepsTheNewerCreationEvent() async throws {
    let database = try makeDatabase()
    let old = batch("Old", at: date(10))
    let priorEvent = PlaylistCreationEvent(kind: .created, host: "Mac", recordedAt: date(10), playlist: "Old", at: date(30),
      writerHost: "Mac", musicID: "music-id", songs: 1, skipped: [])
    _ = try ShelfCache.writeShelf(read([old], events: [priorEvent]), to: database)
    let added = batch("Added", at: date(20))
    let staleEvent = PlaylistCreationEvent(kind: .dismissed, host: "Mac", recordedAt: date(10), playlist: "Old", at: date(29))
    let partial = RecommendationLedgerFolderRead(
      ledger: RecommendationLedgerReadResult(batches: [added], skippedLines: 0),
      creations: PlaylistCreationsReadResult(events: [staleEvent], skippedLines: 0, filesRead: 1),
      filesRead: 1, unreadableFileCount: 1, totalFileCount: 2
    )
    let model = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(40)
      dependencies.keepLibraryClient.isAuthorized = { false }
      dependencies.playlistShelfClient.read = { partial }
    }) { PlaylistShelfModel() }

    await model.refresh()

    #expect(Set(model.playlists.compactMap(\.batch.playlist)) == ["Old", "Added"])
    #expect(model.creationEvents.map(\.kind) == [priorEvent.kind])
    #expect(model.creationEvents.first?.playlist == priorEvent.playlist)
    #expect(abs((model.creationEvents.first?.at.timeIntervalSince1970 ?? 0) - priorEvent.at.timeIntervalSince1970) < 0.001)
    let cachedBatchNames = try await database.read { try CachedBatch.all.fetchAll($0).compactMap { $0.batch?.playlist } }
    #expect(Set(cachedBatchNames) == ["Old", "Added"])
  }

  @Test @MainActor
  func genericReadFailureKeepsCacheButFolderAccessClearsTheShelfAndUnauthorizedHidesCache() async throws {
    let database = try makeDatabase()
    _ = try ShelfCache.writeShelf(read([batch("Cached", at: date(10))]), to: database)

    let failed = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(20)
      dependencies.keepLibraryClient.isAuthorized = { false }
      dependencies.playlistShelfClient.read = { throw CocoaError(.fileReadUnknown) }
    }) { PlaylistShelfModel() }
    await failed.refresh()
    #expect(failed.playlists.map(\.batch.playlist).compactMap { $0 } == ["Cached"])
    #expect(failed.hasUnreadableFiles)

    let denied = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(20)
      dependencies.keepLibraryClient.isAuthorized = { false }
      dependencies.playlistShelfClient.read = { throw ProbeBookmarkError.folderNotSelected }
    }) { PlaylistShelfModel() }
    await denied.refresh()
    #expect(denied.requiresFolderAccess)
    #expect(denied.playlists.isEmpty)
    #expect(denied.libraryPlaylists == nil)
  }

  @Test @MainActor
  func failedLibraryReadRetainsItsCacheAndUnauthorizedModelsDoNotUseCachedMusicState() async throws {
    let database = try makeDatabase()
    let cachedBatch = batch("Cached", at: date(10))
    _ = try ShelfCache.writeShelf(read([cachedBatch]), to: database)
    try ShelfCache.replaceLibrary([KeepLibraryPlaylist(id: "music-id", name: "Cached")], to: database)
    try ShelfCache.replaceProgress(["Mac|10.0": PlaylistProgressResult(songs: ["Mac|10.0|0": .notHeard])], to: database)

    let failedLibraryRead = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.date.now = date(20)
      dependencies.keepLibraryClient.isAuthorized = { true }
      dependencies.keepLibraryClient.libraryPlaylists = { throw CocoaError(.fileReadUnknown) }
      dependencies.playlistShelfClient.read = { read([cachedBatch]) }
    }) { PlaylistShelfModel() }
    await failedLibraryRead.refresh()
    #expect(failedLibraryRead.libraryPlaylists == [KeepLibraryPlaylist(id: "music-id", name: "Cached")])
    let cachedLibraryNames = try await database.read { try CachedLibraryPlaylist.all.fetchAll($0).map(\.name) }
    #expect(cachedLibraryNames == ["Cached"])

    let unauthorized = withDependencies({ dependencies in
      dependencies.mobileCacheDatabase = database
      dependencies.keepLibraryClient.isAuthorized = { false }
    }) { (PlaylistShelfModel(), PlaylistProgressModel()) }
    unauthorized.0.loadCache()
    unauthorized.1.loadCache()
    await unauthorized.1.refresh(unauthorized.0.playlists)
    #expect(unauthorized.0.libraryPlaylists == nil)
    #expect(!unauthorized.1.isAvailable)
    #expect(unauthorized.1.results.isEmpty)
    let cachedProgressCount = try await database.read { try CachedSongProgress.all.fetchAll($0).count }
    #expect(cachedProgressCount == 1)
  }

  @Test
  func garbageAndSupersededDatabasesAreReplacedWithWorkingEmptyCaches() throws {
    let garbagePath = temporaryDatabasePath()
    try Data("garbage".utf8).write(to: URL(fileURLWithPath: garbagePath))
    let garbageDatabase = MobileDatabase.open(path: garbagePath)
    #expect(try garbageDatabase.read { try CachedBatch.all.fetchAll($0).isEmpty })
    try garbageDatabase.close()
    try? FileManager.default.removeItem(atPath: garbagePath)

    let oldPath = temporaryDatabasePath()
    let oldDatabase = try DatabaseQueue(path: oldPath)
    try oldDatabase.write { db in
      try db.create(table: "grdb_migrations") { table in
        table.column("identifier", .text).primaryKey()
      }
      try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('future migration')")
    }
    try oldDatabase.close()
    let recovered = MobileDatabase.open(path: oldPath)
    #expect(try recovered.read { try CachedBatch.all.fetchAll($0).isEmpty })
    try recovered.close()
    try? FileManager.default.removeItem(atPath: oldPath)
  }

  private func makeDatabase() throws -> any DatabaseWriter {
    try MobileDatabase.openInMemory()
  }

  private func temporaryDatabasePath() -> String {
    FileManager.default.temporaryDirectory.appending(path: "mobile-cache-\(UUID().uuidString).sqlite").path
  }

  private func batch(_ name: String, at date: Date) -> RecommendationBatch {
    RecommendationBatch(recordedAt: date, host: "Mac", playlist: name, tracks: [
      RecommendationTrack(artist: "Artist", title: "\(name) song", familiar: false, reasons: [], artistKnown: true),
    ])
  }

  private func preciseBatchFromLedgerLine() throws -> RecommendationBatch {
    let source = batch("Precise", at: date(1_793_216_522.383))
    let line = try RecommendationLedgerCodec.encode(source)
    #expect(String(decoding: line, as: UTF8.self).contains("2026-10-28T19:42:02.383Z"))
    return try #require(RecommendationLedgerCodec.readFiles([line]).batches.first)
  }

  private func shelfPlaylists(_ batches: [RecommendationBatch]) -> [PlaylistShelfPlaylist] {
    PlaylistShelf.make(
      from: RecommendationLedgerReadResult(batches: batches, skippedLines: 0),
      now: date(1_793_216_700), calendar: .current, timeZone: .current
    )
  }

  private func read(_ batches: [RecommendationBatch], events: [PlaylistCreationEvent] = []) -> RecommendationLedgerFolderRead {
    RecommendationLedgerFolderRead(
      ledger: RecommendationLedgerReadResult(batches: batches, skippedLines: 0),
      creations: PlaylistCreationsReadResult(events: events, skippedLines: 0, filesRead: 1),
      filesRead: 1, unreadableFileCount: 0, totalFileCount: 1
    )
  }

  private func emptyNotes() -> PlaylistTasteNotesFolderRead {
    PlaylistTasteNotesFolderRead(result: TasteNotesCodec.readFiles([]), unreadableFileCount: 0, totalFileCount: 0)
  }

  private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
}

private actor ShelfReadGate {
  private var readContinuation: CheckedContinuation<RecommendationLedgerFolderRead, any Error>?
  private var startContinuation: CheckedContinuation<Void, Never>?
  private var didStart = false

  func read() async throws -> RecommendationLedgerFolderRead {
    try await withCheckedThrowingContinuation { continuation in
      readContinuation = continuation
      didStart = true
      startContinuation?.resume()
      startContinuation = nil
    }
  }

  func waitUntilRead() async {
    if didStart { return }
    await withCheckedContinuation { startContinuation = $0 }
  }

  func release(_ value: RecommendationLedgerFolderRead) {
    readContinuation?.resume(returning: value)
    readContinuation = nil
  }
}
