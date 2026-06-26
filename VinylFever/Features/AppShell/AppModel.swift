import Dependencies
import Foundation
import Observation
import VinylFeverCore

@MainActor
@Observable
final class AppModel {
  @ObservationIgnored
  @Dependency(\.fileSystemClient) private var fileSystemClient

  var selectedSection: AppSection = .liveShows
  var destination: Destination?
  var scannedShowFolder: ScannedShowFolder?
  var scanErrorMessage: String?

  enum Destination: Hashable {
  }

  func scanShowFolder(at url: URL) {
    do {
      scannedShowFolder = try fileSystemClient.scanShowFolder(at: url)
      scanErrorMessage = nil
    } catch {
      scannedShowFolder = nil
      scanErrorMessage = error.localizedDescription
    }
  }
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
  case liveShows
  case collections

  var id: Self { self }

  var title: String {
    switch self {
    case .liveShows:
      "Live Shows"
    case .collections:
      "Collections"
    }
  }

  var systemImage: String {
    switch self {
    case .liveShows:
      "music.note.list"
    case .collections:
      "rectangle.stack"
    }
  }
}
