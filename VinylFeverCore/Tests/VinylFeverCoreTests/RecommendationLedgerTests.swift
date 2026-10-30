import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct RecommendationLedgerTests {
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

    let owned = evaluate(artist: "Known Artist", title: "Known Song",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(owned.reasons == ["owned"])
    #expect(owned.familiar)

    let inPlaylist = evaluate(artist: "Known Artist", title: "Discovery",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(inPlaylist.reasons == ["playlist:curated", "playlist:unlabeled"])
    #expect(inPlaylist.artistKnown)

    let notedKey = TasteIntelligence.songKey(artist: "Known Artist", title: "Discovery", identity: index.artistIdentity)
    let prior = RecommendationBatch(recordedAt: now.addingTimeInterval(-10), host: "Mac",
      playlist: "Earlier", tracks: [RecommendationTrack(artist: "Known Artist", title: "Discovery",
        familiar: false, reasons: [], artistKnown: true)])
    let annotated = evaluate(artist: "Known Artist", title: "Discovery",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [notedKey], ledger: RecommendationLedgerReadResult(batches: [prior], skippedLines: 0),
      recordedAt: now)
    #expect(annotated.reasons == ["playlist:curated", "playlist:unlabeled", "noted", "recommended"])

    let noteOnlyKey = TasteIntelligence.songKey(artist: "New Artist", title: "Noted Song", identity: index.artistIdentity)
    let notedOnly = evaluate(artist: "New Artist", title: "Noted Song",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [noteOnlyKey], ledger: empty, recordedAt: now)
    #expect(notedOnly.reasons == ["noted"])
    #expect(!notedOnly.artistKnown)

    let recommendedOnly = evaluate(artist: "New Artist", title: "Prior Find",
      snapshot: snapshot, index: index, playlistIndex: playlistIndex, listeningLog: nil,
      tasteNoteKeys: [], ledger: RecommendationLedgerReadResult(batches: [
        RecommendationBatch(recordedAt: now.addingTimeInterval(-10), host: "Mac", playlist: "Earlier",
          tracks: [RecommendationTrack(artist: "New Artist", title: "Prior Find", familiar: false,
            reasons: [], artistKnown: false)]),
      ], skippedLines: 0), recordedAt: now)
    #expect(recommendedOnly.reasons == ["recommended"])

    let unknownSongByKnownArtist = evaluate(artist: "Known Artist", title: "New Song",
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
    let before = evaluate(artist: "Heard Artist", title: "Heard Song",
      snapshot: snapshot, index: index, playlistIndex: PlaylistIndex(snapshot: snapshot,
        roles: PlaylistRoles(updatedAt: now, playlists: []), identity: index.artistIdentity),
      listeningLog: log, tasteNoteKeys: [], ledger: empty, recordedAt: now)
    #expect(before.reasons == ["heard"])
    let after = evaluate(artist: "Heard Artist", title: "Heard Song",
      snapshot: snapshot, index: index, playlistIndex: PlaylistIndex(snapshot: snapshot,
        roles: PlaylistRoles(updatedAt: now, playlists: []), identity: index.artistIdentity),
      listeningLog: log, tasteNoteKeys: [], ledger: empty, recordedAt: now.addingTimeInterval(-30))
    #expect(after.reasons.isEmpty)
  }

  @Test("heard familiarity and artistKnown match collaborator credits")
  func collaboratorPlayCredits() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [
      LibraryTrack(persistentID: "orville", name: "Another Song", artist: "Orville Peck"),
      LibraryTrack(persistentID: "emmylou", name: "Another Song", artist: "Emmylou Harris"),
    ])
    let fetch = ListeningFetch(poller: UUID(), host: "Fixture", fetchedAt: now.addingTimeInterval(-20),
      outcome: .plays, newCount: 1, pagesRead: 1, items: [
        ListeningItem(kind: .song, id: "prologue", title: "Prologue (Eulogy Of A Man Turned Mule)",
          artist: "Emmylou Harris, Noah Cyrus, Allison Russell & Orville Peck"),
      ])
    let log = ListeningLog(streams: [[fetch]], now: now,
      identity: ArtistIdentity(knownArtists: ["Orville Peck", "Emmylou Harris"]))
    let index = LibraryIndex(snapshot: snapshot)
    let familiarity = RecommendationFamiliarityIndex(snapshot: snapshot, index: index,
      playlistIndex: PlaylistIndex(snapshot: snapshot, roles: PlaylistRoles(updatedAt: now, playlists: []),
        identity: index.artistIdentity), listeningLog: log, tasteNoteKeys: [],
      ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0), recordedAt: now)
    let result = familiarity.evaluate(artist: "Orville Peck", title: "Prologue (Eulogy Of A Man Turned Mule)")
    #expect(result.reasons == ["heard"])
    #expect(result.artistKnown)
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
    let evidenceIndex = RecommendationLedgerEvidenceIndex(ledger: ledger, identity: identity)
    #expect(evidenceIndex.forSong(artist: "Artist", title: "Song") == RecommendationEvidence(count: 2, latestRecordedAt: recent))
    #expect(evidenceIndex.forSong(artist: "Artist", title: "Missing") == nil)
  }

  private func evaluate(artist: String, title: String, album: String? = nil, year: Int? = nil,
    snapshot: LibrarySnapshot, index: LibraryIndex, playlistIndex: PlaylistIndex,
    listeningLog: ListeningLog?, tasteNoteKeys: Set<String>, ledger: RecommendationLedgerReadResult,
    recordedAt: Date) -> RecommendationTrack {
    RecommendationFamiliarityIndex(snapshot: snapshot, index: index, playlistIndex: playlistIndex,
      listeningLog: listeningLog, tasteNoteKeys: tasteNoteKeys, ledger: ledger, recordedAt: recordedAt)
      .evaluate(artist: artist, title: title, album: album, year: year)
  }
}
