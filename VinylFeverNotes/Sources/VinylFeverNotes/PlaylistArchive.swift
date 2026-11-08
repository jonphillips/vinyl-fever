import Foundation

public enum PlaylistArchive {
  public static let gracePeriod: TimeInterval = 14 * 24 * 60 * 60

  public static func archivedPlaylistIDs(
    from playlists: [PlaylistShelfPlaylist],
    libraryPlaylistNames: [String]?,
    creations: [PlaylistCreationEvent] = [],
    now: Date
  ) -> Set<String> {
    let latest = PlaylistCreationsCodec.latestEvents(creations)
    var stagedCountsByName: [String: Int] = [:]
    for playlist in playlists {
      guard let name = playlist.batch.playlist,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { continue }
      stagedCountsByName[name, default: 0] += 1
    }

    return Set(playlists.compactMap { playlist in
      guard let name = playlist.batch.playlist,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return nil }
      let key = PlaylistCreationsCodec.batchKey(host: playlist.batch.host, recordedAt: playlist.batch.recordedAt)
      if let event = latest[key] {
        switch event.kind {
        case .dismissed: return playlist.id
        case .created:
          guard let libraryPlaylistNames, !libraryPlaylistNames.contains(name) else { return nil }
          return playlist.id
        }
      }
      guard stagedCountsByName[name] == 1,
        let libraryPlaylistNames, !libraryPlaylistNames.contains(name),
        now.timeIntervalSince(playlist.batch.recordedAt) > gracePeriod else { return nil }
      return playlist.id
    })
  }
}
