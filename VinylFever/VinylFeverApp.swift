import Dependencies
import SwiftUI
import VinylFeverCore

@main
struct VinylFeverApp: App {
  @State private var model: AppModel

  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
      $0.toolPathClient = .liveValue
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
