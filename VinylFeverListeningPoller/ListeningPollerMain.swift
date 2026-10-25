import Dependencies
import Foundation
import MusicKit
import os
import SwiftUI
import VinylFeverListening

private let logger = Logger(subsystem: "com.jonphillips.vinylfever.listeningpoller", category: "poller")

@main
struct ListeningPollerMain {
  static func main() async {
    @Dependency(\.context) var context
    if CommandLine.arguments.contains("--poll") {
      preparePollerDependencies(context: context)
      do {
        let result = try await ListeningPoller().pollOnce()
        if case let .fetched(fetch) = result, fetch.outcome == .failed {
          logger.error("Listening poll recorded failure: \(fetch.error ?? "Unknown error", privacy: .public)")
        }
      } catch {
        logger.error("Listening poll could not write to iCloud: \(ListeningErrorDescription.describe(error), privacy: .public)")
        exit(EXIT_FAILURE)
      }
      return
    }
    preparePollerDependencies(context: context)
    ListeningPollerWindow.main()
  }
}

private func preparePollerDependencies(context: DependencyContext) {
  prepareDependencies {
    $0.listeningStore = .liveValue
    $0.recentlyPlayedClient = .liveValue
    $0.listeningAuthorizationClient = .liveValue
    if installsLiveTasteClients(context) { $0.newMusicCatalogClient = .liveValue }
  }
}

private struct ListeningPollerWindow: App {
  var body: some Scene {
    WindowGroup {
      ListeningPollerSettingsView()
        .frame(width: 520)
    }
    .windowResizability(.contentSize)
  }
}
