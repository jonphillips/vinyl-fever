import Foundation
import Testing
import VinylFeverCore

@Suite("Library snapshot and index")
struct LibrarySnapshotTests {
  private var date: Date { ISO8601DateFormatter().date(from: "2026-10-15T21:40:00Z")! }
  private var fixture: [LibraryTrack] { LibraryTestFixtures.tracks(date: date) }

  @Test("codec writes fractional-second dates and reads whole-second ones")
  func codecDateForms() throws {
    let fractional = Date(timeIntervalSince1970: 1_700_000_000.25)
    let data = try LibrarySnapshotCodec.encode(LibrarySnapshot(generatedAt: fractional, tracks: []))
    #expect(String(decoding: data, as: UTF8.self).contains(#""2023-11-14T22:13:20.250Z""#))
    #expect(try LibrarySnapshotCodec.decode(data).generatedAt == fractional)
    let whole = Data(
      #"{"format":"vf-library-snapshot","version":1,"generatedAt":"2026-10-15T21:40:00Z","trackCount":0,"tracks":[],"lastfm":null}"#
        .utf8)
    #expect(try LibrarySnapshotCodec.decode(whole).generatedAt == date)
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

  @Test("overview trims and caps genre counts and ignores implausible decades")
  func overviewBounds() {
    var tracks = (0..<30).map { index in
      LibraryTrack(
        persistentID: "genre-\(index)", name: "Song \(index)", artist: "Artist \(index)",
        genre: index == 0 ? "  " : "Genre \(index)", year: index == 1 ? 199 : 1980 + index)
    }
    tracks[2].genre = "  Trimmed Genre  "
    tracks.append(LibraryTrack(persistentID: "genre-duplicate", name: "Duplicate", artist: "Artist", genre: "Trimmed Genre"))
    let overview = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: date, tracks: tracks))
      .overview(generatedAt: date)
    #expect(overview.genreCounts.count == 25)
    #expect(overview.genreCounts["Trimmed Genre"] == 2)
    #expect(!overview.genreCounts.keys.contains(""))
    #expect(!overview.decadeCounts.keys.contains(190))
    #expect(overview.decadeCounts.values.reduce(0, +) == 29)
  }

  @Test("library matching strips remasters and feature credits without stripping with")
  func libraryTitleMatching() {
    let tracks = [
      LibraryTrack(
        persistentID: "1", name: "Starry Eyes (2005 Remaster)", artist: "The Records", playCount: 3),
      LibraryTrack(
        persistentID: "2", name: "Smooth (feat. Rob Thomas)", artist: "Santana", playCount: 5),
      LibraryTrack(
        persistentID: "3", name: "Uptown Funk (feat. Bruno Mars)", artist: "Mark Ronson",
        playCount: 7),
      LibraryTrack(
        persistentID: "4", name: "Stuck with You", artist: "Huey Lewis and the News", playCount: 11),
      LibraryTrack(
        persistentID: "5", name: "Dancing with Myself", artist: "Billy Idol", playCount: 13),
      LibraryTrack(
        persistentID: "6", name: "Live with Me", artist: "The Rolling Stones", playCount: 17),
    ]
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: date, tracks: tracks))
    let results = index.checkTracks([
      (artist: "The Records", title: "Starry Eyes"),
      (artist: "Santana", title: "Smooth"),
      (artist: "Mark Ronson", title: "Uptown Funk"),
      (artist: "Huey Lewis and the News", title: "Stuck with You"),
      (artist: "Billy Idol", title: "Dancing"),
      (artist: "The Rolling Stones", title: "Live"),
    ])
    #expect(results.map(\.owned) == [true, true, true, true, false, false])
    #expect(results[3].versionCount == 1)
    #expect(results[3].plays == 11)
    #expect(
      index.annotation(
        artist: "Other Artist", title: "Smooth", candidateArtist: "Santana",
        candidateTitle: "Smooth (feat. Rob Thomas)")
        == .inLibrary(plays: 5, lastPlayed: nil, favorited: false, versionCount: 1))
  }

  @Test("bulk-column projection maps Music enums and tolerates optional values")
  func bulkColumnProjection() throws {
    let mapping: [(String, LibraryAvailability)] = [
      ("kSub", .subscription), ("kPur", .purchased), ("kMat", .matched),
      ("kUpl", .uploaded), ("kUpP", .uploaded), ("kRej", .uploaded), ("zzzz", .other),
    ]
    for (code, expected) in mapping {
      var columns = requiredColumns
      columns["cloudStatus"] = [NSNumber(value: fourCC(code))]
      let track = try LibraryTrack(bulkColumns: columns, index: 0)
      #expect(track.availability == expected)
    }

    var columns = requiredColumns
    columns["cloudStatus"] = ["uploaded"]
    columns["year"] = [NSNumber(value: 0)]
    columns["genre"] = [NSNull()]
    columns["favorited"] = [NSNumber(value: true)]
    let track = try LibraryTrack(bulkColumns: columns, index: 0)
    #expect(track.availability == .uploaded)
    #expect(track.year == nil)
    #expect(track.genre == nil)
    #expect(track.favorited)
    #expect(track.rating == nil)

    columns.removeValue(forKey: "name")
    do {
      _ = try LibraryTrack(bulkColumns: columns, index: 0)
      Issue.record("Expected missing required field error")
    } catch let error as LibraryTrack.BulkColumnsError {
      #expect(error == .missingRequiredField("name", index: 0))
    }
  }

  private var requiredColumns: [String: [Any]] {
    ["persistentID": ["id"], "name": ["Song"], "artist": ["Artist"]]
  }

  private func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
  }
}
