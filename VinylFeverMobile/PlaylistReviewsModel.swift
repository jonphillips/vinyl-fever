import Dependencies
import DependenciesMacros
import Foundation
import Observation
import UIKit
import VinylFeverNotes

struct PlaylistReviewsClient {
  var read: @Sendable () async throws -> PlaylistReviewsReadResult
  var append: @Sendable (PlaylistReviewEntry, String) async throws -> Void
  var deviceName: @Sendable () async -> String = { "device" }
}

extension PlaylistReviewsClient: TestDependencyKey {
  static var testValue: Self {
    Self(read: { PlaylistReviewsReadResult(entries: [], skippedLines: 0, filesRead: 0) }, append: { _, _ in })
  }
}

private enum PlaylistReviewsClientKey: DependencyKey {
  static let liveValue = PlaylistReviewsClient(
    read: {
      try await Task.detached {
        try ProbeBookmarkStore.withFolder { folder in
          let result = TasteFolderReader.read(folder: folder, subdirectory: "playlist-reviews",
            includes: { $0.hasSuffix(".jsonl") }, missingDirectoryIsUnavailable: false,
            emptyDirectoryIsUnavailable: false)
          let decoded = PlaylistReviewsCodec.readFiles(result.files)
          return PlaylistReviewsReadResult(entries: decoded.entries,
            skippedLines: decoded.skippedLines + result.unreadableFileCount, filesRead: decoded.filesRead)
        }
      }.value
    },
    append: { entry, writer in
      try ProbeBookmarkStore.withFolder { folder in
        try PlaylistReviewsCodec.append(entry, writer: writer,
          folder: folder.appending(path: "Taste Intelligence/playlist-reviews", directoryHint: .isDirectory))
      }
    },
    deviceName: { await MainActor.run { UIDevice.current.name } }
  )
}

extension DependencyValues {
  var playlistReviewsClient: PlaylistReviewsClient {
    get { self[PlaylistReviewsClientKey.self] }
    set { self[PlaylistReviewsClientKey.self] = newValue }
  }
}

@MainActor
@Observable
final class PlaylistReviewsModel {
  private(set) var entries: [PlaylistReviewEntry] = []
  private(set) var hasUnreadableFiles = false
  private(set) var isSaving = false
  private(set) var errorMessage: String?

  @ObservationIgnored @Dependency(\.playlistReviewsClient) private var client
  @ObservationIgnored @Dependency(\.date.now) private var now

  var finishedEntries: [String: PlaylistReviewEntry] {
    PlaylistReviewsCodec.latestJonState(in: entries).filter { $0.value.kind == .finished }
  }

  var waitingEntries: [String: PlaylistReviewEntry] {
    let latestReviews = PlaylistReviewsCodec.latestReviews(in: entries)
    return finishedEntries.filter { id, entry in
      !(latestReviews[id].map { $0.at > entry.at } ?? false)
    }
  }

  var reviews: [String: PlaylistReviewEntry] {
    PlaylistReviewsCodec.latestReviews(in: entries)
  }

  func refresh() async {
    do {
      let result = try await client.read()
      entries = result.entries
      hasUnreadableFiles = result.skippedLines > 0
      errorMessage = nil
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      entries = []
      hasUnreadableFiles = false
      errorMessage = nil
    } catch {
      hasUnreadableFiles = true
      errorMessage = error.localizedDescription
    }
  }

  func finish(_ playlist: PlaylistShelfPlaylist) async {
    await appendJonEntry(.finished, for: playlist)
  }

  func finish(_ playlist: PlaylistShelfPlaylist, progress: PlaylistProgressResult?) async {
    await appendJonEntry(.finished, for: playlist, progress: progress)
  }

  func reopen(_ playlist: PlaylistShelfPlaylist) async {
    await appendJonEntry(.reopened, for: playlist)
  }

  private func appendJonEntry(_ kind: PlaylistReviewKind, for playlist: PlaylistShelfPlaylist,
    progress: PlaylistProgressResult? = nil) async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }
    let device = await client.deviceName()
    let name = playlist.batch.playlist?.trimmingCharacters(in: .whitespacesAndNewlines)
    let songs = progress.map { result in
      playlist.songs.enumerated().map { index, song in
        let status: String
        let keptIn: [String]?
        switch result.songs[song.id] {
        case let .kept(names): status = "kept"; keptIn = names
        case .passed: status = "passed"; keptIn = nil
        case .notHeard, .none: status = "unheard"; keptIn = nil
        }
        return PlaylistReviewSongOutcome(index: index, title: song.title, artist: song.artist,
          status: status, keptIn: keptIn)
      }
    }
    let entry = PlaylistReviewEntry(source: .jon, kind: kind, host: playlist.batch.host,
      recordedAt: playlist.batch.recordedAt, playlistID: playlist.id,
      playlist: name.flatMap { $0.isEmpty ? nil : $0 } ?? "Staged playlist", at: now, device: device,
      heard: progress?.counts.heard, kept: progress?.counts.kept,
      passed: progress.map { $0.counts.passedWithFeedback + $0.counts.passedWithoutFeedback },
      unheard: progress?.counts.notHeard, songs: songs)
    do {
      try await client.append(entry, device)
      entries.append(entry)
      errorMessage = nil
    } catch ProbeBookmarkError.folderNotSelected, ProbeBookmarkError.accessRefused {
      errorMessage = FeedbackNoteSaver.folderGrantMessage
    } catch {
      errorMessage = "The playlist status could not be saved: \(error.localizedDescription)"
    }
  }
}
