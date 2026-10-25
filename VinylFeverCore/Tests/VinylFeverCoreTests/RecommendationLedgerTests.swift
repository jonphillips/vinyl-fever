import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct RecommendationLedgerTests {
  @Test("JSONL round-trips and tolerates blank lines, unsupported records, partial tails and no final newline")
  func ledgerCodec() throws {
    let instant = Date(timeIntervalSince1970: 1_800_000_000)
    let batch = RecommendationBatch(recordedAt: instant, host: "Jon MBP", playlist: "Power Pop",
      tracks: [RecommendationTrack(artist: "The Records", title: "Starry Eyes", album: "Shades in Bed",
        year: 1979, familiar: false, reasons: [], artistKnown: true)])
    let encoded = try RecommendationLedgerCodec.encode(batch)
    let decoded = RecommendationLedgerCodec.readFiles([encoded])
    #expect(decoded.batches == [batch])
    let validWithoutNewline = Data(encoded.dropLast())
    let unsupported = Data(#"{"format":"vf-recommendation-batch","version":2}"#.utf8)
    let stream = Data((String(decoding: validWithoutNewline, as: UTF8.self) + "\n\n" +
      String(decoding: unsupported, as: UTF8.self) + "\n{\"partial\":").utf8)
    let result = RecommendationLedgerCodec.readFiles([stream])
    #expect(result.batches == [batch])
    #expect(result.skippedLines == 1)
  }

  @Test("familiarity records each evidence source and excludes ignored and followed playlists")
  func familiarityEvidence() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let track = LibraryTrack(persistentID: "owned", name: "Known Song", artist: "Known Artist")
    let playlists = [
      LibraryPlaylist(persistentID: "curated", name: "Curated", kind: .user, members: ["outside"]),
      LibraryPlaylist(persistentID: "unlabeled", name: "Unlabeled", kind: .user, members: ["outside"]),
      LibraryPlaylist(persistentID: "ignore", name: "Ignore", kind: .user, members: ["outside"]),
      LibraryPlaylist(persistentID: "followed", name: "Followed", kind: .user, members: ["outside"]),
    ]
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [track], playlists: playlists,
      outsideTracks: ["outside": LibraryOutsideTrack(name: "Discovery", artist: "Known Artist", album: "Album")])
    let roles = PlaylistRoles(updatedAt: now, playlists: [
      PlaylistRoleEntry(persistentID: "curated", name: "Curated", role: .curated),
      PlaylistRoleEntry(persistentID: "ignore", name: "Ignore", role: .ignore),
      PlaylistRoleEntry(persistentID: "followed", name: "Followed", role: .followed),
    ])
    let index = LibraryIndex(snapshot: snapshot)
    let playlistIndex = PlaylistIndex(snapshot: snapshot, roles: roles, identity: index.artistIdentity)
    let empty = RecommendationLedgerReadResult(batches: [], skippedLines: 0)

    let owned = RecommendationFamiliarity.evaluate(artist: "Known Artist", title: "Known Song",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(owned.reasons == ["owned"])
    #expect(owned.familiar)

    let inPlaylist = RecommendationFamiliarity.evaluate(artist: "Known Artist", title: "Discovery",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(inPlaylist.reasons == ["playlist:curated", "playlist:unlabeled"])
    #expect(inPlaylist.artistKnown)

    let notedKey = TasteIntelligence.songKey(artist: "Known Artist", title: "Discovery", identity: index.artistIdentity)
    let prior = RecommendationBatch(recordedAt: now.addingTimeInterval(-10), host: "Mac",
      playlist: "Earlier", tracks: [RecommendationTrack(artist: "Known Artist", title: "Discovery",
        familiar: false, reasons: [], artistKnown: true)])
    let annotated = RecommendationFamiliarity.evaluate(artist: "Known Artist", title: "Discovery",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [notedKey], ledger: RecommendationLedgerReadResult(batches: [prior], skippedLines: 0),
      recordedAt: now)
    #expect(annotated.reasons == ["playlist:curated", "playlist:unlabeled", "noted", "recommended"])

    let noteOnlyKey = TasteIntelligence.songKey(artist: "New Artist", title: "Noted Song", identity: index.artistIdentity)
    let notedOnly = RecommendationFamiliarity.evaluate(artist: "New Artist", title: "Noted Song",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [noteOnlyKey], ledger: empty, recordedAt: now)
    #expect(notedOnly.reasons == ["noted"])
    #expect(!notedOnly.artistKnown)

    let recommendedOnly = RecommendationFamiliarity.evaluate(artist: "New Artist", title: "Prior Find",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: RecommendationLedgerReadResult(batches: [
        RecommendationBatch(recordedAt: now.addingTimeInterval(-10), host: "Mac", playlist: "Earlier",
          tracks: [RecommendationTrack(artist: "New Artist", title: "Prior Find", familiar: false,
            reasons: [], artistKnown: false)]),
      ], skippedLines: 0), recordedAt: now)
    #expect(recommendedOnly.reasons == ["recommended"])

    let unknownSongByKnownArtist = RecommendationFamiliarity.evaluate(artist: "Known Artist", title: "New Song",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(!unknownSongByKnownArtist.familiar)
    #expect(unknownSongByKnownArtist.artistKnown)
  }

  @Test("heard familiarity uses only listening starts before the record time")
  func heardBeforeRecordedAt() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let poller = UUID()
    let fetch = ListeningFetch(poller: poller, host: "Fixture", fetchedAt: now.addingTimeInterval(-20),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [
        ListeningItem(kind: .song, id: "private", title: "Heard Song", artist: "Heard Artist"),
      ])
    let log = ListeningLog(streams: [[fetch]], now: now,
      identity: ArtistIdentity(knownArtists: ["Heard Artist"]))
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [])
    let index = LibraryIndex(snapshot: snapshot)
    let empty = RecommendationLedgerReadResult(batches: [], skippedLines: 0)
    let before = RecommendationFamiliarity.evaluate(artist: "Heard Artist", title: "Heard Song",
      snapshot: snapshot, index: index, playlistIndex: PlaylistIndex(snapshot: snapshot,
        roles: PlaylistRoles(updatedAt: now, playlists: []), identity: index.artistIdentity),
      listeningLog: log, tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(before.reasons == ["heard"])
    let after = RecommendationFamiliarity.evaluate(artist: "Heard Artist", title: "Heard Song",
      snapshot: snapshot, index: index, playlistIndex: PlaylistIndex(snapshot: snapshot,
        roles: PlaylistRoles(updatedAt: now, playlists: []), identity: index.artistIdentity),
      listeningLog: log, tasteNoteKeys: [], ledger: empty, recordedAt: now.addingTimeInterval(-30))
    #expect(after.reasons.isEmpty)
  }

  @Test("recommended evidence counts batches with unfamiliar entries and returns the latest date")
  func recommendationEvidence() {
    let identity = ArtistIdentity(knownArtists: ["Artist"])
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    let recent = old.addingTimeInterval(60)
    let familiar = RecommendationTrack(artist: "Artist", title: "Song", familiar: true,
      reasons: ["owned"], artistKnown: true)
    let unfamiliar = RecommendationTrack(artist: "Artist", title: "Song", familiar: false,
      reasons: [], artistKnown: true)
    let other = RecommendationTrack(artist: "Artist", title: "Other", familiar: false,
      reasons: [], artistKnown: true)
    let ledger = RecommendationLedgerReadResult(batches: [
      RecommendationBatch(recordedAt: old, host: "Mac", playlist: "One", tracks: [familiar, unfamiliar]),
      RecommendationBatch(recordedAt: recent, host: "Mini", playlist: "Two", tracks: [unfamiliar, other]),
    ], skippedLines: 0)
    #expect(RecommendationLedgerEvidence.forSong(artist: "Artist", title: "Song", identity: identity,
      ledger: ledger) == RecommendationEvidence(count: 2, latestRecordedAt: recent))
    #expect(RecommendationLedgerEvidence.forSong(artist: "Artist", title: "Missing", identity: identity,
      ledger: ledger) == nil)
  }
}
