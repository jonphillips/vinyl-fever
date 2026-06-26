import SwiftUI

struct AppShellView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selectedSection) {
        ForEach(AppSection.allCases) { section in
          Label(section.title, systemImage: section.systemImage)
            .tag(section)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
    } detail: {
      switch model.selectedSection {
      case .liveShows:
        ContentUnavailableView("Live Shows", systemImage: "music.note.list")
      case .collections:
        ContentUnavailableView("Collections", systemImage: "rectangle.stack")
      }
    }
  }
}

#Preview {
  AppShellView(model: AppModel())
}
