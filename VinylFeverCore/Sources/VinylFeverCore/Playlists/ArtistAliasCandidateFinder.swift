#if os(macOS)
import Foundation
import SQLiteData
import VinylFeverListening

public struct ArtistAliasCandidate: Codable, Equatable, Identifiable, Sendable {
  public var variant: String
  public var canonical: String
  public var variantDisplay: String
  public var canonicalDisplay: String
  public var variantTrackCount: Int
  public var canonicalTrackCount: Int
  public var sharedTitles: [String]

  public var id: String { "\(variant)|\(canonical)" }
}

/// Finds likely artist aliases from library evidence. Every key is a layer-1/2
/// base key; decisions are applied later and never alter this evidence pass.
public enum ArtistAliasCandidateFinder {
  private static let structuralWords: Set<String> = ["band", "trio", "quartet", "experience", "acoustic"]
  private static let excluded: Set<String> = ["various", "various artists", "soundtrack", "cast recording", "original cast recording"]

  public static func candidates(in tracks: [LibraryTrack], decidedPairs: Set<String> = []) -> [ArtistAliasCandidate] {
    var display: [String: [String: Int]] = [:]
    var titlesByKey: [String: Set<String>] = [:]
    var titleKeys: [String: Set<String>] = [:]
    for track in tracks {
      let key = ArtistIdentity.baseKey(track.artist)
      guard !key.isEmpty, !excluded.contains(key) else { continue }
      display[key, default: [:]][track.artist, default: 0] += 1
      let title = titleKey(track.name)
      guard title.count >= 4 else { continue }
      titleKeys[title, default: []].insert(key)
    }
    var keys: [String] = []
    for key in display.keys where !excluded.contains(key) { keys.append(key) }
    keys.sort()
    var evidencePairs: Set<String> = []
    for (title, owners) in titleKeys where owners.count <= 5 && title.count >= 4 {
      for owner in owners { titlesByKey[owner, default: []].insert(title) }
      let values: [String] = owners.sorted()
      if values.count > 1 {
        for left in 0..<(values.count - 1) {
          for right in (left + 1)..<values.count {
            evidencePairs.insert(pair(values[left], values[right]))
          }
        }
      }
    }
    let structuralEvidence = structuralPairs(keys)
    evidencePairs.formUnion(structuralEvidence)
    var result: [ArtistAliasCandidate] = []
    for pairKey in evidencePairs {
      let parts: [String] = pairKey.components(separatedBy: "\u{1f}")
      guard parts.count == 2 else { continue }
      let a = parts[0], b = parts[1]
      guard !decidedPairs.contains(pair(a, b)) else { continue }
      let titlesA: Set<String> = titlesByKey[a] ?? []
      let titlesB: Set<String> = titlesByKey[b] ?? []
      let sharedSet: Set<String> = titlesA.intersection(titlesB)
      let shared: [String] = sharedSet.sorted()
      let overlap = shared.count >= 4 && shared.count * 2 >= min(titlesA.count, titlesB.count)
      let structural = structuralEvidence.contains(pair(a, b))
      guard overlap || structural else { continue }
      let countsA = display[a, default: [:]].values.reduce(0, +)
      let countsB = display[b, default: [:]].values.reduce(0, +)
      let canonicalKey = countsA >= countsB ? a : b
      let variantKey = canonicalKey == a ? b : a
      result.append(ArtistAliasCandidate(
        variant: variantKey, canonical: canonicalKey,
        variantDisplay: mostCommon(display[variantKey, default: [:]]),
        canonicalDisplay: mostCommon(display[canonicalKey, default: [:]]),
        variantTrackCount: display[variantKey, default: [:]].values.reduce(0, +),
        canonicalTrackCount: display[canonicalKey, default: [:]].values.reduce(0, +),
        sharedTitles: Array(shared.prefix(3))))
    }
    result.sort(by: candidateComesBefore)
    return result
  }

  public static func pair(_ lhs: String, _ rhs: String) -> String {
    [lhs, rhs].sorted().joined(separator: "\u{1f}")
  }

  private static func mostCommon(_ values: [String: Int]) -> String {
    var winner = ""
    var winnerCount = -1
    for (name, count) in values {
      if count > winnerCount || (count == winnerCount && name < winner) {
        winner = name
        winnerCount = count
      }
    }
    return winner
  }

  private static func candidateComesBefore(_ lhs: ArtistAliasCandidate, _ rhs: ArtistAliasCandidate) -> Bool {
    let lhsCount = lhs.variantTrackCount + lhs.canonicalTrackCount
    let rhsCount = rhs.variantTrackCount + rhs.canonicalTrackCount
    if lhsCount != rhsCount { return lhsCount > rhsCount }
    return lhs.id < rhs.id
  }

  private static func titleKey(_ value: String) -> String {
    ListeningTextNormalizer.libraryTitle(value)
  }

  private static func structuralPairs(_ keys: [String]) -> Set<String> {
    let keySet = Set(keys)
    var result: Set<String> = []
    var reordered: [String: [String]] = [:]
    for key in keys {
      let words = key.split(separator: " ").map(String.init)
      var sortedWords = words
      sortedWords.sort()
      reordered[sortedWords.joined(separator: " "), default: []].append(key)
      for suffix in [["band"], ["trio"], ["quartet"], ["experience"], ["acoustic", "trio"]] {
        guard words.count > suffix.count,
          Array(words.suffix(suffix.count)) == suffix else { continue }
        let base = words.dropLast(suffix.count).joined(separator: " ")
        if keySet.contains(base) { result.insert(pair(key, base)) }
      }
    }
    for group in reordered.values where group.count > 1 {
      for i in 0..<(group.count - 1) {
        for j in (i + 1)..<group.count { result.insert(pair(group[i], group[j])) }
      }
    }
    // A joined-word key such as `john lennonplastic ono band` extends the
    // known key's last word inside one candidate word.
    for key in keys {
      let words = key.split(separator: " ").map(String.init)
      guard words.count >= 2 else { continue }
      for index in 1..<words.count {
        let expanded = words[index]
        for split in 0..<expanded.count {
          let knownLast = String(expanded.prefix(expanded.count - split))
          let extra = String(expanded.suffix(split))
          guard extra.count >= 4, knownLast.count >= 3 else { continue }
          let known = (Array(words[..<index]) + [knownLast]).joined(separator: " ")
          if keySet.contains(known) { result.insert(pair(key, known)) }
        }
      }
      // One extra inner word is a common expanded artist spelling.
      if words.count >= 3 {
        for index in 1..<(words.count - 1) {
          let knownWords = Array(words[..<index]) + Array(words[(index + 1)...])
          let known = knownWords.joined(separator: " ")
          if keySet.contains(known) { result.insert(pair(key, known)) }
        }
      }
    }
    return result
  }
}

public struct ArtistAliasesDocument: Codable, Equatable, Sendable {
  public static let format = "vf-artist-aliases"
  public static let currentVersion = 1
  public var format: String = Self.format
  public var version: Int = Self.currentVersion
  public var aliases: [String: String]

  public init(aliases: [String: String]) { self.aliases = aliases }
}

public enum ArtistAliasesCodecError: Error, Equatable, LocalizedError {
  case unsupportedFormat(String)
  case newerVersion(Int)

  public var errorDescription: String? {
    switch self {
    case .newerVersion: "Update Vinyl Fever to read these artist aliases."
    case let .unsupportedFormat(format): "Unsupported artist alias format: \(format)."
    }
  }
}

public enum ArtistAliasExporter {
  public static func export(database: any DatabaseWriter, store: LibrarySnapshotStore) async throws {
    let aliases = try await database.read { db in
      ArtistAlias.acceptedMap(try ArtistAlias.all.fetchAll(db))
    }
    try await store.writeAliases(aliases)
  }
}

public enum ArtistAliasesCodec {
  public static func encode(_ aliases: [String: String]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(ArtistAliasesDocument(aliases: aliases))
  }

  public static func decode(_ data: Data) throws -> [String: String] {
    let document = try JSONDecoder().decode(ArtistAliasesDocument.self, from: data)
    guard document.format == ArtistAliasesDocument.format else {
      throw ArtistAliasesCodecError.unsupportedFormat(document.format)
    }
    guard document.version <= ArtistAliasesDocument.currentVersion else {
      throw ArtistAliasesCodecError.newerVersion(document.version)
    }
    return document.aliases
  }
}
#endif
