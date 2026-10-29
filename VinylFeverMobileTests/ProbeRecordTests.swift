import Foundation
import Testing
@testable import VinylFeverMobile

struct ProbeRecordTests {
  @Test func encodesTheProbeLineAsGoldenJSON() throws {
    let record = ProbeRecord(
      time: Date(timeIntervalSince1970: 0),
      device: "iPhone",
      startedFrom: nil,
      player: ProbeRecord.Player(
        playbackStatus: "playing",
        playbackTime: 12.5,
        currentEntry: ProbeRecord.Entry(title: "Song", artist: "Artist", album: "Album", catalogID: "123"),
        entryMissing: false,
        itemMissing: false
      ),
      recentlyPlayed: [ProbeRecord.RecentSong(title: "Recent", artist: "Band", catalogID: "456")],
      recentlyPlayedError: "Music unavailable",
      previousWriteFailure: ProbeRecord.WriteFailure(time: Date(timeIntervalSince1970: 0), error: "Earlier write failed")
    )

    let json = String(decoding: try ProbeRecord.encodeLine(record), as: UTF8.self)
    #expect(json == #"{"device":"iPhone","player":{"currentEntry":{"album":"Album","artist":"Artist","catalogID":"123","title":"Song"},"entryMissing":false,"itemMissing":false,"playbackStatus":"playing","playbackTime":12.5},"previousWriteFailure":{"error":"Earlier write failed","time":"1970-01-01T00:00:00Z"},"recentlyPlayed":[{"artist":"Band","catalogID":"456","title":"Recent"}],"recentlyPlayedError":"Music unavailable","time":"1970-01-01T00:00:00Z"}"# + "\n")
  }

  @Test func bookmarkStoreSavesAndResolvesATemporaryFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try ProbeBookmarkStore.save(folder, defaults: defaults)
    let resolved = try ProbeBookmarkStore.resolve(defaults: defaults).folder
    #expect(resolved.standardizedFileURL == folder.standardizedFileURL)
    try ProbeBookmarkStore.save(resolved, defaults: defaults)
    #expect(try ProbeBookmarkStore.resolve(defaults: defaults).folder.standardizedFileURL == folder.standardizedFileURL)
  }

  @Test func probeFilenameDoesNotLookLikeATasteNotesFile() {
    #expect(ProbeRecord.filename(for: "Jon’s iPhone") == "m20-s0-Jon-s-iPhone.jsonl")
    #expect(!ProbeRecord.filename(for: "iPhone").hasPrefix("notes"))
    #expect(ProbeRecord.feedbackFilename(for: "Jon’s iPhone") == "feedback-Jon-s-iPhone.jsonl")
  }

  @Test func feedbackEvidenceLineIsGoldenJSON() throws {
    let record = ProbeRecord(
      time: Date(timeIntervalSince1970: 0), device: "iPhone", startedFrom: nil,
      player: ProbeRecord.Player(
        playbackStatus: "playing", playbackTime: 12.5,
        currentEntry: ProbeRecord.Entry(title: "Song", artist: "Band", album: "Album", catalogID: "i.song"),
        entryMissing: false, itemMissing: false
      ),
      recentlyPlayed: [ProbeRecord.RecentSong(title: "New", artist: "Artist", catalogID: "123")],
      recentlyPlayedError: nil, previousWriteFailure: nil,
      staleReason: "belowNewerSong", offeredChoices: ["New by Artist", "Song by Band"],
      savedSong: ProbeRecord.Entry(title: "Song", artist: "Band", album: "Album", catalogID: "i.song")
    )
    let line = String(decoding: try ProbeRecord.encodeLine(record), as: UTF8.self)
    #expect(line == #"{"device":"iPhone","offeredChoices":["New by Artist","Song by Band"],"player":{"currentEntry":{"album":"Album","artist":"Band","catalogID":"i.song","title":"Song"},"entryMissing":false,"itemMissing":false,"playbackStatus":"playing","playbackTime":12.5},"recentlyPlayed":[{"artist":"Artist","catalogID":"123","title":"New"}],"savedSong":{"album":"Album","artist":"Band","catalogID":"i.song","title":"Song"},"staleReason":"belowNewerSong","time":"1970-01-01T00:00:00Z"}"# + "\n")
  }

  @Test func missingFolderBookmarkIsRefused() throws {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var refused = false
    do {
      try ProbeBookmarkStore.withFolder(defaults: defaults) { _ in }
    } catch ProbeBookmarkError.folderNotSelected {
      refused = true
    }
    #expect(refused)
  }

  @Test func failedWriteIsRecordedOnTheNextSuccessfulLine() throws {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let blocker = root.appendingPathComponent("not-a-directory")
    try Data("blocker".utf8).write(to: blocker)
    let writer = ProbeLogWriter(defaults: defaults)
    var didThrow = false
    do {
      try writer.write(record(), to: blocker.appendingPathComponent("probe.jsonl"))
    } catch {
      didThrow = true
    }
    #expect(didThrow)

    let successfulURL = root.appendingPathComponent("Probes/m20-s0-test.jsonl")
    let written = try writer.write(record(), to: successfulURL)
    #expect(written.previousWriteFailure?.time == Date(timeIntervalSince1970: 0))
    #expect(written.previousWriteFailure?.error.isEmpty == false)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let line = try decoder.decode(ProbeRecord.self, from: try Data(contentsOf: successfulURL))
    #expect(line.previousWriteFailure == written.previousWriteFailure)

    let nextLine = try writer.write(record(), to: successfulURL)
    #expect(nextLine.previousWriteFailure == nil)
  }

  private func record() -> ProbeRecord {
    ProbeRecord(
      time: Date(timeIntervalSince1970: 0),
      device: "iPhone",
      startedFrom: nil,
      player: ProbeRecord.Player(
        playbackStatus: "playing",
        playbackTime: nil,
        currentEntry: nil,
        entryMissing: true,
        itemMissing: false
      ),
      recentlyPlayed: [],
      recentlyPlayedError: nil,
      previousWriteFailure: nil
    )
  }
}
