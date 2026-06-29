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
  public var readAlbumTracks: @Sendable (_ request: MusicAlbumReadRequest) async throws -> [ImportedTrackRef]
}

public struct MusicAlbumReadRequest: Equatable, Sendable {
  public var albumTitle: String

  public init(albumTitle: String) {
    self.albumTitle = albumTitle
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
