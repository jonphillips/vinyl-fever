import Foundation

public enum PlaylistArchive {
  /// M22 allows this window for iCloud to bring a newly staged playlist to the phone (M18 S7).
  public static let gracePeriod: TimeInterval = 24 * 60 * 60

  public static func archivedPlaylistIDs(
    from playlists: [PlaylistShelfPlaylist],
    libraryPlaylistNames: [String]?,
    now: Date
  ) -> Set<String> {
    guard let libraryPlaylistNames else { return [] }

    var stagedCountsByName: [String: Int] = [:]
    for playlist in playlists {
      guard let name = playlist.batch.playlist,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }
      stagedCountsByName[name, default: 0] += 1
    }

    return Set(playlists.compactMap { playlist in
      guard let name = playlist.batch.playlist,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        stagedCountsByName[name] == 1,
        !libraryPlaylistNames.contains(name),
        now.timeIntervalSince(playlist.batch.recordedAt) > gracePeriod
      else { return nil }
      return playlist.id
    })
  }
}
