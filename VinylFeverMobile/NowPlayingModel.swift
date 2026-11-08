import Dependencies
import Foundation
import Observation

@MainActor
@Observable
final class NowPlayingModel {
  private(set) var isAuthorized = false
  private(set) var item: NowPlayingItem?
  private(set) var errorMessage: String?

  @ObservationIgnored @Dependency(\.playlistMusicClient) private var client
  @ObservationIgnored @Dependency(\.continuousClock) private var clock
  private var errorTask: Task<Void, Never>?
  private var errorID = UUID()

  func refreshAuthorization() {
    let wasAuthorized = isAuthorized
    isAuthorized = client.isAuthorized()
    if wasAuthorized && !isAuthorized { item = nil }
  }

  func observe() async {
    refreshAuthorization()
    guard isAuthorized else {
      item = nil
      return
    }
    for await item in client.nowPlaying() {
      self.item = item
    }
  }

  func togglePlayback() async {
    guard isAuthorized, item != nil else { return }
    do {
      if item?.isPlaying == true {
        try await client.pause()
      } else {
        try await client.play()
      }
      clearError()
    } catch {
      showError(error.localizedDescription)
    }
  }

  func previous() async {
    guard isAuthorized, item != nil else { return }
    do {
      if client.playbackTime() > 3 {
        try await client.seekToStart()
      } else {
        try await client.skipToPrevious()
      }
      clearError()
    } catch {
      showError(error.localizedDescription)
    }
  }

  func next() async {
    guard isAuthorized, item != nil else { return }
    do {
      try await client.skipToNext()
      clearError()
    } catch {
      showError(error.localizedDescription)
    }
  }

  private func showError(_ message: String) {
    errorTask?.cancel()
    errorID = UUID()
    let currentID = errorID
    errorMessage = message
    errorTask = Task { @MainActor in
      do {
        try await clock.sleep(for: .seconds(4))
      } catch {
        return
      }
      guard errorID == currentID else { return }
      errorMessage = nil
    }
  }

  private func clearError() {
    errorTask?.cancel()
    errorTask = nil
    errorMessage = nil
  }
}
