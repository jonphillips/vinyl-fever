import Foundation
import Testing
import VinylFeverCore

@Suite("Library snapshot and index")
struct LibrarySnapshotTests {
  private var date: Date { ISO8601DateFormatter().date(from: "2026-10-15T21:40:00Z")! }
  private var fixture: [LibraryTrack] {
    var tracks: [LibraryTrack] = []
    for index in 0..<30 {
      let artist = index == 0 ? "Beyoncé" : "Artist \(index % 3)"
      let title = index == 0 ? "Café Song feat. Guest" : "Song \(index)"
      let genre = index.isMultiple(of: 2) ? "Rock" : "Jazz"
      let lastPlayed = index.isMultiple(of: 2) ? date : nil
      let availability: LibraryAvailability = index == 0 ? .uploaded : .subscription
      tracks.append(
        LibraryTrack(
          persistentID: "id-\(index)", name: title, artist: artist, albumArtist: artist,
          album: "Album \(index % 4)", genre: genre, year: 1980 + index, playCount: index,
          favorited: index.isMultiple(of: 5),
          dateAdded: date.addingTimeInterval(Double(index) * 60),
          lastPlayed: lastPlayed, availability: availability))
    }
    return tracks
  }

  @Test("codec preserves fields and reports newer versions with a typed error")
  func codec() throws {
    let snapshot = LibrarySnapshot(generatedAt: date, tracks: fixture)
    let data = try LibrarySnapshotCodec.encode(snapshot)
    let decoded = try LibrarySnapshotCodec.decode(data)
    #expect(decoded == snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["lastfm"] is NSNull)
    let future = try JSONSerialization.data(withJSONObject: [
      "format": LibrarySnapshot.formatName, "version": 2,
    ])
    do {
      _ = try LibrarySnapshotCodec.decode(future)
      Issue.record("Expected newer-version error")
    } catch let error as LibrarySnapshotCodecError {
      #expect(error == .newerVersion(2))
    }
  }

  @Test("index caps, combines search filters, and checks featuring credits and diacritics")
  func queriesAndChecks() {
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: date, tracks: fixture))
    #expect(index.topTracks(by: .plays, limit: 500).count == fixture.count)
    #expect(index.topTracks(by: .plays, limit: 0).count == 1)
    #expect(index.topTracks(by: .plays, limit: 2).map(\.playCount) == [29, 28])
    #expect(index.topTracks(by: .favorites).first?.favorited == true)
    #expect(index.topTracks(by: .recentlyAdded).first?.persistentID == "id-29")
    #expect(index.topTracks(by: .recentlyPlayed).first?.lastPlayed == date)
    #expect(index.topArtists(by: .plays).first?.plays == 155)
    #expect(index.topArtists(by: .favorites).first?.favorites == 2)
    #expect(index.topArtists(by: .recentlyAdded).first?.artist == "Artist 2")
    #expect(index.topArtists(by: .recentlyPlayed).first?.lastPlayed == date)
    var filter = LibrarySearchFilter()
    filter.genre = "rock"
    filter.yearFrom = 1980
    filter.yearTo = 1984
    filter.minPlays = 2
    #expect(index.search(filter, sort: .title).map(\.playCount) == [2, 4])
    let checked = index.checkTracks([
      (artist: "Beyonce", title: "Cafe Song"), (artist: "Missing", title: "Song"),
    ])
    #expect(checked.first?.owned == true)
    #expect(checked.first?.availability == [.uploaded])
    #expect(checked.last?.owned == false)
  }

  @Test("profile counts uploaded library-only tracks and annotations represent all states")
  func profilesAndAnnotations() {
    let tracks =
      fixture + [
        LibraryTrack(
          persistentID: "second-version", name: "Cafe Song", artist: "Beyonce", playCount: 7,
          favorited: true)
      ]
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: date, tracks: tracks))
    let profile = index.artistProfile("Beyoncé")
    #expect(profile?.uploadedTrackCount == 1)
    #expect(profile?.trackCount == 2)
    let checked = index.checkTracks([(artist: "Beyonce", title: "Cafe Song")]).first
    #expect(checked?.plays == 7)
    #expect(checked?.versionCount == 2)
    #expect(
      index.annotation(artist: "Beyonce", title: "Cafe Song")
        == .inLibrary(plays: 7, lastPlayed: date, favorited: true, versionCount: 2))
    #expect(index.annotation(artist: "Missing", title: "Song") == .notInLibrary)
    #expect(
      index.annotation(artist: "Missing", title: "Song", snapshotAvailable: false)
        == .snapshotUnavailable)
  }
}
