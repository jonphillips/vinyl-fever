import Dependencies
import SwiftUI

struct AppShellView: View {
  @Bindable var model: AppModel
  @State private var playlistBuilderModel = PlaylistBuilderModel()
  @State private var playlistRoleBannerModel = PlaylistRoleBannerModel()
  @Dependency(\.context) private var context
  @Environment(\.openSettings) private var openSettings

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
      VStack(spacing: 0) {
        playlistRoleBanner
        Group {
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
      }
    }
    .task {
      // The test host launches this view too; its launch refresh would read live dependencies
      // in the middle of unrelated tests.
      guard context == .live else { return }
      await playlistBuilderModel.loadSnapshotAndRefreshIfStale()
      await playlistRoleBannerModel.snapshotLoaded(playlistBuilderModel.librarySnapshot)
    }
    .onChange(of: playlistBuilderModel.librarySnapshot?.generatedAt) { _, _ in
      guard context == .live, let snapshot = playlistBuilderModel.librarySnapshot else { return }
      Task { await playlistRoleBannerModel.snapshotLoaded(snapshot) }
    }
    .onChange(of: model.playlistRolesRequest) { _, request in
      guard request != nil else { return }
      openSettings()
    }
  }

  @ViewBuilder
  private var playlistRoleBanner: some View {
    VStack(spacing: 0) {
      if let errorMessage = playlistRoleBannerModel.errorMessage {
        Label("Couldn't check playlist roles: \(errorMessage)", systemImage: "exclamationmark.triangle.fill")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(.red.opacity(0.12))
      } else if let announcement = playlistRoleBannerModel.announcement {
        Label {
          Text((try? AttributedString(markdown: announcement)) ?? AttributedString(announcement))
        } icon: {
          Image(systemName: "checkmark.circle.fill")
        }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(.green.opacity(0.12))
      }
      switch playlistRoleBannerModel.state {
      case .hidden:
        EmptyView()
      case let .unlabeled(names, remaining):
        HStack(spacing: 12) {
          Label(bannerMessage(names: names, remaining: remaining), systemImage: "tag")
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Label…") { model.requestPlaylistRoles() }
          Button("Not now") { playlistRoleBannerModel.dismiss() }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.yellow.opacity(0.16))
      }
    }
  }

  private func bannerMessage(names: [String], remaining: Int) -> String {
    let count = names.count + remaining
    let list = names.joined(separator: ", ") + (remaining > 0 ? " and \(remaining) more" : "")
    return "\(count) playlist\(count == 1 ? "" : "s") ha\(count == 1 ? "s" : "ve") no role: \(list)"
  }
}

#Preview {
  AppShellView(model: AppModel())
}
