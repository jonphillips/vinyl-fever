import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct MusicAppClient: Sendable {
  public var automationPermission: @Sendable () async -> MusicAutomationPermission = {
    .unavailable("Music automation is not configured.")
  }
  public var requestAutomationPermission: @Sendable () async -> MusicAutomationPermission = {
    .unavailable("Music automation is not configured.")
  }
  public var add: @Sendable (_ urls: [URL]) async throws -> [ImportedTrackRef]
  /// Copies `urls` into Music's "Automatically Add" `watchFolder` so Music's folder
  /// watcher imports them on its own schedule. Unlike `add`, this sends no Apple Event
  /// and cannot time out on a busy Music; the caller confirms the import by polling
  /// `readAlbumTracks`.
  public var importViaWatchFolder: @Sendable (_ urls: [URL], _ watchFolder: URL) async throws -> Void
  public var readAlbumTracks: @Sendable (_ request: MusicAlbumReadRequest) async throws -> [ImportedTrackRef]
}

public struct MusicAlbumReadRequest: Equatable, Sendable {
  public var albumTitle: String
  public var albumArtist: String?
  public var includesTitleSiblings: Bool

  public init(albumTitle: String, albumArtist: String? = nil, includesTitleSiblings: Bool = false) {
    self.albumTitle = albumTitle
    self.albumArtist = albumArtist
    self.includesTitleSiblings = includesTitleSiblings
  }

  public init(identity: AlbumIdentity, includesTitleSiblings: Bool = false) {
    self.init(
      albumTitle: identity.album,
      albumArtist: identity.albumArtist,
      includesTitleSiblings: includesTitleSiblings
    )
  }
}

public enum MusicAutomationPermission: Equatable, Sendable {
  case authorized
  case notDetermined
  case denied
  case unavailable(String)

  public var isAuthorized: Bool {
    self == .authorized
  }

  public var displayMessage: String {
    switch self {
    case .authorized:
      "Music automation is allowed."
    case .notDetermined:
      "Music automation permission has not been granted yet."
    case .denied:
      "Music automation is denied. Allow Vinyl Fever in System Settings > Privacy & Security > Automation > Music."
    case let .unavailable(message):
      message
    }
  }
}

extension MusicAppClient: TestDependencyKey {
  public static var testValue: Self {
    Self()
  }
}

extension DependencyValues {
  public var musicAppClient: MusicAppClient {
    get { self[MusicAppClient.self] }
    set { self[MusicAppClient.self] = newValue }
  }
}
