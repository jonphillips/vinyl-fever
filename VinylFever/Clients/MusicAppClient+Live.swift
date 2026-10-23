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
      importViaWatchFolder: { urls, watchFolder in
        try await bridge.importViaWatchFolder(urls, into: watchFolder)
      },
      readAlbumTracks: { request in
        try await bridge.readAlbumTracks(request)
      },
      readLibrarySnapshot: {
        try await bridge.readLibrarySnapshot()
      }
    )
  }
}

private struct LiveMusicAppBridge: Sendable {
  private static let musicBundleIdentifier = "com.apple.Music"
  /// Ceiling for a scoped album read; a healthy read returns in well under this.
  private static let readTimeout: Duration = .seconds(30)
  /// Ceiling for a full library snapshot read. Not the gate's read budget (30 s), which is
  /// measured, not enforced: ~25 s for 87k tracks on Jon's Mac, so 30 s would fail a busy Music.
  private static let snapshotReadTimeout: Duration = .seconds(120)
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
        return
          tracks
          .compactMap { track -> ImportedTrackRef? in
            let ref = Self.importedTrackRef(from: track)
            let album = AudioTagVerifier.normalizedMetadataString(ref.album)
            let albumArtist = AudioTagVerifier.normalizedMetadataString(ref.albumArtist)
            guard
              album == requestedAlbum
                || (request.includesTitleSiblings && Self.isTitleSibling(album, of: requestedAlbum))
            else {
              return nil
            }
            guard
              requestedAlbumArtist == nil || albumArtist == requestedAlbumArtist
                || request.includesTitleSiblings
            else {
              return nil
            }
            return ref
          }
          .sorted { lhs, rhs in
            switch (lhs.trackNumber, rhs.trackNumber) {
            case (let lhs?, let rhs?) where lhs != rhs:
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

  func readLibrarySnapshot() async throws -> LibrarySnapshot {
    try await ensureMusicIsRunning()
    let permission = await Self.determineAutomationPermission(askUserIfNeeded: false)
    guard permission == .authorized else {
      throw MusicAppLiveError.automationPermission(permission)
    }
    return try await Self.withTimeout(Self.snapshotReadTimeout) {
      try await Task.detached(priority: .userInitiated) {
        var columns: [String: [Any]] = [:]
        for property in LibraryBulkProperty.all {
          columns[property.key] = try Self.readEveryTrackProperty(property)
        }
        let count = columns["persistentID"]?.count ?? 0
        let mismatched = LibraryBulkProperty.all.filter { columns[$0.key]?.count != count }
        guard mismatched.isEmpty else {
          // The library changed between events (an iCloud sync, say); a retry usually succeeds.
          let detail = mismatched.map { "\($0.key)=\(columns[$0.key]?.count ?? 0)" }
          throw MusicAppLiveError.scriptingBridgeReadFailed(
            "track columns (persistentID=\(count), \(detail.joined(separator: ", "))); try again")
        }
        let result = try (0..<count).map {
          try LibraryTrack(bulkColumns: columns, index: $0)
        }
        let (playlists, outsideTracks) = try Self.readPlaylists(in: Self.musicApplication(), libraryTrackIDs: Set(result.map(\.persistentID)))
        return LibrarySnapshot(generatedAt: Date(), tracks: result, playlists: playlists, outsideTracks: outsideTracks)
      }.value
    }
  }

  /// Sends one `get <property> of every track of library playlist 1` event. ScriptingBridge's
  /// bulk `value(forKey:)` drops `missing value` entries (a never-played track has no played
  /// date), which shifts the column; the raw reply keeps one item per track, so columns zip.
  private static func readEveryTrackProperty(_ property: LibraryBulkProperty) throws -> [Any] {
    let libraryPlaylist = try objectSpecifier(
      "cLiP", form: "indx", data: NSAppleEventDescriptor(int32: 1), from: .null())
    var all = fourCharCode("all ")
    let everyTrack = try objectSpecifier(
      "cTrk", form: "indx",
      data: NSAppleEventDescriptor(descriptorType: fourCharCode("abso"), bytes: &all, length: 4)!,
      from: libraryPlaylist)
    let specifier = try objectSpecifier(
      "prop", form: "prop", data: NSAppleEventDescriptor(typeCode: fourCharCode(property.code)),
      from: everyTrack)
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
      targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: musicBundleIdentifier),
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(specifier, forKeyword: keyDirectObject)
    let reply = try event.sendEvent(
      options: [.waitForReply], timeout: TimeInterval(snapshotReadTimeout.components.seconds))
    guard let list = reply.paramDescriptor(forKeyword: keyDirectObject),
      list.descriptorType == typeAEList
    else {
      let status = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
      throw MusicAppLiveError.scriptingBridgeReadFailed("\(property.key) (OSStatus \(status))")
    }
    guard list.numberOfItems > 0 else { return [] }
    return (1...list.numberOfItems).map { index -> Any in
      guard let item = list.atIndex(index),
        !(item.descriptorType == typeType && item.typeCodeValue == fourCharCode("msng"))
      else { return NSNull() }
      return switch property.kind {
      case .text: item.stringValue ?? NSNull()
      case .integer: NSNumber(value: item.int32Value)
      case .real: NSNumber(value: item.doubleValue)
      case .date: item.dateValue ?? NSNull()
      case .boolean: NSNumber(value: item.booleanValue)
      case .enumeration: NSNumber(value: item.enumCodeValue)
      }
    }
  }

  private static func readPlaylists(in application: SBApplication, libraryTrackIDs: Set<String>) throws
    -> ([LibraryPlaylist], [String: LibraryOutsideTrack])
  {
    var rows: [LibraryPlaylist] = []
    var outside: [String: LibraryOutsideTrack] = [:]
    for source in try objects(named: "sources", on: application) {
      for (property, kind) in [("userPlaylists", LibraryPlaylistKind.user), ("subscriptionPlaylists", .subscription)] {
        for playlist in try objects(named: property, on: source) {
          guard playlist.value(forKey: "tracks") is SBElementArray else { continue }
          guard let playlistDescriptor = playlist.get() as? NSAppleEventDescriptor else {
            throw MusicAppLiveError.scriptingBridgeReadFailed("playlist descriptor")
          }
          let name = (playlist.value(forKey: "name") as? String) ?? ""
          let persistentID = (playlist.value(forKey: "persistentID") as? String) ?? ""
          guard !name.isEmpty, !persistentID.isEmpty, Self.hasNoSpecialKind(playlist) else { continue }
          let memberColumn = try Self.readEveryTrackProperty(.init(key: "persistentID", code: "pPIS", kind: .text), from: playlistDescriptor)
          guard memberColumn.allSatisfy({ $0 is String }) else {
            throw MusicAppLiveError.scriptingBridgeReadFailed("playlist member persistentID")
          }
          let memberIDs = memberColumn.compactMap { $0 as? String }
          let smart = (playlist.value(forKey: "smart") as? NSNumber)?.boolValue ?? false
          let playlistKind: LibraryPlaylistKind = kind == .user && smart ? .smart : kind
          let parentName = (playlist.value(forKey: "parent") as? SBObject)?.value(forKey: "name") as? String
          rows.append(LibraryPlaylist(persistentID: persistentID, name: name,
            folder: parentName == "Library" ? nil : parentName, kind: playlistKind, members: memberIDs))

          let hasOutsideMembers = memberIDs.contains { !libraryTrackIDs.contains($0) }
          guard hasOutsideMembers else { continue }
          var columns: [String: [Any]] = [:]
          for item in [
            LibraryBulkProperty(key: "name", code: "pnam", kind: .text),
            LibraryBulkProperty(key: "artist", code: "pArt", kind: .text),
            LibraryBulkProperty(key: "album", code: "pAlb", kind: .text),
            LibraryBulkProperty(key: "year", code: "pYr ", kind: .integer),
            LibraryBulkProperty(key: "duration", code: "pDur", kind: .real),
          ] { columns[item.key] = try readEveryTrackProperty(item, from: playlistDescriptor) }
          for (index, id) in memberIDs.enumerated() where !libraryTrackIDs.contains(id) {
            func value(_ key: String) -> Any? {
              guard let column = columns[key], column.indices.contains(index) else { return nil }
              return column[index]
            }
            func text(_ key: String) -> String { (value(key) as? String) ?? "" }
            func number(_ key: String) -> Double? { (value(key) as? NSNumber)?.doubleValue }
            let year = number("year").map(Int.init).flatMap { $0 == 0 ? nil : $0 }
            outside[id] = LibraryOutsideTrack(name: text("name"), artist: text("artist"), album: text("album"), year: year, durationSeconds: number("duration"))
          }
        }
      }
    }
    return (rows, outside)
  }

  private static func hasNoSpecialKind(_ playlist: SBObject) -> Bool {
    guard let kind = playlist.value(forKey: "specialKind") else { return true }
    if let string = kind as? String { return string == "none" || string == "kNon" }
    guard let number = kind as? NSNumber else { return false }
    return number.uint32Value == fourCharCode("kNon")
  }

  private static func readEveryTrackProperty(_ property: LibraryBulkProperty, from playlist: NSAppleEventDescriptor) throws -> [Any] {
    var all = fourCharCode("all ")
    let everyTrack = try objectSpecifier("cTrk", form: "indx",
      data: NSAppleEventDescriptor(descriptorType: fourCharCode("abso"), bytes: &all, length: 4)!, from: playlist)
    let specifier = try objectSpecifier("prop", form: "prop",
      data: NSAppleEventDescriptor(typeCode: fourCharCode(property.code)), from: everyTrack)
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
      targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: musicBundleIdentifier),
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(specifier, forKeyword: keyDirectObject)
    let reply = try event.sendEvent(options: [.waitForReply], timeout: TimeInterval(snapshotReadTimeout.components.seconds))
    guard let list = reply.paramDescriptor(forKeyword: keyDirectObject), list.descriptorType == typeAEList else {
      let status = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
      throw MusicAppLiveError.scriptingBridgeReadFailed("playlist \(property.key) (OSStatus \(status))")
    }
    guard list.numberOfItems > 0 else { return [] }
    return (1...list.numberOfItems).map { index in
      guard let item = list.atIndex(index), !(item.descriptorType == typeType && item.typeCodeValue == fourCharCode("msng")) else { return NSNull() }
      return switch property.kind {
      case .text: item.stringValue ?? NSNull()
      case .integer: NSNumber(value: item.int32Value)
      case .real: NSNumber(value: item.doubleValue)
      case .date: item.dateValue ?? NSNull()
      case .boolean: NSNumber(value: item.booleanValue)
      case .enumeration: NSNumber(value: item.enumCodeValue)
      }
    }
  }

  private static func objectSpecifier(
    _ desiredClass: String, form: String, data: NSAppleEventDescriptor,
    from container: NSAppleEventDescriptor
  ) throws -> NSAppleEventDescriptor {
    guard var containerDesc = container.aeDesc?.pointee, var keyDesc = data.aeDesc?.pointee else {
      throw MusicAppLiveError.scriptingBridgeReadFailed("object specifier")
    }
    var result = AEDesc()
    let status = CreateObjSpecifier(
      fourCharCode(desiredClass), &containerDesc, fourCharCode(form), &keyDesc, false, &result)
    guard status == noErr else {
      throw MusicAppLiveError.appleEventDescriptorFailed(OSStatus(status))
    }
    return NSAppleEventDescriptor(aeDescNoCopy: &result)
  }

  private static func fourCharCode(_ value: String) -> FourCharCode {
    value.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
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

  /// Copies each file into Music's "Automatically Add" folder so Music ingests it via its
  /// folder watcher — no Apple Event, nothing that can time out on a busy Music. Runs off
  /// the main actor because it is blocking file IO. Colliding names are disambiguated so a
  /// re-drop never clobbers a file the watcher is mid-import on.
  func importViaWatchFolder(_ urls: [URL], into watchFolder: URL) async throws {
    try await Task.detached(priority: .userInitiated) {
      let fileManager = FileManager.default
      var isDirectory: ObjCBool = false
      guard
        fileManager.fileExists(
          atPath: watchFolder.path(percentEncoded: false), isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        throw MusicAppLiveError.watchFolderUnavailable(watchFolder)
      }
      guard fileManager.isWritableFile(atPath: watchFolder.path(percentEncoded: false)) else {
        throw MusicAppLiveError.watchFolderNotWritable(watchFolder)
      }

      for url in urls {
        let destination = Self.uniqueDestination(
          for: url.lastPathComponent,
          in: watchFolder,
          fileManager: fileManager
        )
        try fileManager.copyItem(at: url.standardizedFileURL, to: destination)
      }
    }
    .value
  }

  /// Returns a destination URL in `folder` for `fileName`, appending a short suffix if a
  /// file already sits there (Music removes files after importing, so a collision means a
  /// prior drop is still pending — never overwrite it).
  private static func uniqueDestination(
    for fileName: String,
    in folder: URL,
    fileManager: FileManager
  ) -> URL {
    let candidate = folder.appending(path: fileName)
    guard fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) else {
      return candidate
    }
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var attempt = 2
    while true {
      let suffixed = ext.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(ext)"
      let url = folder.appending(path: suffixed)
      if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
        return url
      }
      attempt += 1
    }
  }

  private func ensureMusicIsRunning() async throws {
    guard
      NSRunningApplication
        .runningApplications(withBundleIdentifier: Self.musicBundleIdentifier)
        .isEmpty
    else {
      return
    }
    guard
      let url = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: Self.musicBundleIdentifier
      )
    else {
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
  case watchFolderUnavailable(URL)
  case watchFolderNotWritable(URL)

  var errorDescription: String? {
    switch self {
    case .appleEventDescriptorFailed(let status):
      "Could not prepare the Music automation target descriptor: OSStatus \(status)."
    case .automationPermission(let permission):
      permission.displayMessage
    case .libraryPlaylistUnavailable:
      "Music's library playlist could not be read."
    case .musicAppUnavailable:
      "Music.app could not be found."
    case .scriptingBridgeReadFailed(let key):
      "Music scripting bridge value '\(key)' could not be read."
    case .timedOut:
      "Music did not respond in time. It may be busy or blocked on a dialog; try again."
    case .watchFolderUnavailable(let url):
      "The Automatically Add folder isn't there: \(url.path(percentEncoded: false)). Check it in Settings — is the drive mounted?"
    case .watchFolderNotWritable(let url):
      "The Automatically Add folder isn't writable: \(url.path(percentEncoded: false))."
    }
  }
}

/// One Music track property read in bulk for the library snapshot. Keys match
/// `LibraryTrack(bulkColumns:index:)`; codes are from Music's scripting dictionary.
private struct LibraryBulkProperty {
  enum Kind { case text, integer, real, date, boolean, enumeration }
  let key: String
  let code: String
  let kind: Kind

  static let all: [LibraryBulkProperty] = [
    .init(key: "persistentID", code: "pPIS", kind: .text),
    .init(key: "name", code: "pnam", kind: .text),
    .init(key: "artist", code: "pArt", kind: .text),
    .init(key: "albumArtist", code: "pAlA", kind: .text),
    .init(key: "album", code: "pAlb", kind: .text),
    .init(key: "genre", code: "pGen", kind: .text),
    .init(key: "year", code: "pYr ", kind: .integer),
    .init(key: "duration", code: "pDur", kind: .real),
    .init(key: "playedCount", code: "pPlC", kind: .integer),
    .init(key: "skippedCount", code: "pSkC", kind: .integer),
    .init(key: "favorited", code: "pLov", kind: .boolean),
    .init(key: "disliked", code: "pHat", kind: .boolean),
    .init(key: "rating", code: "pRte", kind: .integer),
    .init(key: "dateAdded", code: "pAdd", kind: .date),
    .init(key: "playedDate", code: "pPlD", kind: .date),
    .init(key: "cloudStatus", code: "pClS", kind: .enumeration),
  ]
}
