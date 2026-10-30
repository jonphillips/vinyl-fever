import Dependencies
import DependenciesMacros
import Foundation
import MusicKit
import VinylFeverNotes

struct KeepLibraryPlaylist: Equatable, Sendable, Identifiable {
  var id: String
  var name: String
}

struct KeepLibraryTrack: Equatable, Sendable {
  var title: String
  var artist: String
}

@DependencyClient
struct KeepLibraryClient {
  var isAuthorized: @MainActor @Sendable () -> Bool = { false }
  var readRoles: @Sendable () async throws -> PlaylistRoles?
  var editablePlaylists: @Sendable () async throws -> [KeepLibraryPlaylist]
  var tracks: @Sendable (String) async throws -> [KeepLibraryTrack]
  var append: @Sendable (String, PlaylistSongReference) async throws -> Void
}

extension KeepLibraryClient: TestDependencyKey {
  static var testValue: Self { Self() }
}

private enum KeepLibraryClientKey: DependencyKey {
  static let liveValue = KeepLibraryClient(
    isAuthorized: { MusicAuthorization.currentStatus == .authorized },
    readRoles: {
      try await Task.detached {
        try ProbeBookmarkStore.withFolder { folder in
          let url = folder.appending(path: "Taste Intelligence/playlist-roles.json")
          let coordinator = NSFileCoordinator(filePresenter: nil)
          var coordinationError: NSError?
          var readError: Error?
          var data: Data?
          coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do { data = try Data(contentsOf: coordinatedURL) } catch { readError = error }
          }
          if let coordinationError { throw coordinationError }
          if let readError { throw readError }
          guard let data else { return nil }
          return try PlaylistRolesCodec.decode(data)
        }
      }.value
    },
    editablePlaylists: {
      var next: String? = "/v1/me/library/playlists"
      var playlists: [KeepLibraryPlaylist] = []
      while let page = next {
        let response = try await Self.getPage(path: page)
        playlists += response.data.compactMap { playlist in
          guard playlist.attributes.canEdit == true else { return nil }
          return KeepLibraryPlaylist(id: playlist.id, name: playlist.attributes.name)
        }
        next = response.next
      }
      return playlists
    },
    tracks: { playlistID in
      var next: String? = "/v1/me/library/playlists/\(playlistID)/tracks"
      var tracks: [KeepLibraryTrack] = []
      while let page = next {
        let response = try await Self.getTrackPage(path: page)
        tracks += response.data.map { KeepLibraryTrack(title: $0.attributes.name, artist: $0.attributes.artistName) }
        next = response.next
      }
      return tracks
    },
    append: { playlistID, song in
      let body = try AppleMusicPlaylistRequestEncoder.appendBody(songs: [song])
      _ = try await Self.request(path: "/v1/me/library/playlists/\(playlistID)/tracks", method: "POST", body: body)
    }
  )

  private static func getPage(path: String) async throws -> PlaylistPage {
    guard let url = path.hasPrefix("https://") ? URL(string: path) : URL(string: "https://api.music.apple.com\(path)") else {
      throw KeepLibraryError(statusCode: 0, detail: "Apple Music returned an invalid pagination URL.")
    }
    let response = try await request(url: url, method: "GET", body: nil)
    do { return try JSONDecoder().decode(PlaylistPage.self, from: response.data) }
    catch { throw KeepLibraryError(statusCode: response.urlResponse.statusCode,
      detail: "Apple Music returned an unreadable playlist response: \(error.localizedDescription)") }
  }

  private static func getTrackPage(path: String) async throws -> TrackPage {
    guard let url = path.hasPrefix("https://") ? URL(string: path) : URL(string: "https://api.music.apple.com\(path)") else {
      throw KeepLibraryError(statusCode: 0, detail: "Apple Music returned an invalid pagination URL.")
    }
    let response = try await request(url: url, method: "GET", body: nil)
    do { return try JSONDecoder().decode(TrackPage.self, from: response.data) }
    catch { throw KeepLibraryError(statusCode: response.urlResponse.statusCode,
      detail: "Apple Music returned an unreadable playlist tracks response: \(error.localizedDescription)") }
  }

  private static func request(path: String, method: String, body: Data) async throws -> MusicDataResponse {
    guard let url = URL(string: "https://api.music.apple.com\(path)") else {
      throw KeepLibraryError(statusCode: 0, detail: "The Apple Music API URL is invalid.")
    }
    return try await request(url: url, method: method, body: body)
  }

  private static func request(url: URL, method: String, body: Data?) async throws -> MusicDataResponse {
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }
    let response: MusicDataResponse
    do {
      response = try await MusicDataRequest(urlRequest: request).response()
    } catch let error as MusicDataRequest.Error {
      throw KeepLibraryError(statusCode: error.status, detail: error.detailText)
    }
    guard (200..<300).contains(response.urlResponse.statusCode) else {
      let detail = (try? JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        .flatMap { ($0["errors"] as? [[String: Any]])?.first?["detail"] as? String }
        ?? String(data: response.data, encoding: .utf8)
        ?? "Apple Music did not provide an error detail."
      throw KeepLibraryError(statusCode: response.urlResponse.statusCode, detail: detail)
    }
    return response
  }
}

private struct PlaylistPage: Decodable {
  var data: [Playlist]
  var next: String?

  struct Playlist: Decodable {
    var id: String
    var attributes: Attributes
    struct Attributes: Decodable { var name: String; var canEdit: Bool? }
  }

}

private struct TrackPage: Decodable {
  var data: [Track]
  var next: String?
  struct Track: Decodable {
    var id: String
    var attributes: Attributes
    struct Attributes: Decodable { var name: String; var artistName: String }
  }
}

private struct KeepLibraryError: LocalizedError {
  var statusCode: Int
  var detail: String
  var errorDescription: String? { "Apple Music returned HTTP \(statusCode): \(detail)" }
}

extension DependencyValues {
  var keepLibraryClient: KeepLibraryClient {
    get { self[KeepLibraryClientKey.self] }
    set { self[KeepLibraryClientKey.self] = newValue }
  }
}
