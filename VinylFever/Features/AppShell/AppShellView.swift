import Dependencies
import SwiftUI

struct AppShellView: View {
  @Bindable var model: AppModel
  @State private var playlistBuilderModel = PlaylistBuilderModel()
  @Dependency(\.context) private var context

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selectedSection) {
        ForEach(AppSection.allCases) { section in
          HStack {
            Label(section.title, systemImage: section.systemImage)
            if section == .liveShows, model.isLiveShowRunActive {
              Spacer(minLength: 8)
              ProgressView()
                .controlSize(.small)
            }
          }
          .tag(section)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
    } detail: {
      switch model.selectedSection {
      case .liveShows:
        LiveShowsView(model: model)
      case .collections:
        CollectionsView(model: model)
      case .policies:
        PoliciesView(model: model)
      case .playlists:
        PlaylistsView(model: playlistBuilderModel)
      }
    }
    .task {
      // The test host launches this view too; its launch refresh would read live dependencies
      // in the middle of unrelated tests.
      guard context != .test else { return }
      await playlistBuilderModel.loadSnapshotAndRefreshIfStale()
    }
  }
}

#Preview {
  AppShellView(model: AppModel())
}
