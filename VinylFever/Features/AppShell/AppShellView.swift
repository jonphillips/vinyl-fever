import SwiftUI

struct AppShellView: View {
  @Bindable var model: AppModel

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
      }
    }
  }
}

#Preview {
  AppShellView(model: AppModel())
}
