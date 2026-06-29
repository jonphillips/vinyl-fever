import Dependencies
import SwiftUI
import VinylFeverCore

@main
struct VinylFeverApp: App {
  @State private var model: AppModel

  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
      $0.scriptClient = .liveValue
      $0.audioMetadataClient = .liveValue
      $0.toolPathClient = .liveValue
      $0.runLogClient = .liveValue
      $0.fileOperationClient = .liveValue
      $0.musicAppClient = .liveValue
    }
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
