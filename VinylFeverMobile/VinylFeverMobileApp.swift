import MusicKit
import VinylFeverNotes
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
      .navigationTitle("Vinyl Fever")
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
