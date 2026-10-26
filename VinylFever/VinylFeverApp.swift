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
private let backupLogger = Logger(subsystem: "com.jonphillips.vinylfever", category: "daily-backup")

@main
enum VinylFeverMain {
  @MainActor
  static func main() async {
    @Dependency(\.context) var context
    if CommandLine.arguments.contains("--poll-listening") {
      do {
        try prepareVinylFeverDependencies(includeDatabase: false, context: context)
      } catch {
        listeningLogger.error("Listening poll could not initialize: \(ListeningErrorDescription.describe(error), privacy: .public)")
        exit(EXIT_FAILURE)
      }
      var pollFailed = false
      do {
        let result = try await ListeningPoller().pollOnce()
        if case let .fetched(fetch) = result, fetch.outcome == .failed {
          listeningLogger.error("Listening poll recorded failure: \(fetch.error ?? "Unknown error", privacy: .public)")
          pollFailed = true
        }
      } catch {
        listeningLogger.error("Listening poll could not write to iCloud: \(ListeningErrorDescription.describe(error), privacy: .public)")
        pollFailed = true
      }
      if shouldRunDailyBackup(in: context) {
        await Task.detached(priority: .utility) { runDailyBackup() }.value
      }
      if pollFailed { exit(EXIT_FAILURE) }
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
      try prepareVinylFeverDependencies(includeDatabase: true, context: context)
    } catch {
      showStartupAlert(error.localizedDescription)
      return
    }
    if shouldRunDailyBackup(in: context) {
      Task.detached(priority: .utility) { runDailyBackup() }
    }
    VinylFeverWindow.main()
  }
}

func shouldRunDailyBackup(in context: DependencyContext) -> Bool {
  context == .live
}

private func runDailyBackup() {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  let dailyRoot = DailyBackup.dailyRoot(in: support)
  let iCloudRoot = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever", directoryHint: .isDirectory)
  let input = DailyBackupInput(
    databaseURL: VinylFeverDatabase.liveDatabaseURL,
    dailyRoot: dailyRoot,
    iCloudRoot: iCloudRoot,
    processedInboxRoot: support.appending(path: "VinylFever/PlaylistInbox/Processed", directoryHint: .isDirectory),
    iCloudDatabaseBackupRoot: iCloudRoot.appending(path: "Backups", directoryHint: .isDirectory),
    host: ListeningStore.liveHostName(),
    build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
  )
  do {
    switch try DailyBackup.make(input) {
    case .created(let date, let bytes, let warnings):
      backupLogger.info("Created daily backup \(date, privacy: .public), \(bytes, privacy: .public) bytes, \(warnings.count, privacy: .public) warnings")
    case .alreadyExists:
      break
    case .anotherRunIsActive:
      backupLogger.info("Daily backup skipped because another run holds the lock")
    }
  } catch {
    try? DailyBackup.recordFailure(error.localizedDescription, in: dailyRoot)
    backupLogger.error("Daily backup failed: \(error.localizedDescription, privacy: .public)")
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

private func prepareVinylFeverDependencies(includeDatabase: Bool, context: DependencyContext) throws {
  let database: (any DatabaseWriter)?
  if includeDatabase {
    database = try VinylFeverDatabase.open()
  } else {
    database = nil
  }
  prepareDependencies {
    $0.listeningStore = .liveValue
    $0.recentlyPlayedClient = .liveValue
    if installsLiveTasteClients(context) {
      $0.newMusicCatalogClient = .liveValue
      $0.tasteCurationClient = TasteCurationClient(append: { change, host, folder in
        try TasteCurationLog.append(change, host: host, folder: folder)
      })
    }
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
