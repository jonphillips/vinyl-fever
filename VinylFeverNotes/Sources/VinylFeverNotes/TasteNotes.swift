import Foundation

public struct TasteNote: Codable, Equatable, Sendable {
  public struct About: Codable, Equatable, Sendable {
    public var songs: [Song]
    public var playlists: [String]

    public struct Song: Codable, Equatable, Sendable {
      public var artist: String
      public var title: String

      public init(artist: String, title: String) {
        self.artist = artist
        self.title = title
      }
    }

    public init(songs: [Song] = [], playlists: [String] = []) {
      self.songs = songs
      self.playlists = playlists
    }

    private enum CodingKeys: String, CodingKey { case songs, playlists }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      songs = try container.decodeIfPresent([Song].self, forKey: .songs) ?? []
      playlists = try container.decodeIfPresent([String].self, forKey: .playlists) ?? []
    }
  }

  public var kind: String?
  public var id: String?
  public var answers: String?
  public var skipped: Bool?
  public var about: About?
  public var format: String
  public var version: Int
  public var notedAt: Date
  public var title: String?
  public var artist: String?
  public var album: String?
  public var playCount: Int?
  public var releaseDate: String?
  public var duration: String?
  public var note: String
  public var source: String
  public var device: String?
  public var playlist: String?
  public var catalogID: String?

  public init(
    notedAt: Date, note: String, source: String, title: String? = nil, artist: String? = nil,
    album: String? = nil, playCount: Int? = nil, releaseDate: String? = nil,
    duration: String? = nil, device: String? = nil, playlist: String? = nil,
    kind: String? = nil, id: String? = nil, answers: String? = nil, skipped: Bool? = nil,
    about: About? = nil, catalogID: String? = nil
  ) {
    format = "vf-taste-note"
    version = 1
    self.notedAt = notedAt
    self.title = title
    self.artist = artist
    self.album = album
    self.playCount = playCount
    self.releaseDate = releaseDate
    self.duration = duration
    self.note = note
    self.source = source
    self.device = device
    self.playlist = playlist
    self.kind = kind
    self.id = id
    self.answers = answers
    self.skipped = skipped
    self.about = about
    self.catalogID = catalogID
  }

  public var resolvedKind: String { kind ?? "note" }

  public var isTimeOnly: Bool {
    resolvedKind == "note" && playlist == nil && (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }

  public var firstHearing: Bool? { isTimeOnly ? nil : playCount.map { $0 == 0 } }
}

public struct TasteNotesReadResult: Equatable, Sendable {
  public var notes: [TasteNote]
  public var skippedLines: Int
  public var filesRead: Int

  public init(notes: [TasteNote], skippedLines: Int, filesRead: Int) {
    self.notes = notes
    self.skippedLines = skippedLines
    self.filesRead = filesRead
  }
}

public enum TasteNotesCodec {
  public static func encode(_ note: TasteNote) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      try container.encode(formatter.string(from: date))
    }
    var data = try encoder.encode(note)
    data.append(0x0A)
    return data
  }

  public static func readFiles(_ files: [Data]) -> TasteNotesReadResult {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      guard let date = formatter.date(from: value) else {
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO timestamp")
      }
      return date
    }

    var notes: [TasteNote] = []
    var skippedLines = 0
    for data in files {
      let bytes = [UInt8](data)
      let hasFinalNewline = bytes.last == 0x0A
      let lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
      for (index, line) in lines.enumerated() {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let lineData = Data(line.utf8)
        let header = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        if header == nil && !hasFinalNewline && index == lines.count - 1 { continue }
        guard header?["format"] as? String == "vf-taste-note",
          header?["version"] as? Int == 1,
          let note = try? decoder.decode(TasteNote.self, from: lineData)
        else {
          skippedLines += 1
          continue
        }
        guard !note.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          skippedLines += 1
          continue
        }
        notes.append(note)
      }
    }

    var seen = Set<String>()
    let unique = notes.filter { note in
      let key = note.id.map { "id:\($0)" } ?? "\(note.notedAt.timeIntervalSince1970)|\(note.title ?? "")|\(note.artist ?? "")"
      return seen.insert(key).inserted
    }
    return TasteNotesReadResult(notes: unique.sorted { $0.notedAt > $1.notedAt },
      skippedLines: skippedLines, filesRead: files.count)
  }

  public static func openQuestions(in notes: [TasteNote], now: Date) -> [TasteNote] {
    let answered = Set(notes.compactMap { $0.resolvedKind == "answer" ? $0.answers : nil })
    let questions = notes.filter { note in
      guard note.resolvedKind == "question", let id = note.id else { return false }
      return !answered.contains(id)
    }
      .sorted { $0.notedAt > $1.notedAt }
    let unexpired = questions.filter { now.timeIntervalSince($0.notedAt) < 21 * 86_400 }
    return Array(unexpired.prefix(3))
  }

  public static func appendChatNote(_ note: TasteNote, host: String, folder: URL) throws {
    let safeHost = sanitizedComponent(host, fallback: "Mac")
    try append(note, to: folder.appendingPathComponent("notes-chat-\(safeHost).jsonl"))
  }

  public static func appendFeedbackNote(_ note: TasteNote, device: String, folder: URL) throws {
    let safeDevice = sanitizedComponent(device, fallback: "device")
    try append(note, to: folder.appendingPathComponent("notes-feedback-\(safeDevice).jsonl"))
  }

  public static func append(_ note: TasteNote, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { target in
      do {
        if !FileManager.default.fileExists(atPath: target.path) {
          _ = FileManager.default.createFile(atPath: target.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: encode(note))
        try handle.synchronize()
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
  }

  private static func sanitizedComponent(_ value: String, fallback: String) -> String {
    let result = value.unicodeScalars.map {
      CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? String($0) : "_"
    }.joined()
    return result.isEmpty ? fallback : result
  }
}
