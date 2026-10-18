import Dependencies
import DependenciesMacros
import Foundation
import LLMHandoffKit

public struct StagedPlaylistSummary: Identifiable, Sendable {
  public let handoff: StagedHandoff
  public let name: String
  public let trackCount: Int
  public var id: URL { handoff.url }

  public init(handoff: StagedHandoff, name: String, trackCount: Int) {
    self.handoff = handoff
    self.name = name
    self.trackCount = trackCount
  }
}

@DependencyClient
public struct PlaylistInboxClient: Sendable {
  public var list: @Sendable () throws -> [StagedPlaylistSummary]
  public var read: @Sendable (_ item: StagedHandoff) throws -> String
  public var markProcessed: @Sendable (_ item: StagedHandoff) throws -> StagedHandoff
}

extension PlaylistInboxClient: TestDependencyKey {
  public static var testValue: Self { Self() }
}

extension PlaylistInboxClient: DependencyKey {
  public static var liveValue: Self {
    live(root: FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/VinylFever/PlaylistInbox", directoryHint: .isDirectory))
  }
}

extension PlaylistInboxClient {
  public static func live(root: URL) -> Self {
    let inbox = HandoffInbox(root: root, fileExtension: "vfplaylist")
    return Self(
      list: {
        try inbox.list().map { item in
          let decoded = try? PlaylistContract.decode(inbox.read(item))
          return StagedPlaylistSummary(
            handoff: item, name: decoded?.request.name ?? item.slug,
            trackCount: decoded?.request.tracks.count ?? 0
          )
        }
      },
      read: { try inbox.read($0) },
      markProcessed: { try inbox.markProcessed($0) }
    )
  }
}

extension DependencyValues {
  public var playlistInboxClient: PlaylistInboxClient {
    get { self[PlaylistInboxClient.self] }
    set { self[PlaylistInboxClient.self] = newValue }
  }
}
