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
      add: { urls in
        try await bridge.add(urls)
      },
      readAlbumTracks: { request in
        try await bridge.readAlbumTracks(request)
      }
    )
  }
}

private struct LiveMusicAppBridge: Sendable {
  private static let musicBundleIdentifier = "com.apple.Music"
  /// Ceiling for a scoped album read; a healthy read returns in well under this.
  private static let readTimeout: Duration = .seconds(30)
  /// Ceiling for importing files; copying into the Media folder can be slower.
  private static let addTimeout: Duration = .seconds(120)

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

    return try await Self.withTimeout(Self.readTimeout) {
      try await Task.detached(priority: .userInitiated) {
        let application = try Self.musicApplication()
        let libraryPlaylist = try Self.libraryPlaylist(in: application)
        let tracks = try Self.scopedFileTracks(on: libraryPlaylist, request: request)
        let requestedAlbum = AudioTagVerifier.normalizedMetadataString(request.albumTitle)
        let requestedAlbumArtist = AudioTagVerifier.normalizedMetadataString(request.albumArtist)
        return tracks
          .compactMap { track -> ImportedTrackRef? in
            let ref = Self.importedTrackRef(from: track)
            let album = AudioTagVerifier.normalizedMetadataString(ref.album)
            let albumArtist = AudioTagVerifier.normalizedMetadataString(ref.albumArtist)
            guard album == requestedAlbum || (request.includesTitleSiblings && Self.isTitleSibling(album, of: requestedAlbum)) else {
              return nil
            }
            guard requestedAlbumArtist == nil || albumArtist == requestedAlbumArtist || request.includesTitleSiblings else {
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
  }

  func add(_ urls: [URL]) async throws -> [ImportedTrackRef] {
    try await ensureMusicIsRunning()
    let permission = await Self.determineAutomationPermission(askUserIfNeeded: false)
    guard permission == .authorized else {
      throw MusicAppLiveError.automationPermission(permission)
    }

    return try await Self.withTimeout(Self.addTimeout) {
      try await Task.detached(priority: .userInitiated) {
        let application = try Self.musicApplication()
        let playlist = try Self.libraryPlaylist(in: application)
        let standardizedURLs = urls.map(\.standardizedFileURL)
        let result = (application as MusicScriptingApplication)
          .add?(standardizedURLs as NSArray, to: playlist)
        return Self.importedTrackRefs(from: result)
      }
      .value
    }
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

  /// Reads only the library file tracks that could plausibly belong to the requested
  /// album, instead of materializing every `fileTrack` in the library and filtering in
  /// Swift. The `whose` predicate is pushed to Music (`filtered(using:)` on the lazy
  /// `SBElementArray`), so on a large library the Apple Event returns a small set. The
  /// predicate is a deliberate *superset* — a case/diacritic-insensitive match on the
  /// album's first token — because the caller re-applies the exact album/albumArtist and
  /// title-sibling filter; scoping must never drop a track the precise filter would keep.
  private static func scopedFileTracks(
    on libraryPlaylist: SBObject,
    request: MusicAlbumReadRequest
  ) throws -> [SBObject] {
    guard let elementArray = libraryPlaylist.value(forKey: "fileTracks") as? SBElementArray else {
      throw MusicAppLiveError.scriptingBridgeReadFailed("fileTracks")
    }
    guard let fragment = albumScopingFragment(request.albumTitle) else {
      return elementArray.get() as? [SBObject] ?? []
    }
    let predicate = NSPredicate(format: "album CONTAINS[cd] %@", fragment)
    return elementArray.filtered(using: predicate) as? [SBObject] ?? []
  }

  /// The first whitespace-delimited token of the album title, used as a safe scoping
  /// fragment. A single token has no internal whitespace, so a `CONTAINS` predicate on
  /// it can't be defeated by whitespace variance in Music's stored tag; `nil` when the
  /// title is blank (in which case the caller falls back to the full read).
  private static func albumScopingFragment(_ albumTitle: String) -> String? {
    let trimmed = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let token = trimmed.split(whereSeparator: \.isWhitespace).first else {
      return nil
    }
    return String(token)
  }

  /// Races `operation` against a deadline so a stuck Apple Event surfaces as an error
  /// instead of hanging the caller indefinitely. If the deadline wins, the operation's
  /// detached work is abandoned (a synchronous Apple Event can't be interrupted) but the
  /// caller is freed with `MusicAppLiveError.timedOut`.
  ///
  /// A structured `TaskGroup` would await the loser before returning — which would still
  /// block on the stuck operation — so the race is run as two unstructured tasks feeding
  /// one continuation, guarded so it resumes exactly once.
  private static func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let flag = OnceFlag()
    return try await withCheckedThrowingContinuation { continuation in
      Task {
        do {
          let value = try await operation()
          if flag.claim() { continuation.resume(returning: value) }
        } catch {
          if flag.claim() { continuation.resume(throwing: error) }
        }
      }
      Task {
        try? await Task.sleep(for: timeout)
        if flag.claim() { continuation.resume(throwing: MusicAppLiveError.timedOut) }
      }
    }
  }

  private static func importedTrackRefs(from result: Any?) -> [ImportedTrackRef] {
    switch result {
    case let track as SBObject:
      return [importedTrackRef(from: track)]
    case let tracks as [SBObject]:
      return tracks.map(importedTrackRef(from:))
    case let elementArray as SBElementArray:
      return (elementArray.get() as? [SBObject] ?? []).map(importedTrackRef(from:))
    case let array as NSArray:
      return array.compactMap { $0 as? SBObject }.map(importedTrackRef(from:))
    default:
      return []
    }
  }

  private static func importedTrackRef(from track: SBObject) -> ImportedTrackRef {
    ImportedTrackRef(
      id: stringValue(named: "persistentID", on: track) ?? "",
      title: stringValue(named: "name", on: track),
      album: stringValue(named: "album", on: track),
      albumArtist: stringValue(named: "albumArtist", on: track),
      trackNumber: intValue(named: "trackNumber", on: track),
      durationSeconds: doubleValue(named: "duration", on: track),
      location: track.value(forKey: "location") as? URL
    )
  }

  private static func isTitleSibling(_ title: String?, of target: String?) -> Bool {
    guard let title, let target else {
      return false
    }
    let titleKey = duplicateTitleKey(title)
    let targetKey = duplicateTitleKey(target)
    return titleKey == targetKey || titleKey.hasPrefix(targetKey + " ")
  }

  private static func duplicateTitleKey(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
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

/// One-shot claim guard so a timeout race resumes its continuation exactly once.
private final class OnceFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed {
      return false
    }
    claimed = true
    return true
  }
}

@objc
private protocol MusicScriptingApplication {
  @objc optional func add(_ urls: NSArray, to playlist: SBObject?) -> Any?
}

extension SBApplication: MusicScriptingApplication {
}

private enum MusicAppLiveError: LocalizedError {
  case appleEventDescriptorFailed(OSStatus)
  case automationPermission(MusicAutomationPermission)
  case libraryPlaylistUnavailable
  case musicAppUnavailable
  case scriptingBridgeReadFailed(String)
  case timedOut

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
    case .timedOut:
      "Music did not respond in time. It may be busy or blocked on a dialog; try again."
    }
  }
}
