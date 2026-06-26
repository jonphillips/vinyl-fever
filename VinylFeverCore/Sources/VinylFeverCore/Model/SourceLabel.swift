import CryptoKit
import Foundation
import SQLiteData

@Table
public struct SourceLabel: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var token: String
  public var isBuiltIn: Bool

  public init(id: UUID, token: String, isBuiltIn: Bool) {
    self.id = id
    self.token = Self.normalizedToken(token)
    self.isBuiltIn = isBuiltIn
  }
}

extension SourceLabel {
  public static let builtInTokens = [
    "SBD",
    "D-SBD",
    "DSBD",
    "AUD",
    "FM",
    "ALD",
    "SBD/ALD",
    "SBD/AUD",
    "Matrix",
    "IEM/AUD Matrix",
    "Broadcast DAT Clone",
    "Radio Broadcast",
    "TV/FM Broadcast",
    "Pre-FM",
    "Ultramatrix SBD",
  ]

  public static var builtIns: [Self] {
    builtInTokens.map { token in
      Self(id: stableBuiltInID(for: token), token: token, isBuiltIn: true)
    }
  }

  public static func deduplicated(_ sourceLabels: [Self]) -> [Self] {
    var winners: [String: Self] = [:]

    for sourceLabel in sourceLabels {
      let key = sourceLabel.normalizedTokenKey
      guard !key.isEmpty else {
        continue
      }

      guard let winner = winners[key] else {
        winners[key] = sourceLabel
        continue
      }

      if sourceLabel.precedesDeduplicationWinner(winner) {
        winners[key] = sourceLabel
      }
    }

    return winners.values.sorted(by: isDisplayOrderedBefore)
  }

  public static func normalizedToken(_ token: String) -> String {
    var token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if token.hasPrefix("("), token.hasSuffix(")"), token.count > 2 {
      token = String(token.dropFirst().dropLast())
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return token.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  public var normalizedTokenKey: String {
    Self.normalizedToken(token).lowercased()
  }

  private static func stableBuiltInID(for token: String) -> UUID {
    let input = "VinylFever.SourceLabel.v1:\(normalizedToken(token).lowercased())"
    let digest = SHA256.hash(data: Data(input.utf8))
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

  private static func isDisplayOrderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
    let lhsBuiltInIndex = builtInDisplayOrder[lhs.normalizedTokenKey]
    let rhsBuiltInIndex = builtInDisplayOrder[rhs.normalizedTokenKey]

    switch (lhsBuiltInIndex, rhsBuiltInIndex) {
    case let (.some(lhsIndex), .some(rhsIndex)):
      return lhsIndex < rhsIndex
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    case (.none, .none):
      let tokenComparison = lhs.token.localizedStandardCompare(rhs.token)
      if tokenComparison != .orderedSame {
        return tokenComparison == .orderedAscending
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  private static var builtInDisplayOrder: [String: Int] {
    Dictionary(
      uniqueKeysWithValues: builtInTokens.enumerated().map { index, token in
        (normalizedToken(token).lowercased(), index)
      }
    )
  }

  private func precedesDeduplicationWinner(_ other: Self) -> Bool {
    if isBuiltIn != other.isBuiltIn {
      return isBuiltIn
    }
    return id.uuidString < other.id.uuidString
  }
}
