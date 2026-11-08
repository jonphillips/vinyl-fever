import Dependencies
import Foundation
import Testing
import VinylFeverAppleMusic
import VinylFeverNotes
@testable import VinylFeverMobile

struct PlaylistCreateModelTests {
  @Test @MainActor
  func subscriptionAndSyncLibraryGatesRunBeforeMatching() async {
    for subscription in [AppleMusicSubscriptionStatus(canPlayCatalogContent: false, hasCloudLibraryEnabled: true),
      AppleMusicSubscriptionStatus(canPlayCatalogContent: true, hasCloudLibraryEnabled: false)] {
      let matcher = MatchRecorder()
      let model = withDependencies({ dependencies in
        dependencies.appleMusicCatalogClient.authorizationStatus = { .authorized }
        dependencies.appleMusicCatalogClient.subscriptionStatus = { subscription }
        dependencies.catalogMatchResolver.resolve = { request, _ in await matcher.record(request); return [] }
      }) { PlaylistCreateModel() }

      await model.createButtonTapped(playlist())

      #expect(model.destination == nil)
      #expect(model.gateMessage != nil)
      #expect(await matcher.requests.isEmpty)
    }
  }

  @Test @MainActor
  func ambiguousRowsBlockCreateUntilChosenOrSkippedAndDuplicatesAreSkipped() async {
    let duplicate = candidate(id: "same", title: "Song")
    let alternate = candidate(id: "other", title: "Song (Live)")
    let model = withDependencies({ dependencies in
      readyDependencies(&dependencies)
      dependencies.catalogMatchResolver.resolve = { request, _ in
        if request.tracks[0].index == 0 {
          return [ResolvedPlaylistRow(request: request.tracks[0], status: .ambiguous([
            ScoredCandidate(candidate: duplicate, score: 0.9), ScoredCandidate(candidate: alternate, score: 0.8),
          ]))]
        }
        return [ResolvedPlaylistRow(request: request.tracks[0], status: .matched(duplicate, score: 1))]
      }
    }) { PlaylistCreateModel() }
    let batch = playlist(tracks: [track("Song"), track("Song again")])

    await model.createButtonTapped(batch)
    #expect(model.unresolvedChoiceCount == 1)
    #expect(!model.canCreate)
    model.choose(duplicate, for: 0)
    #expect(model.canCreate)
    #expect(model.duplicateOf(model.rows[1]) == 0)
    model.skip(0)
    #expect(model.unresolvedChoiceCount == 0)
    #expect(model.createButtonTitle == "Create Playlist · 1 songs")
  }

  @Test @MainActor
  func createRechecksNameThenAppendsCreationEventAndHandlesRecordFailure() async {
    let events = CreationRecorder()
    let created = CreatedPlaylistRef(id: "p.1", name: "Night Drive", trackCount: 1)
    let model = withDependencies({ dependencies in
      readyDependencies(&dependencies)
      dependencies.catalogMatchResolver.resolve = { request, _ in
        [ResolvedPlaylistRow(request: request.tracks[0], status: .matched(candidate(id: "song.1", title: "Song"), score: 1))]
      }
      dependencies.playlistCreateSupportClient.deviceName = { "Jon’s iPhone" }
      dependencies.playlistCreateSupportClient.appendCreation = { events.append($0) }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, songs in
        #expect(songs == [PlaylistSongReference(id: "song.1", source: .catalog)])
        return created
      }
    }) { PlaylistCreateModel() }
    let batch = playlist()

    await model.createButtonTapped(batch)
    await model.create()

    #expect(model.destination == nil)
    #expect(model.completionMessage == "Created “Night Drive” with 1 song.")
    let saved = events.values
    #expect(saved.count == 1)
    #expect(saved.first?.kind == .created)
    #expect(saved.first?.musicID == "p.1")
    #expect(saved.first?.device == "Jon’s iPhone")

    let recordFailure = withDependencies({ dependencies in
      readyDependencies(&dependencies)
      dependencies.catalogMatchResolver.resolve = { request, _ in
        [ResolvedPlaylistRow(request: request.tracks[0], status: .matched(candidate(id: "song.1", title: "Song"), score: 1))]
      }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, _ in created }
      dependencies.playlistCreateSupportClient.appendCreation = { _ in throw CocoaError(.fileWriteUnknown) }
    }) { PlaylistCreateModel() }
    await recordFailure.createButtonTapped(batch)
    await recordFailure.create()
    #expect(recordFailure.errorMessage?.contains("Created in Music, but the record didn’t save") == true)
  }

  @Test @MainActor
  func aPlaylistCreatedDuringMatchingStopsBeforePosting() async {
    let presence = LibraryPresence()
    let createCalls = CreateCallRecorder()
    let model = withDependencies({ dependencies in
      readyDependencies(&dependencies)
      dependencies.catalogMatchResolver.resolve = { request, _ in
        [ResolvedPlaylistRow(request: request.tracks[0], status: .matched(candidate(id: "song.1", title: "Song"), score: 1))]
      }
      dependencies.keepLibraryClient.libraryPlaylists = { await presence.next() }
      dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, _ in
        await createCalls.record()
        return CreatedPlaylistRef(id: "p.1", name: "Night Drive", trackCount: 1)
      }
    }) { PlaylistCreateModel() }

    await model.createButtonTapped(playlist())
    await model.create()

    #expect(model.errorMessage == "Already in Music")
    #expect(await createCalls.count == 0)
  }

  @Test @MainActor
  func anOldBatchFallsBackToUploadsOnlyAfterCatalogMissAndPartialCreateIsRecorded() async {
    let events = CreationRecorder()
    let librarySong = candidate(id: "i.upload", title: "Song", source: .libraryUpload)
    let model = withDependencies({ dependencies in
      readyDependencies(&dependencies)
      dependencies.catalogMatchResolver.resolve = { request, _ in
        [ResolvedPlaylistRow(request: request.tracks[0], status: .notFound(error: nil))]
      }
      dependencies.appleMusicCatalogClient.searchLibraryAlbums = { _ in [LibraryAlbumCandidate(id: "album", title: "Record")] }
      dependencies.appleMusicCatalogClient.libraryAlbumTracks = { _ in
        [LibrarySongCandidate(id: librarySong.id, title: librarySong.title, artist: librarySong.artistName,
          album: "Record", hasCatalogID: false)]
      }
      dependencies.appleMusicCatalogClient.searchLibrarySongs = { _, _ in [] }
      dependencies.keepLibraryClient.libraryPlaylists = { [] }
      dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, _ in
        throw CreatedPlaylistPartialError(createdPlaylist: CreatedPlaylistRef(id: "p.2", name: "Night Drive", trackCount: 0),
          unaddedSongs: [PlaylistSongReference(id: librarySong.id, source: .libraryUpload)], detail: "Temporary failure")
      }
      dependencies.playlistCreateSupportClient.appendCreation = { events.append($0) }
    }) { PlaylistCreateModel() }
    let batch = playlist(tracks: [RecommendationTrack(artist: "Band", title: "Song", album: "Record",
      familiar: false, reasons: [], artistKnown: true, upload: nil)])

    await model.createButtonTapped(batch)

    #expect(model.rows.first?.resolvedCandidate?.source == PlaylistSongSource.libraryUpload)
    #expect(model.destination == PlaylistCreateModel.Destination.create)
    await model.create()
    let saved = events.values
    #expect(saved.first?.musicID == "p.2")
    #expect(saved.first?.skipped == [PlaylistCreationSkippedSong(title: "Song", artist: "Band", reason: "not-found")])
  }

  private func readyDependencies(_ dependencies: inout DependencyValues) {
    dependencies.date.now = Date(timeIntervalSince1970: 1_000)
    dependencies.appleMusicCatalogClient.authorizationStatus = { .authorized }
    dependencies.appleMusicCatalogClient.subscriptionStatus = {
      AppleMusicSubscriptionStatus(canPlayCatalogContent: true, hasCloudLibraryEnabled: true)
    }
    dependencies.appleMusicCatalogClient.searchSongs = { _, _ in [] }
    dependencies.appleMusicCatalogClient.searchLibraryAlbums = { _ in [] }
    dependencies.appleMusicCatalogClient.libraryAlbumTracks = { _ in [] }
    dependencies.appleMusicCatalogClient.searchLibrarySongs = { _, _ in [] }
    dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, _ in
      CreatedPlaylistRef(id: "playlist", name: "Night Drive", trackCount: 1)
    }
    dependencies.appleMusicCatalogClient.appendToLibraryPlaylist = { _, _ in }
    dependencies.keepLibraryClient.libraryPlaylists = { [] }
    dependencies.playlistCreateSupportClient.readCreations = {
      PlaylistCreationsReadResult(events: [], skippedLines: 0, filesRead: 0)
    }
    dependencies.playlistCreateSupportClient.artistIdentity = { .empty }
    dependencies.playlistCreateSupportClient.appendCreation = { _ in }
  }

  private func playlist(tracks: [RecommendationTrack]? = nil) -> PlaylistShelfPlaylist {
    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 100), host: "Mac",
      playlist: "Night Drive", tracks: tracks ?? [track("Song")], description: "Late night songs")
    return PlaylistShelfPlaylist(id: "Mac|100", batch: batch, stagedDate: "today", songCount: batch.tracks.count,
      newSongCount: batch.tracks.count, songs: [])
  }

  private func track(_ title: String) -> RecommendationTrack {
    RecommendationTrack(artist: "Band", title: title, familiar: false, reasons: [], artistKnown: true)
  }

  private func candidate(id: String, title: String, source: PlaylistSongSource = .catalog) -> CatalogSongCandidate {
    CatalogSongCandidate(id: id, title: title, artistName: "Band", albumTitle: "Record", source: source)
  }
}

private actor MatchRecorder {
  private(set) var requests: [PlaylistRequest] = []
  func record(_ request: PlaylistRequest) { requests.append(request) }
}

private final class CreationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValues: [PlaylistCreationEvent] = []
  var values: [PlaylistCreationEvent] {
    lock.lock(); defer { lock.unlock() }; return storedValues
  }
  func append(_ event: PlaylistCreationEvent) {
    lock.lock(); defer { lock.unlock() }; storedValues.append(event)
  }
}

private actor LibraryPresence {
  private var reads = 0
  func next() -> [KeepLibraryPlaylist] {
    reads += 1
    return reads == 1 ? [] : [KeepLibraryPlaylist(id: "existing", name: "Night Drive")]
  }
}

private actor CreateCallRecorder {
  private(set) var count = 0
  func record() { count += 1 }
}
