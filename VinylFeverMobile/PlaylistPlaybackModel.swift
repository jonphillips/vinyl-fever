import Dependencies
import MusicKit
import Observation
import VinylFeverNotes

@MainActor
@Observable
final class PlaylistPlaybackModel {
  private(set) var isAuthorized = false
  private(set) var resolvedSongs: [String: Song] = [:]
  private(set) var notFoundSongIDs: Set<String> = []
  private(set) var isResolving = false
  private(set) var errorMessage: String?
  private(set) var matchedPlaylist: Playlist?

  @ObservationIgnored
  @Dependency(\.playlistMusicClient) private var client

  private var activePlaylistID: String?
  private var songs: [PlaylistShelfSong] = []
  private var pendingSongIDs: Set<String> = []
  private var didLookUpStagedPlaylist = false

  func prepare(_ playlist: PlaylistShelfPlaylist) async {
    let wasAuthorized = isAuthorized
    isAuthorized = client.isAuthorized()
    guard activePlaylistID != playlist.id else {
      if !wasAuthorized && isAuthorized {
        await lookUpStagedPlaylist(for: playlist)
      }
      await resolveSongs(through: min(8, playlist.songs.count - 1))
      return
    }
    activePlaylistID = playlist.id
    songs = playlist.songs
    pendingSongIDs = []
    matchedPlaylist = nil
    didLookUpStagedPlaylist = false
    errorMessage = nil
    guard isAuthorized else { return }
    await lookUpStagedPlaylist(for: playlist)
    await resolveSongs(through: min(8, playlist.songs.count - 1))
  }

  private func lookUpStagedPlaylist(for playlist: PlaylistShelfPlaylist) async {
    guard !didLookUpStagedPlaylist else { return }
    didLookUpStagedPlaylist = true
    if let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      do {
        let matches = try await client.playlists().filter { $0.name == name }
        if matches.count == 1, let match = matches.first {
          matchedPlaylist = try await client.playlistDetails(match)
        }
      } catch {
        // A missing or inaccessible staged playlist falls through to library and catalog search.
      }
    }
  }

  func resolveSongs(through index: Int) async {
    guard isAuthorized, !songs.isEmpty, index >= 0 else { return }
    isResolving = true
    defer { isResolving = false }
    for song in songs.prefix(index + 1) {
      guard resolvedSongs[song.id] == nil, !notFoundSongIDs.contains(song.id),
        !pendingSongIDs.contains(song.id)
      else { continue }
      pendingSongIDs.insert(song.id)
      defer { pendingSongIDs.remove(song.id) }
      if let match = await resolve(song) {
        resolvedSongs[song.id] = match
      } else {
        notFoundSongIDs.insert(song.id)
      }
    }
  }

  func play(_ songID: String) async {
    guard songs.contains(where: { $0.id == songID }) else { return }
    await resolveSongs(through: songs.count - 1)
    guard let startingSong = resolvedSongs[songID] else { return }
    do {
      if let matchedPlaylist {
        try await client.playPlaylist(matchedPlaylist, startingSong)
      } else {
        let orderedSongs = songs.compactMap { resolvedSongs[$0.id] }
        try await client.playSongs(orderedSongs, startingSong)
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func playLike(_ like: RecommendationLike, afterCurrent: Bool) async {
    guard isAuthorized else { return }
    let reference = PlaylistShelfSong(
      id: "like|\(like.title)|\(like.artist)", title: like.title, artist: like.artist,
      album: nil, year: nil, familiarity: "", why: nil, like: []
    )
    guard let song = await resolve(reference, includeStagedPlaylist: false) else {
      errorMessage = "Not in Apple Music: \(like.title)"
      return
    }
    do {
      try await client.insertSong(song, afterCurrent)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func resolve(_ reference: PlaylistShelfSong, includeStagedPlaylist: Bool = true) async -> Song? {
    if includeStagedPlaylist {
      let stagedMatches = (matchedPlaylist?.tracks?.compactMap { track -> Song? in
        guard case let .song(song) = track else { return nil }
        return song
      } ?? []).filter { matches($0, reference) }
      if let match = stagedMatches.first { return match }
    }

    if let library = try? await client.librarySongs(reference.title),
      let match = library.first(where: { matches($0, reference) }) {
      return match
    }

    let term = "\(reference.title) \(reference.artist)"
    if let catalog = try? await client.catalogSongs(term, 5) {
      return catalog.first(where: { matches($0, reference) })
    }
    return nil
  }

  private func matches(_ song: Song, _ reference: PlaylistShelfSong) -> Bool {
    MusicFeedback.matches(
      FeedbackSong(title: song.title, artist: song.artistName),
      FeedbackSong(title: reference.title, artist: reference.artist)
    )
  }
}
