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
  var setlistInput = ""
  var setlistDraft: SetlistDraft?
  var setlistErrorMessage: String?

  enum Destination: Hashable {
  }

  func scanShowFolder(at url: URL) {
    do {
      scannedShowFolder = try fileSystemClient.scanShowFolder(root: url)
      scanErrorMessage = nil
    } catch {
      scannedShowFolder = nil
      scanErrorMessage = error.localizedDescription
    }
  }

  func loadSetlistText(from url: URL) {
    do {
      setlistInput = try loadTextFile(at: url)
      parseSetlistInput()
      setlistErrorMessage = nil
    } catch {
      setlistErrorMessage = error.localizedDescription
    }
  }

  func parseSetlistInput() {
    setlistDraft = SetlistParser().parse(setlistInput)
    setlistErrorMessage = nil
  }

  private func loadTextFile(at url: URL) throws -> String {
    var detectedEncoding = String.Encoding.utf8
    if let text = try? String(contentsOf: url, usedEncoding: &detectedEncoding) {
      return text
    }

    let data = try Data(contentsOf: url)
    for encoding in fallbackTextEncodings {
      if let text = String(data: data, encoding: encoding) {
        return text
      }
    }

    throw CocoaError(.fileReadInapplicableStringEncoding)
  }

  private var fallbackTextEncodings: [String.Encoding] {
    [
      .utf8,
      .windowsCP1252,
      .macOSRoman,
      .isoLatin1,
    ]
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
