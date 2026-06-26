import Dependencies
import SwiftUI
import VinylFeverCore

@main
struct VinylFeverApp: App {
  @State private var model = AppModel()

  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
    }
  }

  var body: some Scene {
    WindowGroup {
      AppShellView(model: model)
    }
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
