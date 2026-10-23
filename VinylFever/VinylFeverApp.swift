import AppKit
import Dependencies
import Foundation
import MusicKit
import os
import SQLiteData
import SwiftUI
import VinylFeverCore
import VinylFeverListening

private let listeningLogger = Logger(subsystem: "com.jonphillips.vinylfever", category: "listening-poller")

@main
enum VinylFeverMain {
  @MainActor
  static func main() async {
    @Dependency(\.context) var context
    if CommandLine.arguments.contains("--poll-listening") {
      do {
        try prepareDependencies(includeDatabase: false)
        let result = try await ListeningPoller().pollOnce()
        if case let .fetched(fetch) = result, fetch.outcome == .failed {
          listeningLogger.error("Listening poll recorded failure: \(fetch.error ?? "Unknown error", privacy: .public)")
        }
      } catch {
        listeningLogger.error("Listening poll could not write to iCloud: \(ListeningErrorDescription.describe(error), privacy: .public)")
        exit(EXIT_FAILURE)
      }
      return
    }
    if context == .live, await openInstalledCopyIfRunningBuildIsStale() { return }
    let legacyPath = VinylFeverDatabase.legacyDatabaseURL.path(percentEncoded: false)
    let databasePath = VinylFeverDatabase.liveDatabaseURL.path(percentEncoded: false)
    if context == .live,
      VinylFeverDatabase.needsLegacyAdoption(legacyPath: legacyPath, newPath: databasePath),
      anotherRegularVinylFeverCopyIsRunning()
    {
      showStartupAlert("Quit the other copy of Vinyl Fever, then open this one again.")
      return
    }
    do {
      try prepareDependencies(includeDatabase: true)
    } catch {
      showStartupAlert(error.localizedDescription)
      return
    }
    VinylFeverWindow.main()
  }
}

@MainActor
private func openInstalledCopyIfRunningBuildIsStale() async -> Bool {
  let runningURL = Bundle.main.bundleURL
  let installedURL = URL(fileURLWithPath: "/Applications/VinylFever.app", isDirectory: true)
  let installedExists = FileManager.default.fileExists(atPath: installedURL.path)
  let runningDate = InstalledBuildCheck.buildDate(in: runningURL)
  let installedDate = installedExists ? InstalledBuildCheck.buildDate(in: installedURL) : nil
  guard case let .olderThanInstalled(installedDate) = InstalledBuildCheck.result(
    runningBundleURL: runningURL,
    runningBuildDate: runningDate,
    installedBundleURL: installedExists ? installedURL : nil,
    installedBuildDate: installedDate
  ) else { return false }

  let formatter = DateFormatter()
  formatter.dateStyle = .medium
  formatter.timeStyle = .short
  let application = NSApplication.shared
  application.setActivationPolicy(.regular)
  application.activate(ignoringOtherApps: true)
  let alert = NSAlert()
  alert.alertStyle = .warning
  alert.messageText = "This copy of Vinyl Fever was built \(formatter.string(from: runningDate ?? .distantPast)), and the one in Applications was built \(formatter.string(from: installedDate)). Open the installed copy?"
  alert.addButton(withTitle: "Open Installed Copy")
  alert.addButton(withTitle: "Keep This Copy")
  alert.buttons.first?.keyEquivalent = "\r"
  guard alert.runModal() == .alertFirstButtonReturn else { return false }

  let installedPath = installedURL.resolvingSymlinksInPath().standardizedFileURL
  let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.jonphillips.vinylfever"
  let currentApplication = NSRunningApplication.current
  if let installedApplication = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .first(where: {
      !$0.isEqual(currentApplication)
        && $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == installedPath
    })
  {
    _ = installedApplication.activate(options: [])
    return true
  }

  let configuration = NSWorkspace.OpenConfiguration()
  configuration.createsNewApplicationInstance = true
  do {
    _ = try await NSWorkspace.shared.openApplication(at: installedURL, configuration: configuration)
    return true
  } catch {
    listeningLogger.error("Could not open installed Vinyl Fever: \(error.localizedDescription, privacy: .public)")
    return false
  }
}

private struct VinylFeverWindow: App {
  @State private var model: AppModel

  init() {
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

@MainActor
private func anotherRegularVinylFeverCopyIsRunning() -> Bool {
  let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.jonphillips.vinylfever"
  let currentProcessID = ProcessInfo.processInfo.processIdentifier
  return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .contains { $0.processIdentifier != currentProcessID && $0.activationPolicy == .regular }
}

@MainActor
private func showStartupAlert(_ message: String) {
  let application = NSApplication.shared
  application.setActivationPolicy(.regular)
  application.activate(ignoringOtherApps: true)
  let alert = NSAlert()
  alert.alertStyle = .critical
  alert.messageText = message
  alert.runModal()
}

private func prepareDependencies(includeDatabase: Bool) throws {
  let database: (any DatabaseWriter)?
  if includeDatabase {
    database = try VinylFeverDatabase.open()
  } else {
    database = nil
  }
  prepareDependencies {
    $0.listeningStore = .liveValue
    $0.recentlyPlayedClient = .liveValue
    $0.listeningAuthorizationClient = .liveValue
    if let database {
      $0.defaultDatabase = database
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
