import MusicKit
import SwiftUI
import VinylFeverNotes

@main
struct VinylFeverMobileApp: App {
  @State private var shelfModel = PlaylistShelfModel()
  @State private var playbackModel = PlaylistPlaybackModel()

  var body: some Scene {
    WindowGroup {
      PlaylistHomeView(model: shelfModel, playbackModel: playbackModel)
    }
  }
}

private struct PlaylistHomeView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var didApplyInitialSelection = false
  @Bindable var model: PlaylistShelfModel
  let playbackModel: PlaylistPlaybackModel

  private var selectedPlaylist: PlaylistShelfPlaylist? {
    model.playlists.first { $0.id == model.selectedPlaylistID }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $model.selectedPlaylistID) {
        Section {
          if model.hasUnreadableFiles {
            Label("Some recommendations are still downloading from iCloud. Pull to refresh.",
              systemImage: "icloud.and.arrow.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          ForEach(model.playlists) { playlist in
            NavigationLink(value: playlist.id) {
              PlaylistRow(playlist: playlist)
            }
            .tag(playlist.id)
          }
        } header: {
          Text("Playlists")
        }
      }
      .listStyle(.sidebar)
      .navigationTitle("Playlists")
      .refreshable { await model.refresh() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Setup", systemImage: "gearshape") { model.setupButtonTapped() }
        }
      }
    } detail: {
      Group {
        if let playlist = selectedPlaylist {
          PlaylistDetailView(playlist: playlist, hasUnreadableFiles: model.hasUnreadableFiles,
            playbackModel: playbackModel) {
            await model.refresh()
          }
        } else if model.requiresFolderAccess {
          ContentUnavailableView {
            Label("Grant folder access in Setup", systemImage: "folder.badge.questionmark")
          } actions: {
            Button("Open Setup") { model.setupButtonTapped() }
              .buttonStyle(.borderedProminent)
          }
        } else if model.isLoading {
          ProgressView("Loading playlists…")
        } else {
          ContentUnavailableView("No Vinyl Fever playlists yet. Ask the chat for some.", systemImage: "music.note.list")
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Setup", systemImage: "gearshape") { model.setupButtonTapped() }
        }
      }
    }
    .sheet(item: $model.destination, onDismiss: {
      Task {
        await model.refresh()
        if let selectedPlaylist { await playbackModel.prepare(selectedPlaylist) }
      }
    }) { destination in
      switch destination {
      case .setup:
        MobileSetupView()
      }
    }
    .task {
      await model.refresh()
      guard !didApplyInitialSelection else { return }
      didApplyInitialSelection = true
      if horizontalSizeClass == .regular, model.selectedPlaylistID == nil {
        model.selectedPlaylistID = model.playlists.first?.id
      }
    }
    .task { await playbackModel.observeCurrentEntry() }
  }
}

private struct PlaylistRow: View {
  let playlist: PlaylistShelfPlaylist

  private var title: String {
    guard let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return "Staged playlist"
    }
    return name
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.headline).lineLimit(2)
      Text("\(playlist.stagedDate) · \(playlist.songCount) songs · \(playlist.newSongCount) new")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

private struct PlaylistDetailView: View {
  let playlist: PlaylistShelfPlaylist
  let hasUnreadableFiles: Bool
  let playbackModel: PlaylistPlaybackModel
  let refresh: () async -> Void

  private var title: String {
    guard let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
      return "Staged playlist"
    }
    return name
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        if hasUnreadableFiles {
          Label("Some recommendations are still downloading from iCloud. Pull to refresh.", systemImage: "icloud.and.arrow.down")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        VStack(alignment: .leading, spacing: 10) {
          if let artwork = playbackModel.matchedPlaylist?.artwork {
            ArtworkImage(artwork, width: 180)
              .clipShape(.rect(cornerRadius: 8))
              .accessibilityLabel("\(title) artwork")
          }
          Text(title).font(.largeTitle.bold())
          Text("\(playlist.stagedDate) · \(playlist.songCount) songs · \(playlist.newSongCount) new to you")
            .foregroundStyle(.secondary)
          if let request = playlist.batch.request, !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("You asked").font(.headline)
              Text(request)
            }
            .padding(.top, 8)
          }
          if let noReasons = PlaylistShelf.noReasonsText(for: playlist) {
            Text(noReasons).foregroundStyle(.secondary).padding(.top, 4)
          }
          if !playbackModel.isAuthorized {
            Label("Allow Apple Music access in Setup", systemImage: "music.note")
              .font(.callout)
              .foregroundStyle(.secondary)
          } else {
            Button {
              guard let first = playlist.songs.first else { return }
              Task { await playbackModel.play(first.id) }
            } label: {
              if playbackModel.isResolving {
                ProgressView().accessibilityLabel("Preparing playlist")
              } else {
                Label("Play All", systemImage: "play.fill")
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(playbackModel.isResolving)
          }
          if let errorMessage = playbackModel.errorMessage {
            Text(errorMessage).font(.callout).foregroundStyle(.red)
          }
        }

        ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
          VStack(spacing: 18) {
            PlaylistSongView(song: song, playbackModel: playbackModel)
            if song.id != playlist.songs.last?.id { Divider() }
          }
          .task {
            await playbackModel.resolveSongs(through: index + PlaylistPlaybackModel.resolveAheadCount)
          }
        }
      }
      .padding()
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .refreshable { await refresh() }
    .task(id: playlist.id) {
      await playbackModel.prepare(playlist)
      await playbackModel.resolveSongs(through: PlaylistPlaybackModel.resolveAheadCount)
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PlaylistSongView: View {
  let song: PlaylistShelfSong
  let playbackModel: PlaylistPlaybackModel
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      if let resolved = playbackModel.resolvedSongs[song.id], let artwork = resolved.artwork {
        ArtworkImage(artwork, width: 68)
          .clipShape(.rect(cornerRadius: 6))
          .accessibilityHidden(true)
      } else {
        Image(systemName: "music.note")
          .font(.title2)
          .foregroundStyle(.secondary)
          .frame(width: 68, height: 68)
          .background(.quaternary, in: .rect(cornerRadius: 6))
      }
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Text(song.title).font(.title3.weight(.semibold))
          if playbackModel.nowPlayingSongID == song.id {
            Image(systemName: "waveform").foregroundStyle(.tint).accessibilityLabel("Now playing")
          }
          Spacer()
          if playbackModel.notFoundSongIDs.contains(song.id) {
            Text("Not in Apple Music").font(.caption).foregroundStyle(.secondary)
          } else if playbackModel.resolvingSongIDs.contains(song.id) {
            ProgressView().accessibilityLabel("Finding \(song.title)")
          } else if playbackModel.resolvedSongs[song.id] != nil {
            Button("Play", systemImage: "play.fill") {
              Task { await playbackModel.play(song.id) }
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Play \(song.title) by \(song.artist)")
          }
        }
        Text(song.artist).foregroundStyle(.secondary)
        if song.album != nil || song.year != nil {
          Text([song.album, song.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text(song.familiarity).font(.subheadline.weight(.medium))
        if let why = song.why {
          Text(why).fixedSize(horizontal: false, vertical: true)
        }
        if !song.like.isEmpty {
          VStack(alignment: .leading, spacing: 5) {
            Text("Sounds like").font(.subheadline.weight(.semibold))
            ForEach(Array(song.like.enumerated()), id: \.offset) { _, like in
              Button {
                Task { await playbackModel.playLike(like, afterCurrent: true) }
              } label: {
                Label("\(like.title) · \(like.artist)", systemImage: "play.fill")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .contextMenu {
                Button("Play Next", systemImage: "text.insert") {
                  Task { await playbackModel.playLike(like, afterCurrent: false) }
                }
              }
            }
          }
          .padding(.top, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct MobileSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var authorizationStatus = MusicAuthorization.currentStatus
  @State private var folderName: String?
  @State private var errorMessage: String?
  @State private var isImportingFolder = false
  @State private var lastNote = FeedbackLastNote.load()
  @State private var feedbackCheck: String?
  @State private var whyCheck: String?
  @State private var whyPreviewChoices: [FeedbackSong] = []
  @State private var isPickingWhyPreview = false

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
        Section("Music Feedback") {
          if let lastNote {
            let song = [lastNote.title, lastNote.artist].compactMap { $0 }.joined(separator: " by ")
            LabeledContent("Last note", value: song.isEmpty ? "Time only" : song)
            LabeledContent("Saved", value: lastNote.notedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Source", value: lastNote.source)
          } else {
            Text("No note saved on this device yet.").foregroundStyle(.secondary)
          }
          Button("Test song identification") {
            Task { await testSongIdentification() }
          }
          if let feedbackCheck { Text(feedbackCheck).foregroundStyle(.secondary) }
        }
        Section("Why This Song") {
          Button("Test Why This Song") {
            Task { await testWhyThisSong() }
          }
          if let whyCheck { Text(whyCheck).foregroundStyle(.secondary) }
        }
        if let errorMessage {
          Section { Text(errorMessage).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Setup")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear { lastNote = FeedbackLastNote.load() }
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
      .confirmationDialog("Which song?", isPresented: $isPickingWhyPreview) {
        ForEach(Array(whyPreviewChoices.enumerated()), id: \.offset) { _, song in
          Button("\(song.title) by \(song.artist)") { Task { await previewWhyThisSong(for: song) } }
        }
        Button("None of these", role: .cancel) { whyCheck = "No song picked. Nothing was saved." }
      }
    }
  }

  @MainActor
  private func testSongIdentification() async {
    let player = SystemMusicPlayer.shared
    let entry = player.queue.currentEntry
    let song: Song?
    if case let .song(value)? = entry?.item { song = value } else { song = nil }
    let current = entry.map {
      FeedbackSong(title: $0.title, artist: song?.artistName ?? "", album: song?.albumTitle, catalogID: song?.id.rawValue)
    }
    var recent: [FeedbackSong] = []
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recent = try await request.response().items.map {
        FeedbackSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch {
      whyCheck = "Recently played could not be read: \(error.localizedDescription)"
      return
    }
    let result = MusicFeedback.identify(
      entry: current,
      playbackStatus: String(describing: player.state.playbackStatus),
      recentlyPlayed: recent
    )
    if result.isTrusted, let current {
      feedbackCheck = "Trusted: \(current.title) by \(current.artist). Nothing was saved."
    } else {
      feedbackCheck = "Needs a song choice (\(result.staleReason?.rawValue ?? "unknown")). Nothing was saved."
    }
  }

  @MainActor
  private func testWhyThisSong() async {
    let player = SystemMusicPlayer.shared
    let entry = player.queue.currentEntry
    let currentSong: Song?
    if case let .song(song)? = entry?.item { currentSong = song } else { currentSong = nil }
    let current = entry.map {
      FeedbackSong(title: $0.title, artist: currentSong?.artistName ?? "", album: currentSong?.albumTitle,
        catalogID: currentSong?.id.rawValue)
    }
    var recent: [FeedbackSong] = []
    do {
      var request = MusicRecentlyPlayedRequest<Song>()
      request.limit = 5
      recent = try await request.response().items.map {
        FeedbackSong(title: $0.title, artist: $0.artistName, catalogID: $0.id.rawValue)
      }
    } catch {}
    let identification = MusicFeedback.identify(
      entry: current, playbackStatus: String(describing: player.state.playbackStatus), recentlyPlayed: recent
    )
    guard identification.isTrusted, let current else {
      whyPreviewChoices = identification.choices
      isPickingWhyPreview = true
      return
    }
    await previewWhyThisSong(for: current)
  }

  @MainActor
  private func previewWhyThisSong(for song: FeedbackSong) async {
    do {
      let text = try ProbeBookmarkStore.withFolder { folder in
        let read = RecommendationLedgerFolderReader.read(folder: folder)
        let answer = WhyThisSong.answer(
          for: song, ledger: read.ledger, unreadableFileCount: read.unreadableFileCount
        )
        return WhyThisSong.spokenText(
          for: song, answer: answer, now: .now, calendar: .current, timeZone: .current
        )
      }
      whyCheck = "\(text) Nothing was saved."
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      whyCheck = "Open Vinyl Fever to grant folder access."
    } catch {
      whyCheck = "Recommendations could not be read: \(error.localizedDescription)"
    }
  }
}
