import Dependencies
import Foundation
import MusicKit
import Observation
import VinylFeverNotes

extension PlaylistShelfSong {
  /// A Catchup song as a shelf row: its sources are the row's labels.
  init(catchup song: PlaylistCatchupSong) {
    self.init(id: song.id, title: song.title, artist: song.artist, album: song.album,
      year: song.releaseDate.flatMap { Int($0.prefix(4)) }, familiarity: "",
      why: nil, like: [], details: song.sources)
  }
}

@MainActor
@Observable
final class PlaylistCatchupModel {
  static let routeID = "__playlist-catchup__"
  static let earliestListeningDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2018, month: 1, day: 1))!

  private(set) var songs: [PlaylistCatchupSong] = []
  private(set) var sources: [String] = []
  private(set) var isLoading = false
  private(set) var isAvailable = false
  private(set) var hasUnreadableFiles = false
  private(set) var errorMessage: String?
  var sourceFilter: String?

  @ObservationIgnored @Dependency(\.keepLibraryClient) private var keepClient
  @ObservationIgnored @Dependency(\.playlistListeningLogClient) private var listeningClient
  @ObservationIgnored @Dependency(\.date.now) private var now

  var displayedSongs: [PlaylistCatchupSong] { PlaylistCatchup.filtered(songs, source: sourceFilter) }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }
    guard keepClient.isAuthorized() else {
      isAvailable = false
      songs = []
      sources = []
      errorMessage = "Authorize Apple Music to build Playlist Catchup."
      return
    }
    do {
      let folderRead = try await Task.detached {
        try ProbeBookmarkStore.withFolder { TrackedPlaylistFolderReader.read(folder: $0) }
      }.value
      let library = try await keepClient.libraryPlaylists()
      let roles = try await keepClient.readRoles()
      let keeperNames = Set(roles?.playlists.filter { $0.role == .keepers }.map(\.name)
        ?? library.map(\.name).filter { $0 == "Vinyl Fever Keepers" || $0.range(of: SelectionPlaylistName.pattern, options: .regularExpression) != nil })
      var keeperTrackKeys = Set<String>()
      for playlist in library where keeperNames.contains(playlist.name) {
        let tracks = try await keepClient.tracks(playlist.id)
        keeperTrackKeys.formUnion(tracks.map { ListeningTextNormalizer.trackKey(artist: $0.artist, title: $0.title) })
      }
      let plays = try await listeningClient.read(Self.earliestListeningDate, now)
      let heardKeys = Set(plays.map { ListeningTextNormalizer.trackKey(artist: $0.item.artist, title: $0.item.title) })
      songs = PlaylistCatchup.make(snapshots: folderRead.snapshots, heardTrackKeys: heardKeys,
        keeperTrackKeys: keeperTrackKeys)
      sources = PlaylistCatchup.sources(in: songs)
      if let sourceFilter, !sources.contains(sourceFilter) { self.sourceFilter = nil }
      hasUnreadableFiles = folderRead.unreadableFileCount > 0
      isAvailable = true
      errorMessage = nil
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      isAvailable = false
      songs = []
      sources = []
      hasUnreadableFiles = false
      errorMessage = "Grant iCloud folder access in Setup to read tracked playlists."
    } catch {
      isAvailable = false
      hasUnreadableFiles = true
      errorMessage = error.localizedDescription
    }
  }
}
