import Dependencies
import Foundation
import MusicKit
import os
import SwiftUI
import VinylFeverCore
import VinylFeverListening

private let listeningLogger = Logger(subsystem: "com.jonphillips.vinylfever", category: "listening-poller")

@main
enum VinylFeverMain {
  static func main() async {
    if CommandLine.arguments.contains("--poll-listening") {
      prepareDependencies(includeDatabase: false)
      do {
        let result = try await ListeningPoller().pollOnce()
        if case let .fetched(fetch) = result, fetch.outcome == .failed {
          listeningLogger.error("Listening poll recorded failure: \(fetch.error ?? "Unknown error", privacy: .public)")
        }
      } catch {
        listeningLogger.error("Listening poll could not write to iCloud: \(error.localizedDescription, privacy: .public)")
        exit(EXIT_FAILURE)
      }
      return
    }
    VinylFeverWindow.main()
  }
}

private struct VinylFeverWindow: App {
  @State private var model: AppModel

  init() {
    prepareDependencies(includeDatabase: true)
    _model = State(initialValue: AppModel())
  }

  var body: some Scene {
    WindowGroup {
      AppShellView(model: model)
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }

    Settings {
      SettingsView(model: model)
    }
  }
}

private func prepareDependencies(includeDatabase: Bool) {
  prepareDependencies {
    $0.listeningStore = .liveValue
    $0.recentlyPlayedClient = .liveValue
    $0.listeningAuthorizationClient = .liveValue
    if includeDatabase {
      try! $0.bootstrapDatabase()
      $0.scriptClient = .liveValue
      $0.audioMetadataClient = .liveValue
      $0.toolPathClient = .liveValue
      $0.runLogClient = .liveValue
      $0.fileOperationClient = .liveValue
      $0.musicAppClient = .liveValue
      $0.librarySnapshotStore = .liveValue
      $0.appleMusicCatalogClient = .liveValue
      $0.catalogMatchResolver = .liveValue
      // LLMClientKit's live defaults read the app's Keychain key per request.
      $0.setlistNormalizer = .liveValue
      $0.collectionRecipeRunner = .liveValue
    }
  }
}
