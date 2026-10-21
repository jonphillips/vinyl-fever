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
    let candidates = ArtistAliasCandidateFinder.candidates(in: tracks)
    #expect(candidates.count == 1)
    #expect(candidates[0].variant == "elvis")
    #expect(candidates[0].canonical == "elvis presley")
    #expect(candidates[0].sharedTitles.count == 3)
    #expect(ArtistAliasCandidateFinder.candidates(in: tracks, decidedPairs: [ArtistAliasCandidateFinder.pair("elvis", "elvis presley")]).isEmpty)
  }

  @Test("structure candidates cover band suffixes, reordered words, joined words, and exclusions")
  func structuralFinder() throws {
    let tracks = [
      track("Nils Lofgren", "Song A"), track("Nils Lofgren Band", "Song B"),
      track("Liz Phair", "Song C"), track("Phair Liz", "Song D"),
      track("John Lennon", "Song E"), track("John Lennonplastic ono band", "Song F"),
      track("Elvis", "Song G"), track("Elvis Costello", "Song H"),
      track("Moby", "Song I"), track("Moby Grape", "Song J"),
      track("Billy Joel", "Song K"), track("Billy Joe", "Song L"),
      track("John Cougar Mellencamp", "Cougar Song"),
    ] + (1...5).map { track("John Mellencamp", "Solo Song \($0)") } + [
      track("Various", "Same"), track("Various Artists", "Same"),
      track("Soundtrack", "Same"), track("Cast Recording", "Same"),
      track("Original Cast Recording", "Same"),
    ]
    let pairs = Set(ArtistAliasCandidateFinder.candidates(in: tracks).map {
      ArtistAliasCandidateFinder.pair($0.variant, $0.canonical)
    })
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("nils lofgren", "nils lofgren band")))
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("liz phair", "phair liz")))
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("john lennon", "john lennonplastic ono band")))
    #expect(pairs.contains(ArtistAliasCandidateFinder.pair("john mellencamp", "john cougar mellencamp")))
    let mellencamp = try #require(ArtistAliasCandidateFinder.candidates(in: tracks).first {
      ArtistAliasCandidateFinder.pair($0.variant, $0.canonical)
        == ArtistAliasCandidateFinder.pair("john mellencamp", "john cougar mellencamp")
    })
    #expect(mellencamp.canonical == "john mellencamp")
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("elvis", "elvis costello")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("moby", "moby grape")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("billy joel", "billy joe")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("various", "various artists")))
    #expect(!pairs.contains(ArtistAliasCandidateFinder.pair("soundtrack", "cast recording")))
  }

  @Test("popular titles do not count as overlap and excluded names are omitted before indexing")
  func commonTitleOverlapIsIgnored() {
    let crowded = (1...4).flatMap { number in
      [track("Alpha Artist", "Rare Song \(number)"), track("Beta Artist", "Rare Song \(number)")]
    } + ["Amber", "Birch", "Cedar", "Drift", "Elm", "Flint"].flatMap { owner in
      (1...4).map { number in track("Other Artist \(owner) Song \(number)", "Rare Song \(number)") }
    }
    #expect(ArtistAliasCandidateFinder.candidates(in: crowded).isEmpty)
    let excluded = (1...4).flatMap { number in
      [track("Alpha Artist", "Distinctive Song \(number)"), track("Beta Artist", "Distinctive Song \(number)"), track("Various", "Distinctive Song \(number)")]
    }
    let excludedPairs = ArtistAliasCandidateFinder.candidates(in: excluded).map {
      ArtistAliasCandidateFinder.pair($0.variant, $0.canonical)
    }
    #expect(excludedPairs.contains(ArtistAliasCandidateFinder.pair("alpha artist", "beta artist")))
    #expect(!excludedPairs.contains(ArtistAliasCandidateFinder.pair("alpha artist", "various")))
  }

  @Test("candidate finder runs on the library-sized fixture")
  func candidateFinderPerformance() {
    let tracks = (0..<87_000).map { index in
      LibraryTrack(
        persistentID: "alias-load-\(index)", name: "Unique Track \(index)",
        artist: "Artist \(index % 8_000)")
    }
    let clock = ContinuousClock()
    let start = clock.now
    let candidates = ArtistAliasCandidateFinder.candidates(in: tracks)
    let duration = start.duration(to: clock.now)
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    print("Artist alias finder on 87,000 tracks / 8,000 keys: \(seconds)s, \(candidates.count) candidates")
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
    #expect(ArtistAliasesCodecError.newerVersion(2).errorDescription == "Update Vinyl Fever to read these artist aliases.")
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

    let reversePath = FileManager.default.temporaryDirectory
      .appending(path: "ArtistAliasReverseChain-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    let reverseDatabase = try VinylFeverDatabase.open(path: reversePath)
    try reverseDatabase.write { db in
      try ArtistAlias.decide(variant: "B Artist", canonical: "C Artist", accepted: true, in: db)
      try ArtistAlias.decide(variant: "A Artist", canonical: "B Artist", accepted: true, in: db)
    }
    rows = try reverseDatabase.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(ArtistAlias.acceptedMap(rows) == ["a artist": "c artist", "b artist": "c artist"])
  }

  @Test("rejections persist independently, do not delete acceptance, and accepting replaces rejection")
  func independentDecisions() throws {
    let path = FileManager.default.temporaryDirectory
      .appending(path: "ArtistAliasDecisions-\(UUID().uuidString).sqlite").path(percentEncoded: false)
    let database = try VinylFeverDatabase.open(path: path)
    try database.write { db in
      try ArtistAlias.decide(variant: "Elvis", canonical: "Presley", accepted: true, in: db)
      try ArtistAlias.decide(variant: "Elvis", canonical: "Costello", accepted: false, in: db)
      try ArtistAlias.decide(variant: "Elvis", canonical: "Aaron", accepted: false, in: db)
    }
    var rows = try database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(rows.count == 3)
    #expect(ArtistAlias.acceptedMap(rows) == ["elvis": "presley"])
    #expect(ArtistAlias.decidedPairs(rows).contains(ArtistAliasCandidateFinder.pair("elvis", "costello")))
    try database.write { db in try ArtistAlias.decide(variant: "Elvis", canonical: "Costello", accepted: true, in: db) }
    rows = try database.read { db in try ArtistAlias.all.fetchAll(db) }
    #expect(rows.count == 2)
    #expect(rows.contains { $0.variant == "elvis" && $0.canonical == "costello" && $0.decision == "accepted" })
  }

  private func track(_ artist: String, _ title: String) -> LibraryTrack {
    LibraryTrack(persistentID: UUID().uuidString, name: title, artist: artist, albumArtist: artist, album: "Album")
  }
}
