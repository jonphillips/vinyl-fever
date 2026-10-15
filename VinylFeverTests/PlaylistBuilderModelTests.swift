import Dependencies
import Foundation
import Testing
import VinylFeverCore

@testable import VinylFever

@MainActor
@Suite("Playlist builder model")
struct PlaylistBuilderModelTests {
  @Test("a valid paste resolves rows; malformed paste makes no catalog searches")
  func validAndMalformedPaste() async {
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(search: { term, _ in
        [Self.candidate(id: term, title: "Starry Eyes")]
      })
      $0.catalogMatchResolver.resolve = { request in
        request.tracks.map { ResolvedPlaylistRow(request: $0, status: .matched(Self.candidate(id: "song", title: $0.title), score: 0.9)) }
      }
    } operation: { PlaylistBuilderModel() }
    model.pastedText = validPaste
    await model.resolve()
    #expect(model.playlistName == "Test Mix")
    #expect(model.rows.count == 1)
    #expect(model.decodeError == nil)

    let searchCounter = SearchCallCounter()
    let malformed = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(search: { _, _ in
        await searchCounter.record()
        return []
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    malformed.pastedText = "not a playlist"
    await malformed.resolve()
    #expect(malformed.decodeError != nil)
    #expect(await searchCounter.count == 0)
  }

  @Test("candidate selection resolves an ambiguous row")
  func candidateSelection() {
    let first = Self.candidate(id: "one", title: "Song")
    let second = Self.candidate(id: "two", title: "Song")
    let track = TrackRequest(index: 1, artist: "Artist", title: "Song")
    let model = PlaylistBuilderModel()
    model.rows = [ResolvedPlaylistRow(request: track, status: .ambiguous([
      ScoredCandidate(candidate: first, score: 0.8), ScoredCandidate(candidate: second, score: 0.7),
    ]))]
    model.selectCandidate(second, for: 1)
    #expect(model.rows[0].status == .matched(second, score: 0.9))
  }

  @Test("create requires a match and sends the edited name and only matched IDs in order")
  func createUsesMatchedRows() async {
    let capture = PlaylistCreateCapture()
    let first = Self.candidate(id: "first", title: "First")
    let model = withDependencies {
      $0.appleMusicCatalogClient = authorizedClient(create: { name, description, ids in
        await capture.record(name: name, description: description, ids: ids)
        return CreatedPlaylistRef(id: "playlist-1", name: name, trackCount: ids.count)
      })
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let firstRow = TrackRequest(index: 1, artist: "Artist", title: "First")
    let secondRow = TrackRequest(index: 2, artist: "Artist", title: "Second")
    model.rows = [
      ResolvedPlaylistRow(request: firstRow, status: .matched(first, score: 0.9)),
      ResolvedPlaylistRow(request: secondRow, status: .notFound(error: nil)),
    ]
    #expect(model.canCreate)
    model.playlistName = "Edited name"
    model.playlistDescription = "  "
    await model.createPlaylist()
    let received = await capture.value
    #expect(received?.0 == "Edited name")
    #expect(received?.1 == nil)
    #expect(received?.2 == ["first"])
    #expect(model.createdTrackIndexes == [1])
  }

  @Test("a row fixed after creation appends to the new playlist and leaves the table")
  func addsPreviouslyUnresolvedRow() async {
    let appendCapture = PlaylistAppendCapture()
    let client = authorizedClient(append: { id, ids in await appendCapture.record(id: id, ids: ids) })
    let model = withDependencies {
      $0.appleMusicCatalogClient = client
      $0.catalogMatchResolver.resolve = { _ in [] }
    } operation: { PlaylistBuilderModel() }
    let track = TrackRequest(index: 8, artist: "Artist", title: "Recovered")
    model.rows = [ResolvedPlaylistRow(request: track, status: .matched(Self.candidate(id: "recovered", title: "Recovered"), score: 0.9))]
    model.createdPlaylist = CreatedPlaylistRef(id: "library-id", name: "Mix", trackCount: 1)
    await model.addToCreatedPlaylist(trackIndex: 8)
    let appended = await appendCapture.value
    #expect(appended?.0 == "library-id")
    #expect(appended?.1 == ["recovered"])
    #expect(model.visibleRows.isEmpty)
    #expect(model.createdPlaylist?.trackCount == 2)
  }

  @Test("authorization, subscription, and Sync Library gates block resolve")
  func gatesBlockResolution() async {
    for (client, expected) in [
      (authorizedClient(authorization: .denied), PlaylistGate.notAuthorized),
      (authorizedClient(subscription: .init(canPlayCatalogContent: false, hasCloudLibraryEnabled: true)), .noSubscription),
      (authorizedClient(subscription: .init(canPlayCatalogContent: true, hasCloudLibraryEnabled: false)), .cloudLibraryOff),
    ] {
      let model = withDependencies {
        $0.appleMusicCatalogClient = client
        $0.catalogMatchResolver.resolve = { _ in [] }
      } operation: { PlaylistBuilderModel() }
      model.pastedText = validPaste
      await model.resolve()
      #expect(model.gate == expected)
      #expect(model.rows.isEmpty)
    }
  }

  private var validPaste: String {
    "VF-PLAYLIST: v1\n{\"name\":\"Test Mix\",\"tracks\":[{\"artist\":\"The Records\",\"title\":\"Starry Eyes\"}]}"
  }

  private func authorizedClient(
    authorization: MusicKitAuthorization = .authorized,
    subscription: AppleMusicSubscriptionStatus = .init(canPlayCatalogContent: true, hasCloudLibraryEnabled: true),
    search: @escaping @Sendable (String, Int) async throws -> [CatalogSongCandidate] = { _, _ in [] },
    create: @escaping @Sendable (String, String?, [String]) async throws -> CreatedPlaylistRef = { name, _, ids in
      CreatedPlaylistRef(id: "playlist", name: name, trackCount: ids.count)
    },
    append: @escaping @Sendable (String, [String]) async throws -> Void = { _, _ in }
  ) -> AppleMusicCatalogClient {
    AppleMusicCatalogClient(
      authorizationStatus: { authorization },
      requestAuthorization: { authorization },
      subscriptionStatus: { subscription },
      searchSongs: search,
      createLibraryPlaylist: create,
      appendToLibraryPlaylist: append
    )
  }

  nonisolated private static func candidate(id: String, title: String) -> CatalogSongCandidate {
    CatalogSongCandidate(id: id, title: title, artistName: "The Records")
  }
}

private actor SearchCallCounter {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor PlaylistCreateCapture {
  private(set) var value: (String, String?, [String])?
  func record(name: String, description: String?, ids: [String]) {
    value = (name, description, ids)
  }
}

private actor PlaylistAppendCapture {
  private(set) var value: (String, [String])?
  func record(id: String, ids: [String]) { value = (id, ids) }
}
