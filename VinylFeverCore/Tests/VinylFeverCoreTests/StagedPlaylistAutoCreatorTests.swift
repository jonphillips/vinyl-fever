import Dependencies
import Foundation
import LLMHandoffKit
import Testing
import VinylFeverAppleMusic
import VinylFeverCore
import VinylFeverNotes

struct StagedPlaylistAutoCreatorTests {
  @Test func allCatalogMatchesCreateAndFileTheStagedPlaylist() async throws {
    let fixture = try Fixture()
    let recorder = AutoCreateRecorder()
    await withDependencies({ dependencies in fixture.setDependencies(&dependencies, recorder: recorder, statuses: { request in
      request.tracks.map { track in
        ResolvedPlaylistRow(request: track,
          status: .matched(CatalogSongCandidate(id: "id-\(track.index)", title: track.title, artistName: track.artist), score: 1))
      }
    }) }) {
      await StagedPlaylistAutoCreator().processInbox()
    }

    #expect(recorder.createdSongs.count == 2)
    #expect(recorder.appendedEvents.map(\.kind) == [.created])
    #expect(try fixture.inboxClient.list().isEmpty)
  }

  @Test func ambiguousMatchWritesNeedsReviewWithoutCreating() async throws {
    let fixture = try Fixture()
    let recorder = AutoCreateRecorder()
    await withDependencies({ dependencies in fixture.setDependencies(&dependencies, recorder: recorder, statuses: { request in
      request.tracks.enumerated().map { offset, track in
        if offset == 0 {
          return ResolvedPlaylistRow(request: track,
            status: .ambiguous([ScoredCandidate(candidate: CatalogSongCandidate(id: "one", title: track.title, artistName: track.artist), score: 1)]))
        }
        return ResolvedPlaylistRow(request: track,
          status: .matched(CatalogSongCandidate(id: "id-\(track.index)", title: track.title, artistName: track.artist), score: 1))
      }
    }) }) {
      await StagedPlaylistAutoCreator().processInbox()
    }

    #expect(recorder.createdSongs.isEmpty)
    #expect(recorder.appendedEvents.count == 1)
    #expect(recorder.appendedEvents.first?.kind == .needsReview)
    #expect(recorder.appendedEvents.first?.skipped?.map(\.reason) == ["ambiguous"])
    #expect(try fixture.inboxClient.list().count == 1)
  }

  @Test func stagedUploadRouteUsesLibraryUploadMatcher() async throws {
    let fixture = try Fixture()
    let recorder = AutoCreateRecorder()
    await withDependencies({ dependencies in
      fixture.setDependencies(&dependencies, recorder: recorder, statuses: { _ in
        Issue.record("Catalog matching must not run for an upload-routed track.")
        return []
      })
      dependencies.stagedPlaylistRouteClient.read = { _, _ in
        [
          RecommendationTrack(artist: "Artist One", title: "Song One", familiar: false, reasons: [], artistKnown: true, upload: true),
          RecommendationTrack(artist: "Artist Two", title: "Song Two", familiar: false, reasons: [], artistKnown: true, upload: false),
        ]
      }
      dependencies.catalogMatchResolver.resolve = { request, _ in
        request.tracks.map { track in
          ResolvedPlaylistRow(request: track,
            status: .matched(CatalogSongCandidate(id: "catalog-\(track.index)", title: track.title, artistName: track.artist), score: 1))
        }
      }
      dependencies.appleMusicCatalogClient.searchLibrarySongs = { term, _ in
        [LibrarySongCandidate(id: "upload-id", title: "Song One", artist: "Artist One", album: "Album", hasCatalogID: false)]
      }
    }) {
      await StagedPlaylistAutoCreator().processInbox()
    }

    #expect(recorder.createdSongs.map(\.source) == [.libraryUpload, .catalog])
    #expect(recorder.appendedEvents.first?.kind == .created)
  }

  @Test func existingLibraryNamePreventsCreationAndWriting() async throws {
    let fixture = try Fixture()
    let recorder = AutoCreateRecorder()
    await withDependencies({ dependencies in
      fixture.setDependencies(&dependencies, recorder: recorder, statuses: { request in
      request.tracks.map { track in
        ResolvedPlaylistRow(request: track,
          status: .matched(CatalogSongCandidate(id: "id-\(track.index)", title: track.title, artistName: track.artist), score: 1))
      }
      })
      dependencies.appleMusicCatalogClient.libraryPlaylistNames = { [fixture.name] }
    }) {
      await StagedPlaylistAutoCreator().processInbox()
    }

    #expect(recorder.createdSongs.isEmpty)
    #expect(recorder.appendedEvents.isEmpty)
    #expect(try fixture.inboxClient.list().count == 1)
  }

  @Test func playlistApiFailureRecordsErrorOnlyNeedsReview() async throws {
    let fixture = try Fixture()
    let recorder = AutoCreateRecorder()
    await withDependencies({ dependencies in
      fixture.setDependencies(&dependencies, recorder: recorder, statuses: { request in
      request.tracks.map { track in
        ResolvedPlaylistRow(request: track,
          status: .matched(CatalogSongCandidate(id: "id-\(track.index)", title: track.title, artistName: track.artist), score: 1))
      }
      })
      dependencies.appleMusicCatalogClient.createLibraryPlaylist = { _, _, _ in
        throw AppleMusicAPIError(statusCode: 503, detail: "unavailable")
      }
    }) {
      await StagedPlaylistAutoCreator().processInbox()
    }

    #expect(recorder.createdSongs.isEmpty)
    #expect(recorder.appendedEvents.count == 1)
    #expect(recorder.appendedEvents.first?.kind == .needsReview)
    #expect(recorder.appendedEvents.first?.skipped?.isEmpty == true)
    #expect(recorder.appendedEvents.first?.error?.contains("503") == true)
  }
}

private struct Fixture {
  let root: URL
  let name = "Staged Test Playlist"
  let inboxClient: PlaylistInboxClient
  let routes: [RecommendationTrack]

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let handoffInbox = HandoffInbox(root: root, fileExtension: "vfplaylist")
    let tracks = [
      #"{"artist":"Artist One","title":"Song One"}"#,
      #"{"artist":"Artist Two","title":"Song Two"}"#,
    ].joined(separator: ",")
    let contract = "VF-PLAYLIST: v1\n{\"name\":\"\(name)\",\"description\":\"Fixture\",\"tracks\":[\(tracks)]}"
    _ = try handoffInbox.stage(contract, slug: name, now: Date(timeIntervalSince1970: 1_800_000_000))
    inboxClient = PlaylistInboxClient.live(root: root, hostName: { "Mac" })
    routes = [
      RecommendationTrack(artist: "Artist One", title: "Song One", familiar: false, reasons: [], artistKnown: true, upload: false),
      RecommendationTrack(artist: "Artist Two", title: "Song Two", familiar: false, reasons: [], artistKnown: true, upload: false),
    ]
  }

  func setDependencies(
    _ values: inout DependencyValues,
    recorder: AutoCreateRecorder,
    statuses: @escaping @Sendable (PlaylistRequest) -> [ResolvedPlaylistRow]
  ) {
    values.playlistInboxClient = inboxClient
    values.stagedPlaylistRouteClient = StagedPlaylistRouteClient(read: { _, _ in routes })
    values.librarySnapshotStore.readAliases = { [:] }
    values.catalogMatchResolver.resolve = { request, _ in statuses(request) }
    values.appleMusicCatalogClient.authorizationStatus = { .authorized }
    values.appleMusicCatalogClient.subscriptionStatus = { .init(canPlayCatalogContent: true, hasCloudLibraryEnabled: true) }
    values.appleMusicCatalogClient.libraryPlaylistNames = { [] }
    values.appleMusicCatalogClient.createLibraryPlaylist = { name, _, songs in
      recorder.recordCreated(songs)
      return CreatedPlaylistRef(id: "music-id", name: name, trackCount: songs.count)
    }
    values.playlistCreationClient.read = { .init(events: recorder.appendedEvents, skippedLines: 0, filesRead: 1) }
    values.playlistCreationClient.append = { recorder.recordEvent($0) }
    values.date.now = Date(timeIntervalSince1970: 1_800_000_100)
  }
}

private final class AutoCreateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedSongs: [PlaylistSongReference] = []
  private var storedEvents: [PlaylistCreationEvent] = []

  var createdSongs: [PlaylistSongReference] { lock.withLock { storedSongs } }
  var appendedEvents: [PlaylistCreationEvent] { lock.withLock { storedEvents } }

  func recordCreated(_ songs: [PlaylistSongReference]) { lock.withLock { storedSongs = songs } }
  func recordEvent(_ event: PlaylistCreationEvent) { lock.withLock { storedEvents.append(event) } }
}
