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
      folderWriteSucceeded: true,
      folderWriteError: nil
    )

    let json = String(decoding: try ProbeRecord.encodeLine(record), as: UTF8.self)
    #expect(json == #"{"device":"iPhone","folderWriteError":null,"folderWriteSucceeded":true,"player":{"currentEntry":{"album":"Album","artist":"Artist","catalogID":"123","title":"Song"},"entryMissing":false,"itemMissing":false,"playbackStatus":"playing","playbackTime":12.5},"recentlyPlayed":[{"artist":"Band","catalogID":"456","title":"Recent"}],"startedFrom":null,"time":"1970-01-01T00:00:00Z"}"# + "\n")
  }

  @Test func bookmarkStoreSavesAndResolvesATemporaryFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    try ProbeBookmarkStore.save(folder, defaults: defaults)
    #expect(try ProbeBookmarkStore.resolve(defaults: defaults).standardizedFileURL == folder.standardizedFileURL)
  }

  @Test func probeFilenameDoesNotLookLikeATasteNotesFile() {
    #expect(ProbeRecord.filename(for: "Jon’s iPhone") == "m20-s0-Jon--s-iPhone.jsonl")
    #expect(!ProbeRecord.filename(for: "iPhone").hasPrefix("notes"))
  }
}
