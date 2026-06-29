import AppKit
import CoreServices
import Foundation
import ScriptingBridge
import VinylFeverCore

extension MusicAppClient {
  static var liveValue: Self {
    let bridge = LiveMusicAppBridge()
    return Self(
      automationPermission: {
        await bridge.automationPermission(askUserIfNeeded: false)
      },
      requestAutomationPermission: {
        await bridge.automationPermission(askUserIfNeeded: true)
      },
      readAlbumTracks: { request in
        try await bridge.readAlbumTracks(request)
      }
    )
  }
}

private struct LiveMusicAppBridge: Sendable {
  private static let musicBundleIdentifier = "com.apple.Music"

  func automationPermission(askUserIfNeeded: Bool) async -> MusicAutomationPermission {
    do {
      try await ensureMusicIsRunning()
      return await Self.determineAutomationPermission(askUserIfNeeded: askUserIfNeeded)
    } catch {
      return .unavailable(error.localizedDescription)
    }
  }

  func readAlbumTracks(_ request: MusicAlbumReadRequest) async throws -> [ImportedTrackRef] {
    try await ensureMusicIsRunning()
    let permission = await Self.determineAutomationPermission(askUserIfNeeded: false)
    guard permission == .authorized else {
      throw MusicAppLiveError.automationPermission(permission)
    }

    return try await Task.detached(priority: .userInitiated) {
      let application = try Self.musicApplication()
      let libraryPlaylist = try Self.libraryPlaylist(in: application)
      let tracks = try Self.objects(named: "fileTracks", on: libraryPlaylist)
      let requestedAlbum = AudioTagVerifier.normalizedMetadataString(request.albumTitle)
      return tracks
        .compactMap { track -> ImportedTrackRef? in
          let ref = Self.importedTrackRef(from: track)
          guard AudioTagVerifier.normalizedMetadataString(ref.album) == requestedAlbum else {
            return nil
          }
          return ref
        }
        .sorted { lhs, rhs in
          switch (lhs.trackNumber, rhs.trackNumber) {
          case let (lhs?, rhs?) where lhs != rhs:
            lhs < rhs
          case (nil, _?):
            false
          case (_?, nil):
            true
          default:
            (lhs.title ?? "") < (rhs.title ?? "")
          }
        }
    }
    .value
  }

  private func ensureMusicIsRunning() async throws {
    guard NSRunningApplication
      .runningApplications(withBundleIdentifier: Self.musicBundleIdentifier)
      .isEmpty
    else {
      return
    }
    guard let url = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: Self.musicBundleIdentifier
    ) else {
      throw MusicAppLiveError.musicAppUnavailable
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private static func determineAutomationPermission(
    askUserIfNeeded: Bool
  ) async -> MusicAutomationPermission {
    return await Task.detached(priority: .userInitiated) {
      do {
        var target = try musicAutomationTargetDescriptor()
        defer {
          AEDisposeDesc(&target)
        }
        let status = AEDeterminePermissionToAutomateTarget(
          &target,
          typeWildCard,
          typeWildCard,
          askUserIfNeeded
        )
        if status == noErr {
          return .authorized
        } else if status == OSStatus(errAEEventWouldRequireUserConsent) {
          return .notDetermined
        } else if status == OSStatus(errAEEventNotPermitted) {
          return .denied
        } else if status == OSStatus(procNotFound) {
          return .unavailable("Music is not running.")
        } else {
          return .unavailable("Music automation permission failed with OSStatus \(status).")
        }
      } catch {
        return .unavailable(error.localizedDescription)
      }
    }
    .value
  }

  private static func musicAutomationTargetDescriptor() throws -> AEAddressDesc {
    guard let data = musicBundleIdentifier.data(using: .utf8) else {
      throw MusicAppLiveError.musicAppUnavailable
    }

    var target = AEAddressDesc()
    let status = data.withUnsafeBytes { buffer in
      AECreateDesc(
        typeApplicationBundleID,
        buffer.baseAddress,
        buffer.count,
        &target
      )
    }
    guard status == noErr else {
      throw MusicAppLiveError.appleEventDescriptorFailed(OSStatus(status))
    }
    return target
  }

  private static func musicApplication() throws -> SBApplication {
    guard let application = SBApplication(bundleIdentifier: musicBundleIdentifier) else {
      throw MusicAppLiveError.musicAppUnavailable
    }
    return application
  }

  private static func libraryPlaylist(in application: SBApplication) throws -> SBObject {
    for source in try objects(named: "sources", on: application) {
      let playlists = (try? objects(named: "libraryPlaylists", on: source)) ?? []
      if let playlist = playlists.first {
        return playlist
      }
    }
    throw MusicAppLiveError.libraryPlaylistUnavailable
  }

  private static func objects(named key: String, on object: NSObject) throws -> [SBObject] {
    guard let elementArray = object.value(forKey: key) as? SBElementArray else {
      throw MusicAppLiveError.scriptingBridgeReadFailed(key)
    }
    return elementArray.get() as? [SBObject] ?? []
  }

  private static func importedTrackRef(from track: SBObject) -> ImportedTrackRef {
    ImportedTrackRef(
      id: stringValue(named: "persistentID", on: track) ?? "",
      title: stringValue(named: "name", on: track),
      album: stringValue(named: "album", on: track),
      trackNumber: intValue(named: "trackNumber", on: track),
      durationSeconds: doubleValue(named: "duration", on: track),
      location: track.value(forKey: "location") as? URL
    )
  }

  private static func stringValue(named key: String, on object: NSObject) -> String? {
    object.value(forKey: key) as? String
  }

  private static func intValue(named key: String, on object: NSObject) -> Int? {
    switch object.value(forKey: key) {
    case let value as Int:
      value
    case let value as NSNumber:
      value.intValue
    default:
      nil
    }
  }

  private static func doubleValue(named key: String, on object: NSObject) -> Double? {
    switch object.value(forKey: key) {
    case let value as Double:
      value
    case let value as NSNumber:
      value.doubleValue
    default:
      nil
    }
  }
}

private enum MusicAppLiveError: LocalizedError {
  case appleEventDescriptorFailed(OSStatus)
  case automationPermission(MusicAutomationPermission)
  case libraryPlaylistUnavailable
  case musicAppUnavailable
  case scriptingBridgeReadFailed(String)

  var errorDescription: String? {
    switch self {
    case let .appleEventDescriptorFailed(status):
      "Could not prepare the Music automation target descriptor: OSStatus \(status)."
    case let .automationPermission(permission):
      permission.displayMessage
    case .libraryPlaylistUnavailable:
      "Music's library playlist could not be read."
    case .musicAppUnavailable:
      "Music.app could not be found."
    case let .scriptingBridgeReadFailed(key):
      "Music scripting bridge value '\(key)' could not be read."
    }
  }
}
