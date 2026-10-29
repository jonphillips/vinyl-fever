import Foundation
import Testing
import VinylFeverNotes

struct MusicFeedbackTests {
  @Test func stalenessUsesPlayerStateAndTitleArtistAcrossChangingIDs() {
    let entry = FeedbackSong(title: " Song ", artist: "Beyoncé", catalogID: "i.library")
    let newer = FeedbackSong(title: "New", artist: "Artist", catalogID: "123")
    let same = FeedbackSong(title: "song", artist: "Beyoncé", catalogID: "catalog.456")

    #expect(MusicFeedback.identify(entry: entry, playbackStatus: "playing", recentlyPlayed: [same]).isTrusted)
    #expect(MusicFeedback.identify(entry: entry, playbackStatus: "playing", recentlyPlayed: []).isTrusted)
    #expect(MusicFeedback.identify(entry: entry, playbackStatus: "paused", recentlyPlayed: []).staleReason == .notPlaying)
    #expect(MusicFeedback.identify(entry: nil, playbackStatus: "playing", recentlyPlayed: []).staleReason == .missingEntry)
    #expect(MusicFeedback.identify(entry: FeedbackSong(title: "  ", artist: "Band"), playbackStatus: "playing", recentlyPlayed: []).staleReason == .blankTitle)

    let stuck = MusicFeedback.identify(entry: entry, playbackStatus: "playing", recentlyPlayed: [newer, same])
    #expect(stuck.staleReason == .belowNewerSong)
    #expect(stuck.choices == [newer, same])
  }

  @Test func pickListPutsEntryFirstDeduplicatesAndCapsAtFour() {
    let entry = FeedbackSong(title: "Current", artist: "Band", catalogID: "i.current")
    let recent = [
      FeedbackSong(title: "Current", artist: "Band", catalogID: "catalog.current"),
      FeedbackSong(title: "One", artist: "A"),
      FeedbackSong(title: "Two", artist: "B"),
      FeedbackSong(title: "Three", artist: "C"),
      FeedbackSong(title: "Four", artist: "D"),
    ]
    let result = MusicFeedback.identify(entry: entry, playbackStatus: "playing", recentlyPlayed: recent)
    #expect(result.choices.map(\.title) == ["Current", "One", "Two", "Three"])

    let belowNewer = MusicFeedback.identify(entry: entry, playbackStatus: "playing", recentlyPlayed: [
      FeedbackSong(title: "Newer", artist: "Artist"), recent[0], recent[1],
    ])
    #expect(belowNewer.choices.map(\.title) == ["Newer", "Current", "One"])
  }

  @Test func codecIncludesCatalogIDAndLeavesOlderLineBytesUnchanged() throws {
    let legacy = TasteNote(notedAt: Date(timeIntervalSince1970: 0), note: "Good", source: "now-playing", title: "Song", artist: "Band")
    let expected = #"{"artist":"Band","format":"vf-taste-note","note":"Good","notedAt":"1970-01-01T00:00:00.000Z","source":"now-playing","title":"Song","version":1}"# + "\n"
    #expect(String(decoding: try TasteNotesCodec.encode(legacy), as: UTF8.self) == expected)

    let feedback = TasteNote(notedAt: Date(timeIntervalSince1970: 0), note: "Good", source: "picked", title: "Song", artist: "Band", catalogID: "i.song")
    let data = try TasteNotesCodec.encode(feedback)
    #expect(String(decoding: data, as: UTF8.self).contains(#""catalogID":"i.song""#))
    #expect(TasteNotesCodec.readFiles([data]).notes.first?.catalogID == "i.song")
  }

  @Test func eachFeedbackSourceHasAGoldenV1Line() throws {
    let song = FeedbackSong(title: "Song", artist: "Band", album: "Album", catalogID: "i.song", playCount: 0, duration: "3:05")
    let nowPlaying = try #require(MusicFeedback.makeNote("Like it", selected: song, source: "now-playing", at: Date(timeIntervalSince1970: 0), device: "iPad"))
    let picked = try #require(MusicFeedback.makeNote("Like it", selected: song, source: "picked", at: Date(timeIntervalSince1970: 0), device: "iPad"))
    let timeOnly = try #require(MusicFeedback.makeNote("Like it", selected: nil, source: "time-only", at: Date(timeIntervalSince1970: 0), device: "iPad"))

    let identified = #"{"album":"Album","artist":"Band","catalogID":"i.song","device":"iPad","duration":"3:05","format":"vf-taste-note","note":"Like it","notedAt":"1970-01-01T00:00:00.000Z","playCount":0,"source":"now-playing","title":"Song","version":1}"# + "\n"
    #expect(String(decoding: try TasteNotesCodec.encode(nowPlaying), as: UTF8.self) == identified)
    #expect(String(decoding: try TasteNotesCodec.encode(picked), as: UTF8.self) == identified.replacingOccurrences(of: "now-playing", with: "picked"))
    #expect(String(decoding: try TasteNotesCodec.encode(timeOnly), as: UTF8.self)
      == #"{"device":"iPad","format":"vf-taste-note","note":"Like it","notedAt":"1970-01-01T00:00:00.000Z","source":"time-only","version":1}"# + "\n")
  }

  @Test func appendsToTheCoordinatedFeedbackFileWithSafeDeviceName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let note = TasteNote(notedAt: Date(timeIntervalSince1970: 0), note: "Love it", source: "picked", title: "Song", artist: "Band")
    try TasteNotesCodec.appendFeedbackNote(note, device: "Jon’s iPhone", folder: root)
    let url = root.appendingPathComponent("notes-feedback-Jon_s_iPhone.jsonl")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(TasteNotesCodec.readFiles([try Data(contentsOf: url)]).notes == [note])
  }

  @Test func emptyFeedbackDoesNotProduceANote() {
    #expect(MusicFeedback.makeNote(" \n", selected: nil, source: "time-only", at: .distantPast, device: "iPad") == nil)
    #expect(MusicFeedback.makeNote("word for word", selected: nil, source: "time-only", at: .distantPast, device: "iPad")?.note == "word for word")
  }
}
