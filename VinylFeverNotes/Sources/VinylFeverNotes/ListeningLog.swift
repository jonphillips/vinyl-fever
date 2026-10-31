import Foundation

public enum ListeningQueryLimit {
  public static let `default` = 50
  public static let maximum = 200

  public static func cap(_ requested: Int) -> Int {
    min(max(requested, 1), maximum)
  }
}

public struct ListeningCoverageGap: Codable, Equatable, Sendable, Identifiable {
  public var poller: UUID
  public var host: String
  public var outcome: ListeningFetch.Outcome
  public var windowStart: Date?
  public var windowEnd: Date
  public var detail: String?
  public var id: String { "\(poller.uuidString):\(windowEnd.timeIntervalSince1970)" }

  public init(
    poller: UUID, host: String, outcome: ListeningFetch.Outcome,
    windowStart: Date?, windowEnd: Date, detail: String?
  ) {
    self.poller = poller
    self.host = host
    self.outcome = outcome
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.detail = detail
  }
}

public struct ListeningCoverage: Codable, Equatable, Sendable {
  public var firstFetchAt: Date?
  public var lastFetchAt: Date?
  public var lastFetchAge: TimeInterval?
  public var poller: UUID?
  public var host: String?
  public var gaps: [ListeningCoverageGap]
  public var collapsedOverlappingPlays: Int

  public init(
    firstFetchAt: Date?, lastFetchAt: Date?, lastFetchAge: TimeInterval?,
    poller: UUID?, host: String?, gaps: [ListeningCoverageGap], collapsedOverlappingPlays: Int
  ) {
    self.firstFetchAt = firstFetchAt
    self.lastFetchAt = lastFetchAt
    self.lastFetchAge = lastFetchAge
    self.poller = poller
    self.host = host
    self.gaps = gaps
    self.collapsedOverlappingPlays = collapsedOverlappingPlays
  }
}

/// A normalized, app-independent text key. Its artist/title rules match `SongTextNormalizer`
/// so the app can use the same identity when it joins listening plays to its library.
public enum ListeningTextNormalizer {
  public static func artist(_ raw: String) -> String {
    guard containsCreditMarker(raw) else { return text(raw) }
    return text(raw.replacingOccurrences(
      of: #"\b(feat\.?|ft\.?|with)\b.*$"#,
      with: "", options: [.regularExpression, .caseInsensitive]))
  }

  public static func title(_ raw: String) -> String {
    var value = raw
    if raw.contains("(") || raw.contains("[") {
      value = value.replacingOccurrences(
        of: #"\s*[\(\[]\s*(feat\.?|ft\.?|with)\b[^)\]]*[)\]]"#,
        with: "", options: [.regularExpression, .caseInsensitive])
    }
    if raw.range(of: "remaster", options: .caseInsensitive) != nil {
      value = value.replacingOccurrences(
        of: #"\s*[\(\[](?:(?:19|20)\d{2}\s+)?remaster(?:ed)?[^)\]]*[)\]]"#,
        with: "", options: [.regularExpression, .caseInsensitive])
      value = value.replacingOccurrences(
        of: #"\s+[-–—]\s+(?:(?:19|20)\d{2}\s+)?remaster(?:ed)?(?:\s+(?:19|20)\d{2})?\s*$"#,
        with: "", options: [.regularExpression, .caseInsensitive])
    }
    return text(value)
  }

  public static func trackKey(artist: String, title: String) -> String {
    "\(self.artist(artist))|\(libraryTitle(title))"
  }

  /// Library metadata can store a guest credit directly in the title.
  public static func libraryTitle(_ raw: String) -> String {
    var value = raw
    if containsCreditMarker(raw) {
      value = raw.replacingOccurrences(
        of: #"\s*[\(\[]\s*(?:feat\.?|ft\.?|featuring)\s+[^)\]]*[)\]]"#,
        with: "", options: [.regularExpression, .caseInsensitive])
      value = value.replacingOccurrences(
        of: #"\s+(?:feat\.?|ft\.?|featuring)\s+.*$"#,
        with: "", options: [.regularExpression, .caseInsensitive])
    }
    return title(value)
  }

  private static func containsCreditMarker(_ raw: String) -> Bool {
    raw.range(of: "feat", options: .caseInsensitive) != nil
      || raw.range(of: "ft", options: .caseInsensitive) != nil
      || raw.range(of: "with", options: .caseInsensitive) != nil
  }

  public static func album(_ raw: String) -> String {
    text(raw)
  }

  public static func text(_ raw: String) -> String {
    let folded = raw.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: "&", with: " and ")
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
    return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}

public struct ListeningLog: Sendable {
  public let plays: [ListeningPlay]
  public let coverage: ListeningCoverage
  private let artistIdentity: ArtistIdentity
  private let artistKeys: [String: String]

  public init(jsonlStreams: [Data], now: Date, identity: ArtistIdentity = .empty) throws {
    let files = try jsonlStreams.map(ListeningLogCodec.decodeJSONL)
    let streams = Dictionary(grouping: files.flatMap { $0 }, by: \.poller).values.map { $0 }
    self.init(streams: streams, now: now, identity: identity)
  }

  public init(streams: [[ListeningFetch]], now: Date, identity: ArtistIdentity = .empty) {
    artistIdentity = identity
    let records = streams.flatMap { $0 }.sorted { $0.fetchedAt < $1.fetchedAt }
    let firstFetch = records.filter { $0.outcome != .failed }.map(\.fetchedAt).min()
    let latest = records.max { $0.fetchedAt < $1.fetchedAt }
    var allPlays: [ListeningPlay] = []
    var gaps: [ListeningCoverageGap] = []

    for stream in streams {
      let ordered = stream.sorted { $0.fetchedAt < $1.fetchedAt }
      var lastSuccessfulFetch: Date?
      var hasSuccessfulFetch = false
      for (lineIndex, fetch) in ordered.enumerated() {
        let sourceLineID = "\(fetch.poller.uuidString)|\(lineIndex)"
        switch fetch.outcome {
        case .baseline, .none:
          if fetch.outcome == .baseline, let since = fetch.since, since.fetchedAt < fetch.fetchedAt {
            gaps.append(ListeningCoverageGap(
              poller: fetch.poller, host: fetch.host, outcome: .gap,
              windowStart: since.fetchedAt, windowEnd: fetch.fetchedAt,
              detail: "The previous poller's feed could not be recovered after handover."))
          }
          lastSuccessfulFetch = fetch.fetchedAt
          hasSuccessfulFetch = true
        case .plays:
          let start = fetch.since?.fetchedAt ?? lastSuccessfulFetch ?? fetch.fetchedAt
          for item in fetch.items.prefix(max(0, fetch.newCount)) {
            allPlays.append(ListeningPlay(
              item: item, windowStart: start, windowEnd: fetch.fetchedAt, poller: fetch.poller,
              sourceLineID: sourceLineID))
          }
          lastSuccessfulFetch = fetch.fetchedAt
          hasSuccessfulFetch = true
        case .gap:
          let start = fetch.since?.fetchedAt ?? lastSuccessfulFetch ?? fetch.fetchedAt
          for item in fetch.items {
            allPlays.append(ListeningPlay(
              item: item, windowStart: start, windowEnd: fetch.fetchedAt, poller: fetch.poller,
              sourceLineID: sourceLineID))
          }
          gaps.append(ListeningCoverageGap(
            poller: fetch.poller, host: fetch.host, outcome: .gap,
            windowStart: fetch.since?.fetchedAt ?? lastSuccessfulFetch, windowEnd: fetch.fetchedAt,
            detail: "The previous feed did not overlap within the page cap."))
          lastSuccessfulFetch = fetch.fetchedAt
          hasSuccessfulFetch = true
        case .failed:
          if hasSuccessfulFetch {
            gaps.append(ListeningCoverageGap(
              poller: fetch.poller, host: fetch.host, outcome: .failed,
              windowStart: lastSuccessfulFetch, windowEnd: fetch.fetchedAt, detail: fetch.error))
          }
        }
      }
    }

    artistKeys = Dictionary(uniqueKeysWithValues: Set(allPlays.map { $0.item.artist }).map {
      ($0, identity.key($0))
    })
    let merged = Self.collapseOverlappingPlays(allPlays, artistKeys: artistKeys)
    self.plays = merged.plays.sorted {
      if $0.windowEnd != $1.windowEnd { return $0.windowEnd > $1.windowEnd }
      return $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
    }
    self.coverage = ListeningCoverage(
      firstFetchAt: firstFetch,
      lastFetchAt: latest?.fetchedAt,
      lastFetchAge: latest.map { max(0, now.timeIntervalSince($0.fetchedAt)) },
      poller: latest?.poller,
      host: latest?.host,
      gaps: gaps.sorted { $0.windowEnd < $1.windowEnd },
      collapsedOverlappingPlays: merged.collapsed
    )
  }

  public func recentPlays(
    period: ListeningPeriod, now: Date, limit: Int = ListeningQueryLimit.default
  ) -> [ListeningPlay] {
    let cutoff = now.addingTimeInterval(-period.duration)
    return Array(plays.filter { $0.windowEnd >= cutoff }.prefix(ListeningQueryLimit.cap(limit)))
  }

  public func topArtists(
    period: ListeningPeriod, now: Date, limit: Int = ListeningQueryLimit.default
  ) -> [ListeningArtistCount] {
    let grouped = Dictionary(grouping: periodPlays(period: period, now: now)) {
      artistIdentity.key($0.item.artist)
    }
    return grouped.compactMap { key, plays in
      guard !key.isEmpty, let artist = plays.first?.item.artist else { return nil }
      return ListeningArtistCount(artist: artist, plays: plays.count)
    }.sorted {
      $0.plays == $1.plays
        ? $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
        : $0.plays > $1.plays
    }.prefix(ListeningQueryLimit.cap(limit)).map { $0 }
  }

  public func topTracks(
    period: ListeningPeriod, now: Date, limit: Int = ListeningQueryLimit.default
  ) -> [ListeningTrackCount] {
    let grouped = Dictionary(grouping: periodPlays(period: period, now: now)) {
      Self.trackKey(artist: $0.item.artist, title: $0.item.title, artistKeys: artistKeys)
    }
    return grouped.compactMap { key, plays in
      guard !key.hasSuffix("|") else { return nil }
      guard let item = plays.first?.item else { return nil }
      return ListeningTrackCount(title: item.title, artist: item.artist, album: item.album, plays: plays.count)
    }.sorted {
      if $0.plays != $1.plays { return $0.plays > $1.plays }
      if $0.artist != $1.artist { return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending }
      return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }.prefix(ListeningQueryLimit.cap(limit)).map { $0 }
  }

  private func periodPlays(period: ListeningPeriod, now: Date) -> [ListeningPlay] {
    let cutoff = now.addingTimeInterval(-period.duration)
    return plays.filter { $0.windowEnd >= cutoff }
  }

  private static func collapseOverlappingPlays(
    _ plays: [ListeningPlay], artistKeys: [String: String]
  )
    -> (plays: [ListeningPlay], collapsed: Int)
  {
    var keyByTrack = [RawTrackIdentity: String]()
    var keyedPlays: [(key: String, play: ListeningPlay)] = []
    keyedPlays.reserveCapacity(plays.count)
    for play in plays {
      let identity = RawTrackIdentity(artist: play.item.artist, title: play.item.title)
      let key: String
      if let cached = keyByTrack[identity] {
        key = cached
      } else {
        key = trackKey(artist: identity.artist, title: identity.title, artistKeys: artistKeys)
        keyByTrack[identity] = key
      }
      keyedPlays.append((key, play))
    }
    var kept: [ListeningPlay] = []
    var collapsed = 0
    let groups = Dictionary(grouping: keyedPlays, by: { $0.key })
    for group in groups.values {
      let ordered = group.sorted {
        if $0.play.windowStart != $1.play.windowStart {
          return $0.play.windowStart < $1.play.windowStart
        }
        return $0.play.windowEnd < $1.play.windowEnd
      }
      var latestEndByLine: [String: Date] = [:]
      for entry in ordered {
        let play = entry.play
        for (lineID, end) in Array(latestEndByLine) where end <= play.windowStart {
          latestEndByLine.removeValue(forKey: lineID)
        }
        let overlapsAnotherLine = latestEndByLine.contains { entry in
          entry.key != play.sourceLineID && entry.value > play.windowStart
        }
        if overlapsAnotherLine {
          collapsed += 1
          continue
        } else {
          kept.append(play)
        }
        latestEndByLine[play.sourceLineID] = max(
          latestEndByLine[play.sourceLineID] ?? play.windowEnd, play.windowEnd)
      }
    }
    return (kept, collapsed)
  }

  private static func trackKey(artist: String, title: String, artistKeys: [String: String]) -> String {
    "\(artistKeys[artist] ?? ArtistIdentity.baseKey(artist))|\(ListeningTextNormalizer.libraryTitle(title))"
  }

  private struct RawTrackIdentity: Hashable {
    var artist: String
    var title: String
  }
}
