import Dependencies
import Foundation
import Testing
import VinylFeverNotes
@testable import VinylFeverMobile

struct NowPlayingModelTests {
  @Test @MainActor
  func isHiddenWithoutAuthorizationOrCurrentEntry() async {
    let unauthorized = withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { false }
      dependencies.playlistMusicClient.nowPlaying = { stream(nil) }
    }) { NowPlayingModel() }
    await unauthorized.observe()
    #expect(!unauthorized.isAuthorized)
    #expect(unauthorized.item == nil)

    let noEntry = withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.nowPlaying = { stream(nil) }
    }) { NowPlayingModel() }
    await noEntry.observe()
    #expect(noEntry.isAuthorized)
    #expect(noEntry.item == nil)
  }

  @Test @MainActor
  func playPauseUsesTheLatestOutsidePlaybackState() async {
    var paused = 0
    var played = 0
    let model = withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.nowPlaying = {
        AsyncStream { continuation in
          continuation.yield(item(isPlaying: true))
          continuation.yield(item(isPlaying: false))
          continuation.finish()
        }
      }
      dependencies.playlistMusicClient.pause = { paused += 1 }
      dependencies.playlistMusicClient.play = { played += 1 }
    }) { NowPlayingModel() }

    await model.observe()
    await model.togglePlayback()

    #expect(model.item?.isPlaying == false)
    #expect(paused == 0)
    #expect(played == 1)
  }

  @Test @MainActor
  func previousRestartsAfterThreeSecondsAndStepsBackAtOrBeforeThree() async {
    var playbackTime: TimeInterval = 3.01
    var actions: [String] = []
    let model = withDependencies({ dependencies in
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.nowPlaying = { stream(item(isPlaying: false)) }
      dependencies.playlistMusicClient.playbackTime = { playbackTime }
      dependencies.playlistMusicClient.seekToStart = { actions.append("restart") }
      dependencies.playlistMusicClient.skipToPrevious = { actions.append("previous") }
    }) { NowPlayingModel() }
    await model.observe()

    await model.previous()
    playbackTime = 3
    await model.previous()

    #expect(actions == ["restart", "previous"])
  }

  @Test @MainActor
  func commandErrorClearsAfterFourSeconds() async {
    let clock = TestClock()
    let model = withDependencies({ dependencies in
      dependencies.continuousClock = clock
      dependencies.playlistMusicClient.isAuthorized = { true }
      dependencies.playlistMusicClient.nowPlaying = { stream(item(isPlaying: true)) }
      dependencies.playlistMusicClient.pause = { throw TestError.failed }
    }) { NowPlayingModel() }
    await model.observe()

    await model.togglePlayback()
    #expect(model.errorMessage != nil)
    await clock.advance(by: .seconds(4))
    #expect(model.errorMessage == nil)
  }

  private func item(isPlaying: Bool) -> NowPlayingItem {
    NowPlayingItem(song: FeedbackSong(title: "Song", artist: "Artist"), artworkURL: nil,
      isPlaying: isPlaying)
  }

  private func stream(_ item: NowPlayingItem?) -> AsyncStream<NowPlayingItem?> {
    AsyncStream { continuation in
      continuation.yield(item)
      continuation.finish()
    }
  }

  private enum TestError: Error { case failed }
}
