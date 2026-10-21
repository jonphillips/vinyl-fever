import Foundation
import SQLiteData
import Testing
import VinylFeverCore

@Suite(.serialized)
struct ArtistAliasTests {
  @Test("title overlap candidates carry counts, evidence, direction, and hide decisions")
  func overlapFinder() {
    let tracks = (1...4).flatMap { number in
      [
        track("Elvis", "Song \(number)"),
        track("Elvis Presley", "Song \(number)"),
      ]
    } + (5...8).map { track("Elvis Presley", "Solo \($0)") }
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: .now, tracks: tracks))
    let candidates = ArtistAliasCandidateFinder.candidates(in: index)
    #expect(candidates.count == 1)
    #expect(candidates[0].variant == "elvis")
    #expect(candidates[0].canonical == "elvis presley")
    #expect(candidates[0].sharedTitles.count == 3)
    #expect(ArtistAliasCandidateFinder.candidates(in: index, decidedPairs: [ArtistAliasCandidateFinder.pair("elvis", "elvis presley")]).isEmpty)
  }

  @Test("structure candidates cover band suffixes, reordered words, joined words, and exclusions")
  func structuralFinder() {
    let tracks = [
      track("Nils Lofgren", "Song A"), track("Nils Lofgren Band", "Song B"),
      track("Liz Phair", "Song C"), track("Phair Liz", "Song D"),
      track("John Lennon", "Song E"), track("John Lennonplastic", "Song F"),
      track("Various", "Same"), track("Various Artists", "Same"),
      track("Soundtrack", "Same"), track("Cast Recording", "Same"),
      track("Original Cast Recording", "Same"),
    ]
    let index = LibraryIndex(snapshot: LibrarySnapshot(generatedAt: .now, tracks: tracks))
    let pairs = Set(ArtistAliasCandidateFinder.candidates(in: index).map {
      ArtistAliasCandidateFinder.pair($0.variant, $0.canonical)
    })
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("nils lofgren", "nils lofgren band")))
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("liz phair", "phair liz")))
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("john lennon", "john lennonplastic")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("various", "various artists")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("soundtrack", "cast recording")))
  }

  @Test("alias export round trips and rejects unknown formats and versions")
  func aliasesCodec() throws {
    let aliases = ["john cougar mellencamp": "john mellencamp"]
    #expect(try ArtistAliasesCodec.decode(ArtistAliasesCodec.encode(aliases)) == aliases)
    let wrongFormat = Data(#"{"format":"other","version":1,"aliases":{}}"#.utf8)
    #expect(throws: ArtistAliasesCodecError.unsupportedFormat("other")) {
      try ArtistAliasesCodec.decode(wrongFormat)
    }
    let future = Data(#"{"format":"vf-artist-aliases","version":2,"aliases":{}}"#.utf8)
    #expect(throws: ArtistAliasesCodecError.newerVersion(2)) {
      try ArtistAliasesCodec.decode(future)
    }
  }

  @Test("accepted aliases collapse chains, repoint aliases, reject self aliases, and undo")
  func aliasStore() throws {
    let path = FileManager.default.temporaryDirectory
      .appending(path: "ArtistAliases-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    let database = try VinylFeverDatabase.open(path: path)
    let decidedAt = Date(timeIntervalSince1970: 1_800_000_000)
    try database.write { db in
      try ArtistAlias.decide(variant: "A Artist", canonical: "B Artist", accepted: true, now: decidedAt, in: db)
      try ArtistAlias.decide(variant: "B Artist", canonical: "C Artist", accepted: true, now: decidedAt, in: db)
    }
    var rows = try database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(ArtistAlias.acceptedMap(rows) == ["a artist": "c artist", "b artist": "c artist"])
    #expect(ArtistAlias.decidedPairs(rows).contains(ArtistAliasCandidateFinder.pair("a artist", "b artist")))
    try database.write { db in try ArtistAlias.decide(variant: "C Artist", canonical: "C Artist", accepted: true, in: db) }
    rows = try database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(rows.count == 2)
    try database.write { db in try ArtistAlias.undo("B Artist", in: db) }
    rows = try database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(ArtistAlias.acceptedMap(rows) == ["a artist": "c artist"])
  }

  private func track(_ artist: String, _ title: String) -> LibraryTrack {
    LibraryTrack(persistentID: UUID().uuidString, name: title, artist: artist, albumArtist: artist, album: "Album")
  }
}
