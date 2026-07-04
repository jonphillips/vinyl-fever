import Foundation

public enum AppendVerdict: Equatable, Sendable {
  case merged
  case albumNotFound
  case duplicateSpawned(otherTitle: String)
  case countMismatch(expected: Int, actual: Int)

  public var isCertified: Bool {
    self == .merged
  }

  public var displayMessage: String {
    switch self {
    case .merged:
      "Certified: imported tracks merged into the existing album."
    case .albumNotFound:
      "Not certified: the exact album was not found in Music."
    case let .duplicateSpawned(otherTitle):
      "Not certified: a near-identical album appeared: \(otherTitle)."
    case let .countMismatch(expected, actual):
      "Not certified: expected \(expected) tracks in the album, found \(actual)."
    }
  }
}

public struct AppendCertification: Equatable, Sendable {
  public var run: RunRecord
  public var identity: AlbumIdentity
  public var addedTrackCount: Int
  public var preImportTrackCount: Int
  public var postImportTrackCount: Int
  public var verdict: AppendVerdict

  public init(
    run: RunRecord,
    identity: AlbumIdentity,
    addedTrackCount: Int,
    preImportTrackCount: Int,
    postImportTrackCount: Int,
    verdict: AppendVerdict
  ) {
    self.run = run
    self.identity = identity
    self.addedTrackCount = addedTrackCount
    self.preImportTrackCount = preImportTrackCount
    self.postImportTrackCount = postImportTrackCount
    self.verdict = verdict
  }

  public var isCertified: Bool {
    verdict.isCertified
  }
}

public enum AppendCertificationComparator {
  public static func verdict(
    identity: AlbumIdentity,
    preImportTracks: [ImportedTrackRef],
    postImportTracks: [ImportedTrackRef],
    addedTrackCount: Int
  ) -> AppendVerdict {
    let preExactCount = exactMatches(identity: identity, in: preImportTracks).count
    let postExactCount = exactMatches(identity: identity, in: postImportTracks).count

    guard preExactCount > 0, postExactCount > 0 else {
      return .albumNotFound
    }

    if let duplicate = duplicateSpawn(
      identity: identity,
      preImportTracks: preImportTracks,
      postImportTracks: postImportTracks
    ) {
      return .duplicateSpawned(otherTitle: duplicate)
    }

    let expectedCount = preExactCount + addedTrackCount
    guard postExactCount == expectedCount else {
      return .countMismatch(expected: expectedCount, actual: postExactCount)
    }

    return .merged
  }

  public static func exactMatches(
    identity: AlbumIdentity,
    in tracks: [ImportedTrackRef]
  ) -> [ImportedTrackRef] {
    let normalizedIdentity = normalized(identity)
    return tracks.filter { ref in
      isExactIdentity(ref, identity: normalizedIdentity)
    }
  }

  private static func duplicateSpawn(
    identity: AlbumIdentity,
    preImportTracks: [ImportedTrackRef],
    postImportTracks: [ImportedTrackRef]
  ) -> String? {
    let preKeys = Set(preImportTracks.map(albumKey))
    let normalizedIdentity = normalized(identity)
    return postImportTracks
      .filter { ref in
        !preKeys.contains(albumKey(ref)) &&
          ref.album != nil &&
          !isExactIdentity(ref, identity: normalizedIdentity) &&
          looksLikeDuplicateTitle(ref.album, of: normalizedIdentity.album)
      }
      .compactMap(\.album)
      .sorted()
      .first
  }

  private static func isExactIdentity(_ ref: ImportedTrackRef, identity: AlbumIdentity) -> Bool {
    ref.album == identity.album && ref.albumArtist == identity.albumArtist
  }

  private static func normalized(_ identity: AlbumIdentity) -> AlbumIdentity {
    AlbumIdentity(
      album: AudioTagVerifier.normalizedMetadataString(identity.album),
      albumArtist: AudioTagVerifier.normalizedMetadataString(identity.albumArtist)
    )
  }

  private static func albumKey(_ ref: ImportedTrackRef) -> AlbumKey {
    AlbumKey(album: ref.album ?? "", albumArtist: ref.albumArtist ?? "")
  }

  private static func looksLikeDuplicateTitle(_ title: String?, of target: String) -> Bool {
    guard let title else {
      return false
    }
    let normalizedTitle = duplicateTitleKey(title)
    let normalizedTarget = duplicateTitleKey(target)
    guard normalizedTitle != normalizedTarget else {
      return false
    }
    return normalizedTitle.hasPrefix(normalizedTarget + " ")
  }

  private static func duplicateTitleKey(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
  }
}

private struct AlbumKey: Hashable {
  var album: String
  var albumArtist: String
}

public enum CompilationImportReducer {
  public static func importedTracks(
    plan: ConversionPlan,
    addedRefs: [ImportedTrackRef]
  ) -> [ImportedTrack] {
    var remainingRefs = addedRefs
    return plan.tracks.map { track in
      if let locationMatchIndex = remainingRefs.firstIndex(where: { ref in
        ref.locationPath == ImportedTrackRef.normalizedFilePath(track.verificationFile)
      }) {
        let ref = remainingRefs.remove(at: locationMatchIndex)
        return ImportedTrack(
          id: track.id,
          sourceURL: track.verificationFile,
          libraryRef: ref,
          status: .imported
        )
      }

      if !remainingRefs.isEmpty {
        let ref = remainingRefs.removeFirst()
        return ImportedTrack(
          id: track.id,
          sourceURL: track.verificationFile,
          libraryRef: ref,
          status: .imported
        )
      }

      return ImportedTrack(
        id: track.id,
        sourceURL: track.verificationFile,
        libraryRef: nil,
        status: .alreadyPresent
      )
    }
  }
}
