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

  @Test func newMusicPickedAndUnpickedSpokenGoldens() {
    let picked = musicBatch(picked: true, why: "The chorus has a bright, loose energy.")
    let answer = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [picked], skippedLines: 0), unreadableFileCount: 0)
    guard case let .withReason(batch, track) = answer else { Issue.record("Expected the picked track's reason"); return }
    let pickedText = WhyThisSong.spokenText(for: song, answer: .withReason(batch: batch, track: track),
      now: Date(timeIntervalSince1970: 1_790_000_000), calendar: utcCalendar, timeZone: utc)
    #expect(pickedText == "Starry Eyes by The Records was one of the chat's New Music picks on October 30. The chorus has a bright, loose energy.")

    let unpicked = musicBatch(picked: false, why: "This reason must not be spoken.")
    let unpickedAnswer = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [unpicked], skippedLines: 0), unreadableFileCount: 0)
    guard case let .notPicked(unpickedBatch, unpickedTrack) = unpickedAnswer else {
      Issue.record("Expected an unpicked outcome"); return
    }
    let unpickedText = WhyThisSong.spokenText(for: song,
      answer: .notPicked(batch: unpickedBatch, track: unpickedTrack),
      now: Date(timeIntervalSince1970: 1_790_000_000), calendar: utcCalendar, timeZone: utc)
    #expect(unpickedText == "The chat saw Starry Eyes by The Records in New Music on October 30 and didn't pick it.")
  }

  @Test func pickedNewMusicWithoutReasonSpokenGolden() {
    let picked = musicBatch(picked: true, why: nil)
    let answer = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [picked], skippedLines: 0), unreadableFileCount: 0)
    guard case let .stagedWithoutReason(batch, track) = answer else {
      Issue.record("Expected the picked New Music track without a reason"); return
    }
    let spoken = WhyThisSong.spokenText(for: song,
      answer: .stagedWithoutReason(batch: batch, track: track),
      now: Date(timeIntervalSince1970: 1_790_000_000), calendar: utcCalendar, timeZone: utc)
    #expect(spoken == "Starry Eyes by The Records was one of the chat's New Music picks on October 30, without a reason.")
  }

  @Test func stagedReasonBeatsNewMusicUnpickedAndUnreadableDoesNotHideNotPicked() {
    let unpicked = musicBatch(picked: false, why: nil)
    let staged = batch("Prior picks", day: 10, why: "An older staged recommendation.")
    let preferred = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [unpicked, staged], skippedLines: 0), unreadableFileCount: 1)
    if case .withReason = preferred {} else { Issue.record("Expected the staged recommendation reason") }

    let onlyUnpicked = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [unpicked], skippedLines: 0), unreadableFileCount: 1)
    if case .notPicked = onlyUnpicked {} else { Issue.record("Unreadable files must not hide a known unpicked result") }
  }

  @Test func matchingRecommendationStillAnswersWhenAnotherFileIsUnreadable() {
    let recommendation = batch("Earlier", day: 1, why: "A reason.")
    let answer = WhyThisSong.answer(for: song,
      ledger: RecommendationLedgerReadResult(batches: [recommendation], skippedLines: 0), unreadableFileCount: 1)
    if case .withReason = answer {} else { Issue.record("Expected the readable match to answer") }
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

  private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

  private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
  }

  private func musicBatch(picked: Bool, why: String?) -> RecommendationBatch {
    RecommendationBatch(kind: "new-music-picks", recordedAt: Date(timeIntervalSince1970: 1_793_318_400),
      host: "Mac", tracks: [RecommendationTrack(artist: "The Records", title: "Starry Eyes",
        familiar: false, reasons: [], artistKnown: true, why: why, picked: picked)])
  }
}
