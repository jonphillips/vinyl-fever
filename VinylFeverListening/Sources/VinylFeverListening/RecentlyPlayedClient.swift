import Dependencies
import DependenciesMacros
import Foundation
import MusicKit

@DependencyClient
public struct RecentlyPlayedClient: Sendable {
  public var page: @Sendable (_ offset: Int) async throws -> RecentlyPlayedPage
}

public struct RecentlyPlayedPage: Equatable, Sendable {
  public var items: [ListeningItem]
  public var hasNext: Bool

  public init(items: [ListeningItem], hasNext: Bool) {
    self.items = items
    self.hasNext = hasNext
  }
}

extension RecentlyPlayedClient: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension RecentlyPlayedClient: DependencyKey {
  public static var liveValue: Self {
    Self(page: { offset in
      let request = try Self.request(offset: offset)
      let response: MusicDataResponse
      do {
        response = try await MusicDataRequest(urlRequest: request).response()
      } catch let error as MusicDataRequest.Error {
        guard !(200..<300).contains(error.status) else { throw error }
        throw RecentlyPlayedError.httpStatus(
          error.status,
          detail: Self.joinedErrorDetail(title: error.title, detail: error.detailText)
        )
      }
      guard (200..<300).contains(response.urlResponse.statusCode) else {
        throw Self.httpError(status: response.urlResponse.statusCode, body: response.data)
      }
      let payload = try JSONDecoder().decode(RecentlyPlayedResponse.self, from: response.data)
      return RecentlyPlayedPage(items: try payload.data.map { try $0.listeningItem }, hasNext: payload.next != nil)
    })
  }

  public static func request(offset: Int) throws -> URLRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.music.apple.com"
    components.path = "/v1/me/recent/played/tracks"
    components.queryItems = [
      URLQueryItem(name: "types", value: "songs,library-songs"),
      URLQueryItem(name: "limit", value: String(ListeningDiff.pageSize)),
      URLQueryItem(name: "offset", value: String(offset)),
    ]
    guard let url = components.url else {
      throw RecentlyPlayedError.invalidEndpoint
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    return request
  }

  static func httpError(status: Int, body: Data) -> RecentlyPlayedError {
    let response = try? JSONDecoder().decode(AppleMusicErrorResponse.self, from: body)
    let error = response?.errors?.first
    return .httpStatus(
      status,
      detail: joinedErrorDetail(title: error?.title, detail: error?.detail)
    )
  }

  static func joinedErrorDetail(title: String?, detail: String?) -> String? {
    let parts = [title, detail].compactMap { value -> String? in
      guard let value, !value.isEmpty else { return nil }
      return value
    }
    return parts.isEmpty ? nil : parts.joined(separator: ": ")
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
  case httpStatus(Int, detail: String?)
  case unsupportedResource(String)

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint: "Apple Music's recently-played endpoint is invalid."
    case let .httpStatus(status, detail):
      if let detail {
        "Apple Music returned HTTP \(status) (\(detail))."
      } else {
        "Apple Music returned HTTP \(status)."
      }
    case let .unsupportedResource(type): "Apple Music returned an unsupported track type: \(type)."
    }
  }
}

private struct AppleMusicErrorResponse: Decodable {
  var errors: [Item]?

  struct Item: Decodable {
    var title: String?
    var detail: String?
  }
}

private struct RecentlyPlayedResponse: Decodable {
  var data: [Resource]
  var next: String?

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
