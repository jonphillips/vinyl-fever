import Foundation
import LLMHandoffKit
import Testing
import VinylFeverCore

struct PlaylistInboxClientTests {
  @Test("lists newest first and moves reviewed handoffs to Processed without deleting them")
  func inboxLifecycle() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let inbox = HandoffInbox(root: root, fileExtension: "vfplaylist")
    let earlier = try inbox.stage("VF-PLAYLIST: v1\n{\"name\":\"Earlier\",\"tracks\":[{\"artist\":\"A\",\"title\":\"One\"}]}", slug: "Earlier", now: Date(timeIntervalSince1970: 1))
    let later = try inbox.stage("VF-PLAYLIST: v1\n{\"name\":\"Later\",\"tracks\":[{\"artist\":\"B\",\"title\":\"Two\"}]}", slug: "Later", now: Date(timeIntervalSince1970: 2))
    let client = PlaylistInboxClient.live(root: root)

    let items = try client.list()
    #expect(items.map(\.name) == ["Later", "Earlier"])
    #expect(items.map(\.trackCount) == [1, 1])
    #expect(try PlaylistContract.decode(client.read(items[0].handoff)).request.name == "Later")

    let processed = try client.markProcessed(items[0].handoff)
    #expect(try client.list().map(\.name) == ["Earlier"])
    #expect(FileManager.default.fileExists(atPath: processed.url.path))
    #expect(FileManager.default.fileExists(atPath: earlier.url.path))
    #expect(FileManager.default.fileExists(atPath: later.url.path) == false)
  }
}
