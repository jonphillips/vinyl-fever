import Dependencies
import Foundation
import Testing
import VinylFeverCore
import VinylFeverNotes

struct PlaylistReviewAlertSenderTests {
  @Test func sendsOneMessageForANeedsReviewEventAndDoesNotRepeat() async {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let event = PlaylistCreationEvent(kind: .needsReview, host: "Mac", recordedAt: at,
      playlist: "Power Pop", at: at, writerHost: "Mac",
      skipped: [PlaylistCreationSkippedSong(title: "Song 2", artist: "Artist 2", reason: "not-found"),
        PlaylistCreationSkippedSong(title: "Song 3", artist: "Artist 3", reason: "ambiguous")])
    let recorder = AlertRecorder(phoneNumber: "+15551234567")

    await withDependencies({ dependencies in
      dependencies.playlistCreationClient.read = { .init(events: [event], skippedLines: 0, filesRead: 1) }
      dependencies.playlistInboxClient.list = { [] }
      dependencies.playlistAlertClient = recorder.client
    }) {
      await PlaylistReviewAlertSender().sendPendingAlerts()
      await PlaylistReviewAlertSender().sendPendingAlerts()
    }

    #expect(recorder.sentMessages.count == 1)
    #expect(recorder.sentMessages.first?.1 == "Power Pop: 0 of 2 songs found. Needs: Song 2 — Artist 2; Song 3 — Artist 3.\nFinish it in Vinyl Fever on your phone.")
  }

  @Test func emptyHandleLogsAndMarksTheEventWithoutFailing() async {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let event = PlaylistCreationEvent(kind: .needsReview, host: "Mac", recordedAt: at,
      playlist: "Power Pop", at: at, writerHost: "Mac", error: "Apple Music unavailable.")
    let recorder = AlertRecorder(phoneNumber: "  ")

    await withDependencies({ dependencies in
      dependencies.playlistCreationClient.read = { .init(events: [event], skippedLines: 0, filesRead: 1) }
      dependencies.playlistInboxClient.list = { [] }
      dependencies.playlistAlertClient = recorder.client
    }) {
      await PlaylistReviewAlertSender().sendPendingAlerts()
    }

    #expect(recorder.sentMessages.isEmpty)
    #expect(recorder.attemptedKeys.count == 1)
    #expect(PlaylistReviewAlertSender.message(for: event, totalSongs: 0)
      == "Power Pop: Apple Music unavailable.\nFinish it in Vinyl Fever on your phone.")
  }
}

private final class AlertRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let storedPhoneNumber: String
  private var storedKeys: Set<String> = []
  private var storedMessages: [(String, String)] = []

  init(phoneNumber: String) { storedPhoneNumber = phoneNumber }

  var client: PlaylistAlertClient {
    PlaylistAlertClient(
      phoneNumber: { self.storedPhoneNumber }, savePhoneNumber: { _ in },
      hasAttempted: { key in self.lock.withLock { self.storedKeys.contains(key) } },
      markAttempted: { key in self.lock.withLock { _ = self.storedKeys.insert(key) } },
      send: { phoneNumber, message in self.lock.withLock { self.storedMessages.append((phoneNumber, message)) } }
    )
  }

  var attemptedKeys: Set<String> { lock.withLock { storedKeys } }
  var sentMessages: [(String, String)] { lock.withLock { storedMessages } }
}
