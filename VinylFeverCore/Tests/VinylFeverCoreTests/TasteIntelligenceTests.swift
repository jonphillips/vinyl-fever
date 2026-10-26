import Foundation
import Testing
import VinylFeverCore
import VinylFeverListening

struct TasteIntelligenceTests {
  @Test("snapshot curation diff ignores playlist reorders and records membership and flag changes")
  func curationDiff() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let firstTrack = LibraryTrack(persistentID: "1", name: "One", artist: "A", album: "A", favorited: false)
    let secondTrack = LibraryTrack(persistentID: "2", name: "Two", artist: "A", album: "B")
    let playlist = LibraryPlaylist(persistentID: "p", name: "Keep", kind: .user, members: ["1", "2"])
    let old = LibrarySnapshot(generatedAt: t0, tracks: [firstTrack, secondTrack], playlists: [playlist])
    var changed = firstTrack; changed.favorited = true; changed.disliked = true
    let replacement = LibraryTrack(persistentID: "3", name: "Three", artist: "B", album: "C")
    let reordered = LibraryPlaylist(persistentID: "p", name: "Keep", kind: .user, members: ["2", "1", "3"])
    let current = LibrarySnapshot(generatedAt: t0.addingTimeInterval(60), tracks: [changed, secondTrack, replacement], playlists: [reordered])
    let diff = SnapshotCurationDiff.diff(previous: old, current: current, observedAt: t0.addingTimeInterval(120))
    #expect(diff.baseline == false)
    #expect(diff.playlists.first?.added.map(\.title) == ["Three"])
    #expect(diff.playlists.first?.removed.isEmpty == true)
    #expect(diff.tracks.count == 1)
    #expect(diff.tracks.first?.favoriteFrom == false)
    #expect(diff.tracks.first?.dislikeTo == true)
    #expect(diff.isEmpty == false)
    #expect(SnapshotCurationDiff.diff(previous: old, current: old, observedAt: t0).isEmpty)
    #expect(SnapshotCurationDiff.diff(previous: nil, current: old, observedAt: t0).isEmpty == false)
  }

  @Test("New Music classification includes kept, passed, unheard and pending songs")
  func classifications() {
    let modified = Date(timeIntervalSince1970: 1_800_000_000)
    let now = modified.addingTimeInterval(20 * 86_400)
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [
      LibraryTrack(persistentID: "keep", name: "Kept song", artist: "A"),
    ], playlists: [LibraryPlaylist(persistentID: "keepers", name: "Keepers", kind: .user, members: ["keep"])])
    let roles = PlaylistRoles(updatedAt: now, playlists: [PlaylistRoleEntry(persistentID: "keepers", name: "Keepers", role: .keepers)])
    let poller = UUID()
    let play = ListeningFetch(poller: poller, host: "Mac", fetchedAt: modified.addingTimeInterval(2 * 86_400),
      outcome: .plays, newCount: 1, pagesRead: 1,
      items: [ListeningItem(kind: .song, id: "passed", title: "Passed song", artist: "B")])
    let log = ListeningLog(streams: [[play]], now: now)
    let week = NewMusicWeek(lastModifiedDate: modified, fetchedAt: modified,
      host: "Mac", tracks: [
        NewMusicTrack(catalogID: "1", title: "Kept song", artist: "A"),
        NewMusicTrack(catalogID: "2", title: "Passed song", artist: "B"),
        NewMusicTrack(catalogID: "3", title: "Unheard song", artist: "C"),
      ])
    let pending = NewMusicWeek(lastModifiedDate: now.addingTimeInterval(-2 * 86_400), fetchedAt: now,
      host: "Mac", tracks: [NewMusicTrack(catalogID: "4", title: "New song", artist: "D")])
    let result = TasteIntelligence.keptAndPassed(weeks: [week, pending], snapshot: snapshot,
      roles: roles, log: log, now: now)
    #expect(result[0].tracks.map(\.classification) == [.pending])
    #expect(result[1].tracks.map(\.classification) == [.kept, .passed, .unheard])
    #expect(result[1].counts == ["kept": 1, "passed": 1, "unheard": 1])
  }

  @Test("taste baselines use Replay N and N+1 and report counts")
  func baselines() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = LibrarySnapshot(generatedAt: date, tracks: [], playlists: [
      LibraryPlaylist(persistentID: "selection", name: "2025: Jon's Selections", kind: .user, members: ["one", "two"]),
      LibraryPlaylist(persistentID: "replay", name: "Replay 2026", kind: .subscription, members: ["one"]),
    ], outsideTracks: [
      "one": LibraryOutsideTrack(name: "One", artist: "A", album: "Album"),
      "two": LibraryOutsideTrack(name: "Two", artist: "B", album: "Album"),
    ])
    let week = NewMusicWeekResult(lastModifiedDate: date, fetchedAt: date,
      counts: ["kept": 2, "passed": 1], tracks: [])
    let result = TasteIntelligence.baselines(weeks: [week], snapshot: snapshot)
    #expect(result.overallYield.kept == 2)
    #expect(result.overallYield.passed == 1)
    #expect(result.overallYield.ratio == 2.0 / 3.0)
    #expect(result.stickRates.first(where: { $0.year == 2025 })?.selections == 2)
    #expect(result.stickRates.first(where: { $0.year == 2025 })?.returned == 1)
  }

  @Test("release age boundaries and unknown years")
  func releaseAgeBands() {
    #expect(TasteIntelligence.band(releaseYear: 2026, batchYear: 2026) == .new)
    #expect(TasteIntelligence.band(releaseYear: 2025, batchYear: 2026) == .new)
    #expect(TasteIntelligence.band(releaseYear: 2024, batchYear: 2026) == .recent)
    #expect(TasteIntelligence.band(releaseYear: 2021, batchYear: 2026) == .recent)
    #expect(TasteIntelligence.band(releaseYear: 2020, batchYear: 2026) == .catalog)
    #expect(TasteIntelligence.band(releaseYear: nil, batchYear: 2026) == .unknown)
  }

  @Test("stick rate excludes additions first observed after the following year")
  func stickRateExcludesLateAdds() {
    let observed = ISO8601DateFormatter().date(from: "2026-02-01T12:00:00Z")!
    let snapshot = LibrarySnapshot(generatedAt: observed, tracks: [
      LibraryTrack(persistentID: "early", name: "Early", artist: "A"),
      LibraryTrack(persistentID: "late", name: "Late", artist: "B"),
    ], playlists: [LibraryPlaylist(persistentID: "selection", name: "2024: Jon's Selections", kind: .user, members: ["early", "late"])])
    let curation = CurationChange(observedAt: observed, previousSnapshotAt: observed.addingTimeInterval(-60),
      playlists: [CurationPlaylistChange(name: "2024: Jon's Selections", persistentID: "selection",
        added: [CurationSong(artist: "B", title: "Late", album: "")])])
    let result = TasteIntelligence.baselines(weeks: [], snapshot: snapshot, curation: [curation])
    let rate = result.stickRates.first { $0.year == 2024 }
    #expect(rate?.selections == 1)
    #expect(rate?.excludedLateAdds == 1)
  }

  @Test("New Music picks score picked songs against the rest of the same week")
  func newMusicPickOutcomes() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let now = date.addingTimeInterval(15 * 86_400)
    let snapshot = LibrarySnapshot(generatedAt: now, tracks: [
      LibraryTrack(persistentID: "keep-id", name: "Keep Song", artist: "Keep Artist"),
    ], playlists: [LibraryPlaylist(persistentID: "keepers", name: "Keepers", kind: .user, members: ["keep-id"])])
    let roles = PlaylistRoles(updatedAt: now,
      playlists: [PlaylistRoleEntry(persistentID: "keepers", name: "Keepers", role: .keepers)])
    let poller = UUID()
    let fetch = ListeningFetch(poller: poller, host: "Mac", fetchedAt: date.addingTimeInterval(3 * 86_400),
      outcome: .plays, newCount: 1, pagesRead: 1,
      items: [
        ListeningItem(kind: .song, id: "pass-id", title: "Pass Song", artist: "Pass Artist"),
        ListeningItem(kind: .song, id: "heard-id", title: "Heard Song", artist: "Heard Artist"),
      ])
    let log = ListeningLog(streams: [[fetch]], now: now)
    let week = NewMusicWeek(lastModifiedDate: date, fetchedAt: date, host: "Mac", tracks: [
      NewMusicTrack(catalogID: "keep-catalog", title: "Keep Song", artist: "Keep Artist", releaseDate: "2027-01-01"),
      NewMusicTrack(catalogID: "pass-catalog", title: "Pass Song", artist: "Pass Artist", releaseDate: "2026-01-01"),
      NewMusicTrack(catalogID: "heard-catalog", title: "Heard Song", artist: "Heard Artist", releaseDate: "2027-01-01"),
    ])
    let ledgerBatch = RecommendationBatch(kind: "new-music-picks", recordedAt: date.addingTimeInterval(100),
      host: "Mac", tracks: [
        RecommendationTrack(artist: "Keep Artist", title: "Keep Song", year: 2027, familiar: false, reasons: [], artistKnown: false, picked: true),
        RecommendationTrack(artist: "Pass Artist", title: "Pass Song", year: 2026, familiar: false, reasons: [], artistKnown: false, picked: false),
        RecommendationTrack(artist: "Heard Artist", title: "Heard Song", year: 2027, familiar: false, reasons: [], artistKnown: false, heardBeforePick: true, picked: true),
      ], coverage: RecommendationCoverage(listening: true, notes: true, snapshotAt: now), batchDate: date)
    let ledger = RecommendationLedgerReadResult(batches: [ledgerBatch], skippedLines: 0)
    let classified = TasteIntelligence.keptAndPassed(weeks: [week], snapshot: snapshot,
      roles: roles, log: log, now: now)
    let outcomes = TasteIntelligence.recommendationOutcomes(ledger: ledger, weeks: [week],
      snapshot: snapshot, roles: roles, log: log, now: now)
    let batch = outcomes.batches[0]
    #expect(batch.pickedCounts == ["kept": 1])
    #expect(batch.notPickedCounts == ["passed": 1])
    #expect(batch.songs.map(\.title).sorted() == ["Keep Song", "Pass Song"])
    let baselines = TasteIntelligence.baselines(weeks: classified, snapshot: snapshot,
      ledger: ledger, outcomes: outcomes)
    let pick = baselines.picksByWeek[date.ISO8601Format()]
    #expect(pick?.picked.kept == 1)
    #expect(pick?.notPicked.passed == 1)
    #expect(baselines.bySourceAndBand["chat|new"]?.ratio == nil)
  }

  @Test("pending weeks do not contribute to yield")
  func baselinesExcludePendingWeeksFromYield() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = LibrarySnapshot(generatedAt: date, tracks: [], playlists: [])
    let finished = NewMusicWeekResult(lastModifiedDate: date, fetchedAt: date,
      counts: ["kept": 2, "passed": 1], tracks: [])
    let pending = NewMusicWeekResult(lastModifiedDate: date.addingTimeInterval(100), fetchedAt: date,
      counts: ["kept": 3, "pending": 22], tracks: [])
    let result = TasteIntelligence.baselines(weeks: [finished, pending], snapshot: snapshot)
    #expect(result.weeklyYield.count == 1)
    #expect(result.overallYield.kept == 2)
    #expect(result.overallYield.passed == 1)
    #expect(result.pendingWeeks == 1)
  }

  @Test("stick rate merges artist variants between Selections and Replay")
  func stickRateMergesArtistVariants() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = LibrarySnapshot(generatedAt: date, tracks: [
      LibraryTrack(persistentID: "selection-song", name: "The Weight", artist: "The Band"),
      LibraryTrack(persistentID: "replay-song", name: "The Weight", artist: "Band, The"),
    ], playlists: [
      LibraryPlaylist(persistentID: "selection", name: "2025: Jon's Selections", kind: .user, members: ["selection-song"]),
      LibraryPlaylist(persistentID: "replay", name: "Replay 2026", kind: .subscription, members: ["replay-song"]),
    ])
    let result = TasteIntelligence.baselines(weeks: [], snapshot: snapshot)
    #expect(result.stickRates.first(where: { $0.year == 2025 })?.selections == 1)
    #expect(result.stickRates.first(where: { $0.year == 2025 })?.returned == 1)
  }

  @Test("kept and passed scales to Jon's library size", .enabled(if: ProcessInfo.processInfo.environment["VF_PERF_TESTS"] == "1"))
  func keptAndPassedAtJonsScale() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let tracks = (0..<87_000).map { index in
      LibraryTrack(persistentID: "track-\(index)", name: "Track \(index)", artist: "Artist \(index % 500)")
    }
    let playlists = (0..<150).map { index in
      LibraryPlaylist(persistentID: "playlist-\(index)", name: "Playlist \(index)", kind: .user, members: [])
    }
    let snapshot = LibrarySnapshot(generatedAt: start.addingTimeInterval(60 * 86_400), tracks: tracks, playlists: playlists)
    let roles = PlaylistRoles(updatedAt: start, playlists: [])
    let weeks = (0..<8).map { index in
      NewMusicWeek(lastModifiedDate: start.addingTimeInterval(Double(index) * 7 * 86_400), fetchedAt: start,
        host: "Mini", tracks: (0..<25).map { song in NewMusicTrack(catalogID: "week-\(index)-\(song)", title: "New \(song)", artist: "Artist \(song)") })
    }
    let poller = UUID()
    let plays = (0..<15_000).map { index in
      ListeningFetch(poller: poller, host: "Mini", fetchedAt: start.addingTimeInterval(Double(index) * 20),
        outcome: .plays, newCount: 1, pagesRead: 1,
        items: [ListeningItem(kind: .song, id: "play-\(index)", title: "New \(index % 25)", artist: "Artist \(index % 25)")])
    }
    let log = ListeningLog(streams: [plays], now: start.addingTimeInterval(60 * 86_400))
    let clock = ContinuousClock()
    let elapsed = clock.measure {
      _ = TasteIntelligence.keptAndPassed(weeks: weeks, snapshot: snapshot, roles: roles, log: log,
        now: start.addingTimeInterval(60 * 86_400))
    }
    #expect(elapsed < .seconds(1))
  }
}
