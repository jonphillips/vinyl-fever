import CryptoKit
import Foundation
import SQLiteData

@Table
public struct AppSetting: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var metaflacPath: String?
  public var ffmpegPath: String?
  public var ffprobePath: String?

  public init(
    id: UUID = Self.singletonID,
    metaflacPath: String? = nil,
    ffmpegPath: String? = nil,
    ffprobePath: String? = nil
  ) {
    self.id = id
    self.metaflacPath = Self.normalizedPath(metaflacPath)
    self.ffmpegPath = Self.normalizedPath(ffmpegPath)
    self.ffprobePath = Self.normalizedPath(ffprobePath)
  }
}

extension AppSetting {
  public static let singletonID = stableID(
    namespace: "VinylFever.AppSetting.v1:singleton"
  )

  public static var `default`: Self {
    Self()
  }

  public static func current(from settings: [Self]) -> Self {
    if let singleton = settings.first(where: { $0.id == singletonID }) {
      return singleton
    }

    return settings
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .first ?? .default
  }

  public var toolPathOverrides: ToolPathOverrides {
    ToolPathOverrides(
      metaflacPath: metaflacPath,
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath
    )
  }

  public func withOverridePath(_ path: String?, for tool: AudioTool) -> Self {
    var copy = self
    copy.setOverridePath(path, for: tool)
    return copy
  }

  public mutating func setOverridePath(_ path: String?, for tool: AudioTool) {
    let path = Self.normalizedPath(path)
    switch tool {
    case .metaflac:
      metaflacPath = path
    case .ffmpeg:
      ffmpegPath = path
    case .ffprobe:
      ffprobePath = path
    }
  }

  fileprivate static func normalizedPath(_ path: String?) -> String? {
    guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
      return nil
    }
    return path
  }

  private static func stableID(namespace: String) -> UUID {
    let digest = SHA256.hash(data: Data(namespace.utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x80
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}

public struct ToolPathOverrides: Equatable, Hashable, Sendable {
  public var metaflacPath: String?
  public var ffmpegPath: String?
  public var ffprobePath: String?

  public init(
    metaflacPath: String? = nil,
    ffmpegPath: String? = nil,
    ffprobePath: String? = nil
  ) {
    self.metaflacPath = AppSetting.normalizedPath(metaflacPath)
    self.ffmpegPath = AppSetting.normalizedPath(ffmpegPath)
    self.ffprobePath = AppSetting.normalizedPath(ffprobePath)
  }

  public func path(for tool: AudioTool) -> String? {
    switch tool {
    case .metaflac:
      metaflacPath
    case .ffmpeg:
      ffmpegPath
    case .ffprobe:
      ffprobePath
    }
  }
}
