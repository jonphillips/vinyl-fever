import Dependencies
import DependenciesMacros
import Foundation
import MusicKit

@DependencyClient
public struct RecentlyPlayedClient: Sendable {
  public var page: @Sendable (_ offset: Int) async throws -> [ListeningItem]
}

extension RecentlyPlayedClient: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension RecentlyPlayedClient: DependencyKey {
  public static var liveValue: Self {
    Self(page: { offset in
      var components = URLComponents()
      components.scheme = "https"
      components.host = "api.music.apple.com"
      components.path = "/v1/me/recent/played/tracks"
      components.queryItems = [
        URLQueryItem(name: "types", value: "songs,library-songs"),
        URLQueryItem(name: "offset", value: String(offset)),
      ]
      guard let url = components.url else {
        throw RecentlyPlayedError.invalidEndpoint
      }
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      let response = try await MusicDataRequest(urlRequest: request).response()
      guard (200..<300).contains(response.urlResponse.statusCode) else {
        throw RecentlyPlayedError.httpStatus(response.urlResponse.statusCode)
      }
      let page = try JSONDecoder().decode(RecentlyPlayedPage.self, from: response.data)
      return try page.data.map { try $0.listeningItem }
    })
  }
}

extension DependencyValues {
  public var recentlyPlayedClient: RecentlyPlayedClient {
    get { self[RecentlyPlayedClient.self] }
    set { self[RecentlyPlayedClient.self] = newValue }
  }
}

public enum RecentlyPlayedError: Error, LocalizedError, Equatable, Sendable {
  case invalidEndpoint
  case httpStatus(Int)
  case unsupportedResource(String)

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "Apple Music's recently-played endpoint is invalid."
    case let .httpStatus(status): "Apple Music returned HTTP \(status)."
    case let .unsupportedResource(type): "Apple Music returned an unsupported track type: \(type)."
    }
  }
}

private struct RecentlyPlayedPage: Decodable {
  var data: [Resource]

  struct Resource: Decodable {
    var id: String
    var type: String
    var attributes: Attributes

    var listeningItem: ListeningItem {
      get throws {
        let kind: ListeningItem.Kind
        switch type {
        case "songs": kind = .song
        case "library-songs": kind = .librarySong
        default: throw RecentlyPlayedError.unsupportedResource(type)
        }
        return ListeningItem(
          kind: kind,
          id: id,
          title: attributes.name,
          artist: attributes.artistName,
          album: attributes.albumName,
          durationSeconds: attributes.durationInMillis.map { Double($0) / 1_000 }
        )
      }
    }
  }

  struct Attributes: Decodable {
    var name: String
    var artistName: String
    var albumName: String?
    var durationInMillis: Int?
  }
}
