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
  private(set) var resolvingSongIDs: Set<String> = []
  private(set) var isResolving = false
  private(set) var errorMessage: String?
  private(set) var matchedPlaylist: Playlist?
  private(set) var nowPlayingSongID: String?

  @ObservationIgnored
  @Dependency(\.playlistMusicClient) private var client

  private var activePlaylistID: String?
  private var songs: [PlaylistShelfSong] = []
  private var didLookUpStagedPlaylist = false
  private var stagedPlaylistLookupTask: Task<Playlist?, Never>?
  private var stagedPlaylistLookupID: String?
  private var resolutionTasks: [String: Task<Song?, Never>] = [:]

  static let resolveAheadCount = 8

  func prepare(_ playlist: PlaylistShelfPlaylist) async {
    let wasAuthorized = isAuthorized
    isAuthorized = client.isAuthorized()
    guard activePlaylistID != playlist.id else {
      if !wasAuthorized && isAuthorized {
        beginStagedPlaylistLookup(for: playlist)
      }
      return
    }
    activePlaylistID = playlist.id
    songs = playlist.songs
    matchedPlaylist = nil
    didLookUpStagedPlaylist = false
    stagedPlaylistLookupTask = nil
    stagedPlaylistLookupID = nil
    errorMessage = nil
    guard isAuthorized else { return }
    beginStagedPlaylistLookup(for: playlist)
  }

  private func beginStagedPlaylistLookup(for playlist: PlaylistShelfPlaylist) {
    guard !didLookUpStagedPlaylist else { return }
    didLookUpStagedPlaylist = true
    guard let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return
    }
    stagedPlaylistLookupTask = Task { @MainActor in
      do {
        let matches = try await client.playlists().filter { $0.name == name }
        guard matches.count == 1, let match = matches.first else { return nil }
        return try await client.playlistDetails(match)
      } catch {
        return nil
      }
    }
    stagedPlaylistLookupID = playlist.id
  }

  private func waitForStagedPlaylistLookup() async {
    guard let stagedPlaylistLookupTask else { return }
    let lookupID = stagedPlaylistLookupID
    let result = await stagedPlaylistLookupTask.value
    guard activePlaylistID == lookupID else { return }
    matchedPlaylist = result
    self.stagedPlaylistLookupTask = nil
    stagedPlaylistLookupID = nil
  }

  func resolveSongs(through index: Int) async {
    guard isAuthorized, !songs.isEmpty, index >= 0 else { return }
    await waitForStagedPlaylistLookup()
    isResolving = true
    defer { isResolving = false }
    for song in songs.prefix(index + 1) {
      _ = await resolveSong(song.id)
    }
  }

  private func resolveSong(_ songID: String) async -> Song? {
    guard let reference = songs.first(where: { $0.id == songID }) else { return nil }
    if let resolved = resolvedSongs[songID] { return resolved }
    if notFoundSongIDs.contains(songID) { return nil }
    if let task = resolutionTasks[songID] { return await task.value }

    resolvingSongIDs.insert(songID)
    let task = Task { @MainActor in await resolve(reference) }
    resolutionTasks[songID] = task
    let result = await task.value
    resolutionTasks[songID] = nil
    resolvingSongIDs.remove(songID)
    if let result {
      resolvedSongs[songID] = result
    } else {
      notFoundSongIDs.insert(songID)
    }
    return result
  }

  private func resolveRemainingSongsConcurrently() async {
    let remaining = songs.filter { resolvedSongs[$0.id] == nil && !notFoundSongIDs.contains($0.id) }
    await withTaskGroup(of: Void.self) { group in
      var nextIndex = 0
      for _ in 0..<min(4, remaining.count) {
        let songID = remaining[nextIndex].id
        nextIndex += 1
        group.addTask { _ = await self.resolveSong(songID) }
      }
      while await group.next() != nil, nextIndex < remaining.count {
        let songID = remaining[nextIndex].id
        nextIndex += 1
        group.addTask { _ = await self.resolveSong(songID) }
      }
    }
  }

  func play(_ songID: String) async {
    guard songs.contains(where: { $0.id == songID }) else { return }
    await waitForStagedPlaylistLookup()
    isResolving = true
    defer { isResolving = false }
    guard let startingSong = await resolveSong(songID) else { return }
    do {
      if let matchedPlaylist {
        let target = songs.first { $0.id == songID }
        let entry = matchedPlaylist.entries?.first(where: { entry in
          guard let target else { return false }
          return MusicFeedback.matches(
            FeedbackSong(title: entry.title, artist: entry.artistName),
            FeedbackSong(title: target.title, artist: target.artist)
          )
        })
        if let entry {
          try await client.playPlaylist(matchedPlaylist, entry)
          errorMessage = nil
          return
        }
      }

      await resolveRemainingSongsConcurrently()
      let orderedSongs = songs.compactMap { resolvedSongs[$0.id] }
      guard orderedSongs.contains(where: { $0.id == startingSong.id }) else { return }
      try await client.playSongs(orderedSongs, startingSong)
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
      if afterCurrent, !client.hasCurrentEntry() {
        try await client.playSongs([song], song)
      } else {
        try await client.insertSong(song, afterCurrent)
        if afterCurrent { try await client.play() }
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func observeCurrentEntry() async {
    for await entry in client.currentEntry() {
      guard let entry else {
        nowPlayingSongID = nil
        continue
      }
      nowPlayingSongID = songs.first(where: { song in
        MusicFeedback.matches(entry, FeedbackSong(title: song.title, artist: song.artist))
      })?.id
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
