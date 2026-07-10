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
      // The Setlist Normalizer's live sandwich. `modelClient` and `apiKeyStore` need no
      // wiring — LLMClientKit ships live defaults (TieredModelClient.live reads the
      // Keychain per request), and we don't share keys across apps here, so the default
      // (app-own) access group is correct. Only this seam has an unimplemented testValue,
      // so without it the Normalize path throws the moment the sheet runs.
      $0.setlistNormalizer = .liveValue
      // Same story as the normalizer: the recipe runner's testValue is unimplemented,
      // so without this the recipe workbench throws `Unimplemented` the moment a
      // sample runs. Its liveValue runs the deterministic engine for model-off recipes
      // and the on-device classify stage (reading `\.modelClient`) behind `useModel`.
      $0.collectionRecipeRunner = .liveValue
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
