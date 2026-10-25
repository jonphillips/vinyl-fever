import Foundation
import Testing
@testable import VinylFeverListening

@Suite("New Music exposure codec")
struct NewMusicExposureCodecTests {
  @Test("blank lines and an unterminated partial tail are ignored")
  func blankAndPartialTail() throws {
    let week = try NewMusicExposureCodec.encode(sampleWeek())
    var data = Data("\n".utf8)
    data.append(week)
    data.append(Data("{\"format\":\"unfinished".utf8))
    let result = NewMusicExposureCodec.decodeJSONLReport(data)
    #expect(result.records.count == 1)
    #expect(result.skippedLines == 0)
  }

  @Test("unknown versions and malformed complete lines are counted and skipped")
  func skipsUnknownAndMalformed() {
    let data = Data("{\"format\":\"vf-new-music-week\",\"version\":2}\nnot-json\n".utf8)
    let result = NewMusicExposureCodec.decodeJSONLReport(data)
    #expect(result.records.isEmpty)
    #expect(result.skippedLines == 2)
  }

  @Test("gap lines decode")
  func gapLine() throws {
    let data = try NewMusicExposureCodec.encode(NewMusicExposureGap(
      fetchedAt: Date(timeIntervalSince1970: 1_800_000_000), host: "Mini", detail: "offline"))
    let result = NewMusicExposureCodec.decodeJSONLReport(data)
    #expect(result.records.count == 1)
    if case .gap = result.records[0] {} else { Issue.record("Expected gap record") }
  }

  @Test("duplicate weeks across host files keep the newest fetch")
  func deDuplicatesAcrossFiles() throws {
    let first = try NewMusicExposureCodec.encode(sampleWeek(fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)))
    let second = try NewMusicExposureCodec.encode(sampleWeek(fetchedAt: Date(timeIntervalSince1970: 1_800_000_100)))
    let result = NewMusicExposureCodec.readFiles([first, second])
    #expect(result.records.count == 1)
    #expect(result.records[0].fetchedAt == Date(timeIntervalSince1970: 1_800_000_100))
  }

  @Test("library playlist parser uses exact New Music and exposes the next page")
  func resolvesNewMusicFromSecondPageGlobalID() throws {
    let request = try NewMusicCatalogClient.libraryPlaylistsRequest()
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "limit", value: "100")])
    let page1 = Data(#"{"data":[{"attributes":{"name":"New Music Daily","playParams":{"globalId":"wrong"}}}],"next":"/v1/me/library/playlists?offset=1"}"#.utf8)
    let page2 = Data(#"{"data":[{"attributes":{"name":"New Music","playParams":{"globalId":"pl.pm-real"}}}]}"#.utf8)
    let first = try NewMusicCatalogParser.libraryPlaylists(page1)
    let second = try NewMusicCatalogParser.libraryPlaylists(page2)
    #expect(first.catalogID == nil)
    #expect(first.next == "/v1/me/library/playlists?offset=1")
    #expect(second.catalogID == "pl.pm-real")
    #expect(try NewMusicCatalogParser.endpointURL(first.next!).host == "api.music.apple.com")
  }

  @Test("catalog tracks parse and follow relative next values")
  func catalogTracksFollowRelativeNext() throws {
    let data = Data(#"{"data":[{"id":"song-1","type":"songs","attributes":{"name":"Song","artistName":"Artist"}}],"next":"/v1/catalog/us/playlists/pl.pm-real/tracks?offset=1"}"#.utf8)
    let page = try NewMusicCatalogParser.catalogTracks(data)
    #expect(page.tracks.map(\.catalogID) == ["song-1"])
    #expect(try NewMusicCatalogParser.endpointURL(page.next!).absoluteString == "https://api.music.apple.com/v1/catalog/us/playlists/pl.pm-real/tracks?offset=1")
    let request = try NewMusicCatalogClient.catalogPlaylistRequest(storefront: "us", catalogID: "pl.pm-real")
    #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "include", value: "tracks")])
  }

  @Test("cached catalog 404 triggers one resolution and a retry")
  func staleCachedCatalogIDIsReResolved() async throws {
    let attempts = CallCounter()
    let invalidated = CallFlag()
    let result = try await NewMusicCatalogClient.fetchWithRecovery(cachedCatalogID: "old",
      resolve: { "fresh" }, load: { id in
        let count = await attempts.next()
        if id == "old" { throw NewMusicExposureError.staleCatalogID }
        #expect(id == "fresh")
        #expect(count == 2)
        return NewMusicCatalogWeek(lastModifiedDate: Date(timeIntervalSince1970: 100), tracks: [])
      }, cache: { _ in }, invalidate: { invalidated.set() })
    #expect(result.tracks.isEmpty)
    #expect(invalidated.value)
  }

  private func sampleWeek(fetchedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> NewMusicWeek {
    NewMusicWeek(lastModifiedDate: Date(timeIntervalSince1970: 1_799_900_000), fetchedAt: fetchedAt,
      host: "Mini", tracks: [NewMusicTrack(catalogID: "one", title: "One", artist: "Artist")])
  }
}

private actor CallCounter {
  private var value = 0
  func next() -> Int { value += 1; return value }
}

private final class CallFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var stored = false
  var value: Bool { lock.withLock { stored } }
  func set() { lock.withLock { stored = true } }
}
