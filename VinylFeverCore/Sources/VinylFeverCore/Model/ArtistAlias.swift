#if os(macOS)
import Foundation
import SQLiteData
import VinylFeverListening

@Table
public struct ArtistAlias: Equatable, Identifiable, Sendable {
  public var id: String { "\(variant)\u{1f}\(canonical)" }
  public var variant: String
  public var canonical: String
  public var decision: String
  public var decidedAt: Date

  public init(variant: String, canonical: String, decision: String, decidedAt: Date) {
    self.variant = ArtistIdentity.baseKey(variant)
    self.canonical = ArtistIdentity.baseKey(canonical)
    self.decision = decision
    self.decidedAt = decidedAt
  }
}

extension ArtistAlias {
  public static func acceptedMap(_ rows: [Self]) -> [String: String] {
    Dictionary(rows.filter { $0.decision == "accepted" }.map { ($0.variant, $0.canonical) }, uniquingKeysWith: { _, latest in latest })
  }

  public static func decidedPairs(_ rows: [Self]) -> Set<String> {
    var pairs = Set(rows.map { ArtistAliasCandidateFinder.pair($0.variant, $0.canonical) })
    var aliasesByCanonical: [String: Set<String>] = [:]
    for row in rows where row.decision == "accepted" {
      aliasesByCanonical[row.canonical, default: []].insert(row.variant)
      aliasesByCanonical[row.canonical, default: []].insert(row.canonical)
    }
    for aliases in aliasesByCanonical.values where aliases.count > 1 {
      let values = aliases.sorted()
      for left in 0..<(values.count - 1) {
        for right in (left + 1)..<values.count {
          pairs.insert(ArtistAliasCandidateFinder.pair(values[left], values[right]))
        }
      }
    }
    return pairs
  }

  public static func decide(
    variant rawVariant: String, canonical rawCanonical: String, accepted: Bool,
    now: Date = Date(), in db: Database
  ) throws {
    let variant = ArtistIdentity.baseKey(rawVariant)
    let canonical = ArtistIdentity.baseKey(rawCanonical)
    guard !variant.isEmpty, !canonical.isEmpty, variant != canonical else { return }
    let resolved: String
    if accepted {
      resolved = try resolve(canonical, in: db)
    } else {
      resolved = canonical
    }
    guard variant != resolved else { return }
    if accepted {
      // Acceptance replaces a rejection for this pair in either direction,
      // and an accepted mapping for this variant.
      try #sql("DELETE FROM artistAliases WHERE decision = 'rejected' AND ((variant = \(bind: variant) AND canonical = \(bind: resolved)) OR (variant = \(bind: resolved) AND canonical = \(bind: variant)))").execute(db)
      try #sql("DELETE FROM artistAliases WHERE variant = \(bind: variant) AND decision = 'accepted'").execute(db)

      // Existing aliases that pointed at this variant follow it to the new root.
      let aliases = try ArtistAlias.all.fetchAll(db).filter { $0.decision == "accepted" && $0.canonical == variant }
      for alias in aliases {
        try #sql("DELETE FROM artistAliases WHERE variant = \(bind: alias.variant) AND canonical = \(bind: resolved) AND decision = 'rejected'").execute(db)
        try #sql("UPDATE artistAliases SET canonical = \(bind: resolved) WHERE variant = \(bind: alias.variant) AND canonical = \(bind: variant) AND decision = 'accepted'").execute(db)
      }
      try #sql("""
        INSERT INTO artistAliases (variant, canonical, decision, decidedAt)
        VALUES (\(bind: variant), \(bind: resolved), 'accepted', \(bind: now))
        ON CONFLICT(variant, canonical) DO UPDATE SET decision = 'accepted', decidedAt = excluded.decidedAt
        """).execute(db)
    } else {
      // A rejection records the reviewed pair and never replaces an accepted
      // decision for the same ordered pair.
      try #sql("""
        INSERT INTO artistAliases (variant, canonical, decision, decidedAt)
        VALUES (\(bind: variant), \(bind: resolved), 'rejected', \(bind: now))
        ON CONFLICT(variant, canonical) DO NOTHING
        """).execute(db)
    }
  }

  public static func undo(_ variant: String, in db: Database) throws {
    try #sql("DELETE FROM artistAliases WHERE variant = \(bind: ArtistIdentity.baseKey(variant)) AND decision = 'accepted'").execute(db)
  }

  private static func resolve(_ key: String, in db: Database) throws -> String {
    var current = key
    var visited: Set<String> = []
    let rows = try ArtistAlias.all.fetchAll(db)
    while visited.insert(current).inserted,
      let next = rows.first(where: { $0.variant == current && $0.decision == "accepted" })?.canonical,
      next != current
    { current = next }
    return current
  }
}
#endif
