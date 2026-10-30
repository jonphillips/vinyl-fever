import Dependencies
import Foundation
import MusicKit
import Observation
import VinylFeverNotes

struct PlaylistKeepRequest: Equatable, Sendable {
  var songID: String
  var title: String
  var artist: String
  var reference: PlaylistSongReference
  var year: Int?
}

@MainActor
@Observable
final class PlaylistKeepModel {
  enum Destination: Identifiable, Equatable {
    case keep(PlaylistKeepRequest)
    var id: String {
      switch self { case .keep(let request): "\(request.reference.id)|\(request.title)|\(request.artist)" }
    }
  }

  private(set) var playlists: [KeepPlaylist] = []
  private(set) var rolesReadFallback = false
  private(set) var errorMessage: String?
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var savedPlaylistNames: [String] = []
  private(set) var keptPlaylistsBySong: [String: [String]] = [:]
  var destination: Destination?
  private(set) var currentRequest: PlaylistKeepRequest?

  @ObservationIgnored
  @Dependency(\.keepLibraryClient) private var client
  private var cachedEditablePlaylists: [KeepLibraryPlaylist]?
  private var cachedRoles: PlaylistRoles?
  private var didReadRoles = false
  private var tracksByPlaylist: [String: [KeepLibraryTrack]] = [:]
  private var loadedTrackPlaylists: Set<String> = []
  private var request: PlaylistKeepRequest?

  var isAuthorized: Bool { client.isAuthorized() }

  func keepButtonTapped(for shelfSong: PlaylistShelfSong, resolvedSong: Song) async {
    guard isAuthorized else { return }
    let year = shelfSong.year ?? resolvedSong.releaseDate.map(PlaylistKeepOptions.releaseYear(from:))
    let source: PlaylistSongSource = resolvedSong.id.rawValue.hasPrefix("i.") ? .libraryUpload : .catalog
    let request = PlaylistKeepRequest(songID: shelfSong.id, title: shelfSong.title, artist: shelfSong.artist,
      reference: PlaylistSongReference(id: resolvedSong.id.rawValue, source: source), year: year)
    currentRequest = request
    savedPlaylistNames = keptPlaylistsBySong[shelfSong.id] ?? []
    destination = .keep(request)
    await prepare(request)
  }

  func toggle(_ playlistID: String, isChecked: Bool) {
    guard let index = playlists.firstIndex(where: { $0.id == playlistID }), !playlists[index].isDisabled else { return }
    playlists[index].isChecked = isChecked
  }

  func cancel() { destination = nil; errorMessage = nil }

  func prepare(_ request: PlaylistKeepRequest) async {
    self.request = request
    currentRequest = request
    errorMessage = nil
    isLoading = true
    defer { isLoading = false }
    do {
      if cachedEditablePlaylists == nil { cachedEditablePlaylists = try await client.editablePlaylists() }
      if !didReadRoles {
        cachedRoles = try? await client.readRoles()
        didReadRoles = true
      }
      let choices = PlaylistKeepOptions.make(roles: cachedRoles,
        editablePlaylists: (cachedEditablePlaylists ?? []).map { (id: $0.id, name: $0.name) }, year: request.year)
      rolesReadFallback = choices.rolesReadFallback
      var rows = choices.playlists
      for index in rows.indices {
        let id = rows[index].id
        if !loadedTrackPlaylists.contains(id) {
          tracksByPlaylist[id] = try await client.tracks(id)
          loadedTrackPlaylists.insert(id)
        }
        if let tracks = tracksByPlaylist[id], tracks.contains(where: { matches($0, request) }) {
          rows[index].isAlreadyThere = true
          rows[index].isChecked = true
        }
      }
      playlists = rows
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func save() async {
    guard let request, !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    var failures: [String] = []
    for playlist in playlists where playlist.isChecked && !playlist.isAlreadyThere {
      do {
        try await client.append(playlist.id, request.reference)
        savedPlaylistNames.append(playlist.name)
        keptPlaylistsBySong[request.songID, default: []].append(playlist.name)
        do {
          tracksByPlaylist[playlist.id] = try await client.tracks(playlist.id)
          loadedTrackPlaylists.insert(playlist.id)
        } catch {
          tracksByPlaylist[playlist.id, default: []].append(KeepLibraryTrack(title: request.title, artist: request.artist))
        }
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
          playlists[index].isAlreadyThere = true
          playlists[index].isChecked = true
        }
      } catch {
        failures.append("\(playlist.name): \(error.localizedDescription)")
      }
    }
    errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    if failures.isEmpty { destination = nil }
  }

  private func matches(_ track: KeepLibraryTrack, _ request: PlaylistKeepRequest) -> Bool {
    MusicFeedback.matches(FeedbackSong(title: track.title, artist: track.artist),
      FeedbackSong(title: request.title, artist: request.artist))
  }
}
