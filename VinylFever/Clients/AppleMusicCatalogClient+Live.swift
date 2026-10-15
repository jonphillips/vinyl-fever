import Foundation
import MusicKit
import VinylFeverCore

extension AppleMusicCatalogClient {
  static var liveValue: Self {
    Self(
      authorizationStatus: {
        Self.authorization(MusicAuthorization.currentStatus)
      },
      requestAuthorization: {
        Self.authorization(await MusicAuthorization.request())
      },
      subscriptionStatus: {
        let subscription = try await MusicSubscription.current
        return AppleMusicSubscriptionStatus(
          canPlayCatalogContent: subscription.canPlayCatalogContent,
          hasCloudLibraryEnabled: subscription.hasCloudLibraryEnabled
        )
      },
      searchSongs: { term, limit in
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = min(25, max(1, limit))
        let response: MusicCatalogSearchResponse
        do {
          response = try await request.response()
        } catch let error as MusicDataRequest.Error {
          if error.status == 429 { throw AppleMusicCatalogBusyError() }
          throw AppleMusicAPIError(statusCode: error.status, detail: error.detailText)
        } catch where Self.isUnreadableResponse(error) {
          // A 429 arrives with a plain-text "API capacity exceeded" body. MusicKit fails to
          // decode it and throws a decoding error that never mentions the status code.
          throw AppleMusicCatalogBusyError()
        }
        return response.songs.map { song in
          CatalogSongCandidate(
            id: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            releaseDate: song.releaseDate,
            durationSeconds: song.duration,
            isrc: song.isrc
          )
        }
      },
      createLibraryPlaylist: { name, description, songIDs in
        guard !songIDs.isEmpty else {
          throw PlaylistCreationError.noTracks
        }
        let firstChunk = Array(songIDs.prefix(100))
        let body = PlaylistCreateBody(
          attributes: .init(name: name, description: description),
          relationships: .init(tracks: .init(data: firstChunk.map(PlaylistTrackData.song)))
        )
        let data = try JSONEncoder().encode(body)
        let response = try await Self.perform(
          path: "/v1/me/library/playlists",
          method: "POST",
          body: data
        )
        let created: PlaylistCreateResponse
        do {
          created = try JSONDecoder().decode(PlaylistCreateResponse.self, from: response.data)
        } catch {
          throw PlaylistCreationError.invalidResponse(error.localizedDescription)
        }
        guard let playlist = created.data.first else {
          throw PlaylistCreationError.invalidResponse("Apple Music did not return the created playlist.")
        }
        for chunk in songIDs.dropFirst(firstChunk.count).chunked(into: 100) {
          try await Self.append(chunk, to: playlist.id)
        }
        return CreatedPlaylistRef(id: playlist.id, name: name, trackCount: songIDs.count)
      },
      appendToLibraryPlaylist: { id, songIDs in
        for chunk in songIDs.chunked(into: 100) {
          try await Self.append(chunk, to: id)
        }
      }
    )
  }

  private static func authorization(_ status: MusicAuthorization.Status) -> MusicKitAuthorization {
    switch status {
    case .authorized: .authorized
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .unknown
    }
  }

  private static func append(_ songIDs: [String], to playlistID: String) async throws {
    let data = try JSONEncoder().encode(PlaylistTracksBody(data: songIDs.map(PlaylistTrackData.song)))
    _ = try await perform(
      path: "/v1/me/library/playlists/\(playlistID)/tracks",
      method: "POST",
      body: data
    )
  }

  /// MusicDataRequest supplies the user and developer tokens for this Apple Music API request.
  private static func perform(path: String, method: String, body: Data) async throws -> MusicDataResponse {
    guard let url = URL(string: "https://api.music.apple.com\(path)") else {
      throw PlaylistCreationError.invalidResponse("The Apple Music API URL is invalid.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    let response: MusicDataResponse
    do {
      response = try await MusicDataRequest(urlRequest: request).response()
    } catch let error as MusicDataRequest.Error {
      throw AppleMusicAPIError(statusCode: error.status, detail: error.detailText)
    }
    guard (200..<300).contains(response.urlResponse.statusCode) else {
      throw AppleMusicAPIError(
        statusCode: response.urlResponse.statusCode,
        detail: Self.apiErrorDetail(from: response.data)
      )
    }
    return response
  }

  private static func isUnreadableResponse(_ error: any Error) -> Bool {
    if error is DecodingError { return true }
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain
      && [CocoaError.coderReadCorrupt.rawValue, CocoaError.propertyListReadCorrupt.rawValue].contains(nsError.code)
  }

  private static func apiErrorDetail(from data: Data) -> String {
    if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let errors = payload["errors"] as? [[String: Any]],
      let detail = errors.first?["detail"] as? String {
      return detail
    }
    return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
      ?? "Apple Music did not provide an error detail."
  }
}

private enum PlaylistCreationError: LocalizedError {
  case noTracks
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .noTracks: "Choose at least one matched song before creating a playlist."
    case let .invalidResponse(detail): "Apple Music returned an unreadable playlist response: \(detail)"
    }
  }
}

// The request shape follows Apple's Music API. The concise playlist creation payload is
// adapted from MusadoraKit's MIT-licensed LibraryPlaylistCreationRequest and post technique
// (https://github.com/rryam/MusadoraKit).
private struct PlaylistCreateBody: Encodable {
  var attributes: Attributes
  var relationships: Relationships

  struct Attributes: Encodable {
    var name: String
    var description: String?
  }

  struct Relationships: Encodable {
    var tracks: Tracks
  }

  struct Tracks: Encodable {
    var data: [PlaylistTrackData]
  }
}

private struct PlaylistTracksBody: Encodable {
  var data: [PlaylistTrackData]
}

private struct PlaylistTrackData: Encodable {
  var id: String
  var type = "songs"

  static func song(_ id: String) -> Self { Self(id: id) }
}

private struct PlaylistCreateResponse: Decodable {
  var data: [Playlist]

  struct Playlist: Decodable {
    var id: String
  }
}

private extension Collection {
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [] }
    var chunks: [[Element]] = []
    var start = startIndex
    while start != endIndex {
      let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(Array(self[start..<end]))
      start = end
    }
    return chunks
  }
}
