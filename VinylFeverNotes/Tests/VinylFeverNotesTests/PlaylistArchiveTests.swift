import Foundation
import Testing
@testable import VinylFeverNotes

struct PlaylistArchiveTests {
  @Test func gracePeriodIsFourteenDays() {
    #expect(PlaylistArchive.gracePeriod == 14 * 24 * 60 * 60)
  }
  @Test func aNamedPlaylistPresentInTheLibraryIsActive() {
    #expect(!isArchived(name: "Power Pop", stagedAt: 0, library: ["Power Pop"], now: 200_000))
  }

  @Test func anAbsentPlaylistPastTheGracePeriodIsArchived() {
    #expect(isArchived(name: "Power Pop", stagedAt: 0, library: [], now: PlaylistArchive.gracePeriod + 1))
  }

  @Test func anAbsentPlaylistWithinTheGracePeriodIsActive() {
    #expect(!isArchived(name: "Power Pop", stagedAt: 0, library: [], now: PlaylistArchive.gracePeriod))
  }

  @Test func aNameSharedByLibraryPlaylistsIsActive() {
    #expect(!isArchived(name: "Power Pop", stagedAt: 0, library: ["Power Pop", "Power Pop"], now: 200_000))
  }

  @Test func aNameSharedByTwoStagedPlaylistsIsActive() {
    #expect(!isArchived(name: "Power Pop", stagedAt: 0, siblings: ["Power Pop"], library: [], now: 200_000))
  }

  @Test func aBatchWithoutAPlaylistNameIsActive() {
    #expect(!isArchived(name: nil, stagedAt: 0, library: [], now: 200_000))
  }

  @Test func aFailedLibraryReadLeavesEveryPlaylistActive() {
    #expect(!isArchived(name: "Power Pop", stagedAt: 0, library: nil, now: 200_000))
  }

  @Test func aCreatedPlaylistMissingFromMusicArchivesImmediately() {
    let date = Date(timeIntervalSince1970: 10)
    let event = PlaylistCreationEvent(kind: .created, host: "Test", recordedAt: date,
      playlist: "Power Pop", at: date, writerHost: "Phone", musicID: "p.1", songs: 1, skipped: [])
    #expect(PlaylistArchive.archivedPlaylistIDs(from: [playlist(name: "Power Pop", id: "target", stagedAt: 10)],
      libraryPlaylistNames: [], creations: [event], now: date).contains("target"))
  }

  @Test func aCreatedPlaylistStillInMusicRemainsActive() {
    let date = Date(timeIntervalSince1970: 10)
    let event = PlaylistCreationEvent(kind: .created, host: "Test", recordedAt: date,
      playlist: "Power Pop", at: date, writerHost: "Phone", musicID: "p.1", songs: 1, skipped: [])
    #expect(!PlaylistArchive.archivedPlaylistIDs(from: [playlist(name: "Power Pop", id: "target", stagedAt: 10)],
      libraryPlaylistNames: ["Power Pop"], creations: [event], now: date).contains("target"))
  }

  @Test func aDismissedPlaylistArchivesWithoutALibraryRead() {
    let date = Date(timeIntervalSince1970: 10)
    let event = PlaylistCreationEvent(kind: .dismissed, host: "Test", recordedAt: date,
      playlist: "Power Pop", at: date, writerHost: "Mac")
    #expect(PlaylistArchive.archivedPlaylistIDs(from: [playlist(name: "Power Pop", id: "target", stagedAt: 10)],
      libraryPlaylistNames: nil, creations: [event], now: date).contains("target"))
  }

  private func isArchived(
    name: String?, stagedAt: TimeInterval, siblings: [String?] = [], library: [String]?, now: TimeInterval
  ) -> Bool {
    let playlists = [playlist(name: name, id: "target", stagedAt: stagedAt)]
      + siblings.enumerated().map { index, sibling in
        playlist(name: sibling, id: "sibling-\(index)", stagedAt: stagedAt + TimeInterval(index + 1))
      }
    return PlaylistArchive.archivedPlaylistIDs(from: playlists, libraryPlaylistNames: library,
      now: Date(timeIntervalSince1970: now)).contains("target")
  }

  private func playlist(name: String?, id: String, stagedAt: TimeInterval) -> PlaylistShelfPlaylist {
    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: stagedAt), host: "Test",
      playlist: name, tracks: [])
    return PlaylistShelfPlaylist(id: id, batch: batch, stagedDate: "today",
      songCount: 0, newSongCount: 0, songs: [])
  }
}
