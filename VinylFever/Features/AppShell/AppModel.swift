import Dependencies
import Foundation
import Observation
import SQLiteData
import VinylFeverCore

@MainActor
@Observable
final class AppModel {
  @ObservationIgnored
  @Dependency(\.fileSystemClient) private var fileSystemClient
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid

  var selectedSection: AppSection = .liveShows
  var destination: Destination?
  var scannedShowFolder: ScannedShowFolder?
  var scanErrorMessage: String?
  var setlistInput = ""
  var setlistDraft: SetlistDraft?
  var setlistErrorMessage: String?
  var selectedSourceLabelID: SourceLabel.ID?
  var newSourceLabelToken = ""
  var sourceLabelErrorMessage: String?

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

  func addSourceLabel() {
    let token = SourceLabel.normalizedToken(newSourceLabelToken)
    guard !token.isEmpty else {
      sourceLabelErrorMessage = "Enter a source label."
      return
    }

    do {
      let existingSourceLabels = try database.read { db in
        try SourceLabel.order(by: \.token).fetchAll(db)
      }
      guard !existingSourceLabels.contains(where: { $0.normalizedTokenKey == token.lowercased() })
      else {
        sourceLabelErrorMessage = "That source label already exists."
        return
      }

      let sourceLabel = SourceLabel(id: uuid(), token: token, isBuiltIn: false)
      try database.write { db in
        try SourceLabel.upsert { sourceLabel }.execute(db)
      }
      selectedSourceLabelID = sourceLabel.id
      newSourceLabelToken = ""
      sourceLabelErrorMessage = nil
    } catch {
      sourceLabelErrorMessage = error.localizedDescription
    }
  }

  func deleteSourceLabel(_ sourceLabel: SourceLabel) {
    guard !sourceLabel.isBuiltIn else {
      sourceLabelErrorMessage = "Built-in source labels cannot be removed."
      return
    }

    do {
      try database.write { db in
        try SourceLabel.find(sourceLabel.id).delete().execute(db)
      }
      if selectedSourceLabelID == sourceLabel.id {
        selectedSourceLabelID = nil
      }
      sourceLabelErrorMessage = nil
    } catch {
      sourceLabelErrorMessage = error.localizedDescription
    }
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
