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
  var libraryPlaylists: @Sendable () async throws -> [KeepLibraryPlaylist]
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
      try await Task.detached { try PlaylistRolesFolderReader.read() }.value
    },
    libraryPlaylists: {
      var next: String? = "/v1/me/library/playlists"
      var playlists: [KeepLibraryPlaylist] = []
      while let page = next {
        let response = try await Self.getPage(path: page)
        playlists += response.data.map { KeepLibraryPlaylist(id: $0.id, name: $0.attributes.name) }
        next = response.next
      }
      return playlists
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

private enum PlaylistRolesFolderReader {
  // Match RecommendationLedgerFolderReader's established iCloud read deadline.
  private static let deadline: TimeInterval = 8

  private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<PlaylistRoles?, Error>?

    func store(_ result: Result<PlaylistRoles?, Error>) {
      lock.lock(); self.result = result; lock.unlock()
    }

    func load() -> Result<PlaylistRoles?, Error>? {
      lock.lock(); defer { lock.unlock() }; return result
    }
  }

  static func read() throws -> PlaylistRoles? {
    let group = DispatchGroup()
    let result = ResultBox()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      defer { group.leave() }
      do {
        let roles = try ProbeBookmarkStore.withFolder { folder -> PlaylistRoles? in
          let url = folder.appending(path: "Taste Intelligence/playlist-roles.json")
          try? FileManager.default.startDownloadingUbiquitousItem(at: url)
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
        result.store(.success(roles))
      } catch {
        result.store(.failure(error))
      }
    }

    let timeout = DispatchTimeInterval.milliseconds(Int(deadline * 1_000))
    guard group.wait(timeout: .now() + timeout) == .success else { throw RolesReadTimedOut() }
    return try result.load()?.get()
  }
}

private struct RolesReadTimedOut: LocalizedError {
  var errorDescription: String? { "Playlist roles did not finish loading before the deadline." }
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
