import Foundation
import SQLiteData

/// The first concrete instance of the Collection Policy primitive described in
/// `docs/metadata-policy-model.md`: "because this song belongs here, what should
/// we do to its metadata." M7 stands up the minimal identity (name + a free-text
/// description) that a `CollectionRecipe` hangs off of via a foreign key.
///
/// Deliberately thin. Membership rules, artwork policy, MusicBrainz lookup policy
/// and the rest of the policy model land on this table later; recipes only need
/// something stable to belong to and cascade from.
@Table
public struct CollectionPolicy: Equatable, Identifiable, Sendable {
  public let id: UUID
  public var name: String
  /// Free-text "what this collection means." Named `details` rather than
  /// `description` to avoid colliding with `CustomStringConvertible`.
  public var details: String

  public init(id: UUID, name: String, details: String = "") {
    self.id = id
    self.name = name
    self.details = details
  }
}
