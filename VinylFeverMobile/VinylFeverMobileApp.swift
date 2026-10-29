import MusicKit
import SwiftUI

@main
struct VinylFeverMobileApp: App {
  var body: some Scene {
    WindowGroup {
      MobileSetupView()
    }
  }
}

private struct MobileSetupView: View {
  @State private var authorizationStatus = MusicAuthorization.currentStatus
  @State private var folderName: String?
  @State private var errorMessage: String?
  @State private var isImportingFolder = false

  var body: some View {
    NavigationStack {
      Form {
        Section("iCloud Drive") {
          Button("Grant folder access…") { isImportingFolder = true }
          if let folderName { LabeledContent("Folder", value: folderName) }
        }
        Section("Apple Music") {
          LabeledContent("Authorization", value: String(describing: authorizationStatus))
          Button("Request Music access") {
            Task { authorizationStatus = await MusicAuthorization.request() }
          }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Vinyl Fever")
      .fileImporter(isPresented: $isImportingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
        do {
          let folder = try result.get().first ?? { throw ProbeBookmarkError.folderNotSelected }()
          try ProbeBookmarkStore.save(folder)
          folderName = folder.lastPathComponent
          errorMessage = nil
        } catch {
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}
