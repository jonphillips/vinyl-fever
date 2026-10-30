import Foundation

struct ProbeRecord: Codable, Equatable {
  static func filename(for device: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let safeName = device.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    return "m20-s0-\(safeName.isEmpty ? "device" : safeName).jsonl"
  }

  static func feedbackFilename(for device: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let safeName = device.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    return "feedback-\(safeName.isEmpty ? "device" : safeName).jsonl"
  }

  static func whyFilename(for device: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let safeName = device.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    return "why-\(safeName.isEmpty ? "device" : safeName).jsonl"
  }

  struct Player: Codable, Equatable {
    var playbackStatus: String
    var playbackTime: Double?
    var currentEntry: Entry?
    var entryMissing: Bool
    var itemMissing: Bool
  }

  struct Entry: Codable, Equatable {
    var title: String
    var artist: String?
    var album: String?
    var catalogID: String?
  }

  struct RecentSong: Codable, Equatable {
    var title: String
    var artist: String
    var catalogID: String
  }

  struct WriteFailure: Codable, Equatable {
    var time: Date
    var error: String
  }

  var time: Date
  var device: String
  var startedFrom: String?
  var player: Player
  var recentlyPlayed: [RecentSong]
  var recentlyPlayedError: String?
  var previousWriteFailure: WriteFailure?
  var staleReason: String? = nil
  var offeredChoices: [String]? = nil
  var savedSong: Entry? = nil
  var askedSong: Entry? = nil
  var recommendationAnswerKind: String? = nil
  var recommendationRecordedAt: Date? = nil
  var recommendationPlaylist: String? = nil
  var recommendationFilesRead: Int? = nil
  var recommendationFilesUnreadable: Int? = nil

  static func encodeLine(_ record: ProbeRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(record)
    data.append(0x0A)
    return data
  }
}
