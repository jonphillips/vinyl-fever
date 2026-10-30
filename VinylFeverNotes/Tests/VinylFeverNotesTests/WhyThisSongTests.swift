import Foundation
import Testing
import VinylFeverNotes

struct WhyThisSongTests {
  private let song = FeedbackSong(title: "Starry Eyes", artist: "The Records")

  @Test func newestReasonWinsOverANewerBatchWithoutOne() {
    let older = batch("Old", day: 1, why: "A bright power-pop hook.")
    let newer = batch("New", day: 2, why: nil)
    let answer = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [newer, older], skippedLines: 0), unreadableFileCount: 0)
    guard case let .withReason(found, _) = answer else { Issue.record("Expected the older reason"); return }
    #expect(found.playlist == "Old")
  }

  @Test func newestWithoutReasonAndMissingSongOutcomes() {
    let noReason = batch("No reason", day: 1, why: nil)
    let staged = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [noReason], skippedLines: 0), unreadableFileCount: 0)
    if case .stagedWithoutReason = staged {} else { Issue.record("Expected staged without reason") }
    let missing = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0), unreadableFileCount: 0)
    #expect(missing == .notRecommended)
    let unreadable = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [], skippedLines: 0), unreadableFileCount: 1)
    #expect(unreadable == .recommendationsUnavailable)
  }

  @Test func matchingTrimsAndIgnoresCaseAndDiacritics() {
    let batch = RecommendationBatch(recordedAt: date(1), host: "Mac", playlist: "Cafe",
      tracks: [RecommendationTrack(artist: "Beyoncé", title: "Déjà Vu", familiar: false, reasons: [], artistKnown: true, why: "A match.")])
    let result = WhyThisSong.answer(for: FeedbackSong(title: " Deja Vu ", artist: "BEYONCE"),
      ledger: RecommendationLedgerReadResult(batches: [batch], skippedLines: 0), unreadableFileCount: 0)
    if case .withReason = result {} else { Issue.record("Expected normalized match") }
  }

  @Test func spokenTextFormatsLikeListsPlaylistAndLocalDate() {
    let batch = RecommendationBatch(recordedAt: date(1), host: "Mac", playlist: "New finds",
      tracks: [RecommendationTrack(artist: "The Records", title: "Starry Eyes", familiar: false,
        reasons: [], artistKnown: true, why: "A bright hook.", like: [
          RecommendationLike(artist: "A", title: "One"),
          RecommendationLike(artist: "B", title: "Two"),
          RecommendationLike(artist: "C", title: "Three"),
        ])])
    let answer = WhyThisSongAnswer.withReason(batch: batch, track: batch.tracks[0])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let spoken = WhyThisSong.spokenText(for: song, answer: answer, now: date(100), calendar: calendar,
      timeZone: TimeZone(identifier: "America/New_York")!)
    #expect(spoken == "Starry Eyes by The Records was in New finds, staged January 1. A bright hook. The chat compared it with One by A, Two by B and Three by C.")
  }

  @Test func spokenLikeListsCoverZeroOneAndTwo() {
    let batch = RecommendationBatch(recordedAt: date(1), host: "Mac", playlist: "New finds", tracks: [
      RecommendationTrack(artist: "The Records", title: "Starry Eyes", familiar: false,
        reasons: [], artistKnown: true, why: "A hook."),
    ])
    let now = date(100)
    let timezone = TimeZone(identifier: "America/New_York")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    for (likes, ending) in [
      ([], "A hook."),
      ([RecommendationLike(artist: "A", title: "One")], "A hook. The chat compared it with One by A."),
      ([RecommendationLike(artist: "A", title: "One"), RecommendationLike(artist: "B", title: "Two")],
       "A hook. The chat compared it with One by A and Two by B."),
    ] {
      var track = batch.tracks[0]
      track.like = likes
      let answer = WhyThisSongAnswer.withReason(batch: batch, track: track)
      let spoken = WhyThisSong.spokenText(for: song, answer: answer, now: now, calendar: calendar, timeZone: timezone)
      #expect(spoken.hasSuffix(ending))
    }
  }

  @Test func recommendationEncodingIsStable() throws {
    let batch = RecommendationBatch(recordedAt: Date(timeIntervalSince1970: 1_800_000_000), host: "Jon MBP", playlist: "Power Pop",
      tracks: [RecommendationTrack(artist: "The Records", title: "Starry Eyes", album: "Shades in Bed",
        year: 1979, familiar: false, reasons: [], artistKnown: true)])
    let encoded = String(decoding: try RecommendationLedgerCodec.encode(batch), as: UTF8.self)
    let expected = [
      #"{"format":"vf-recommendation-batch","host":"Jon MBP","kind":"staged-playlist","playlist":"Power Pop",""#,
      #"recordedAt":"2027-01-15T08:00:00.000Z","source":"chat","tracks":[{"album":"Shades in Bed",""#,
      #"artist":"The Records","artistKnown":true,"familiar":false,"reasons":[],"title":"Starry Eyes","year":1979}],"version":1}"#,
      "\n",
    ].joined()
    #expect(encoded == expected)
  }

  @Test func stagedWithoutReasonUsesNoPlaylistPhraseAndYear() {
    let batch = RecommendationBatch(recordedAt: date(1), host: "Mac", tracks: [
      RecommendationTrack(artist: "The Records", title: "Starry Eyes", familiar: false, reasons: [], artistKnown: true),
    ])
    let spoken = WhyThisSong.spokenText(for: song,
      answer: .stagedWithoutReason(batch: batch, track: batch.tracks[0]), now: Date(timeIntervalSince1970: 1_790_000_000),
      calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
    #expect(spoken == "Starry Eyes by The Records was in a staged batch, staged January 2, 1970, without a reason.")
  }

  @Test func cancelGuardRejectsRepeatedCancelWordsOnly() {
    #expect(MusicFeedback.makeNote("Cancel cancel", selected: nil, source: "time-only", at: .now, device: "iPhone") == nil)
    #expect(MusicFeedback.makeNote("cancel, cancel.", selected: nil, source: "time-only", at: .now, device: "iPhone") == nil)
    #expect(MusicFeedback.makeNote("Cancel culture is a bad name for a band", selected: nil,
      source: "time-only", at: .now, device: "iPhone") != nil)
  }

  private func batch(_ playlist: String, day: TimeInterval, why: String?) -> RecommendationBatch {
    RecommendationBatch(recordedAt: date(day), host: "Mac", playlist: playlist, tracks: [
      RecommendationTrack(artist: "The Records", title: "Starry Eyes", familiar: false,
        reasons: [], artistKnown: true, why: why),
    ])
  }

  private func date(_ day: TimeInterval) -> Date { Date(timeIntervalSince1970: day * 86_400) }
}
