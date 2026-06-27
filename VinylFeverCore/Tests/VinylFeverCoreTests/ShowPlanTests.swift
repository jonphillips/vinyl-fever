import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite struct ShowPlanTests {
  @Test
  func mapsSortedFilesToTracksAndProposedTags() {
    let plan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: [
          audioFile(id: UUID(2), name: "02.flac", sortKey: "02.flac"),
          audioFile(id: UUID(1), name: "01.flac", sortKey: "01.flac"),
        ],
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(
        tags: showTags,
        tracks: [
          SetlistTrack(id: UUID(101), title: "The Way It Is"),
          SetlistTrack(id: UUID(102), title: "Mandolin Rain"),
        ]
      ),
      metadata: showMetadata
    )

    expectNoDifference(plan.isReadyToImport, true)
    expectNoDifference(plan.issues, [])
    expectNoDifference(
      plan.tracks.map { trackPlan in
        TrackPlanSnapshot(
          fileName: trackPlan.sourceFile.url.lastPathComponent,
          proposedFilename: trackPlan.proposedFilename,
          title: trackPlan.proposedTags.title,
          album: trackPlan.proposedTags.album,
          sortAlbum: trackPlan.proposedTags.sortAlbum,
          artist: trackPlan.proposedTags.artist,
          albumArtist: trackPlan.proposedTags.albumArtist,
          trackNumber: trackPlan.proposedTags.trackNumber,
          discNumber: trackPlan.proposedTags.discNumber
        )
      },
      [
        TrackPlanSnapshot(
          fileName: "01.flac",
          proposedFilename: "01 - The Way It Is.flac",
          title: "The Way It Is",
          album: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
          sortAlbum: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
          artist: "Bruce Hornsby and The Range",
          albumArtist: "Bruce Hornsby",
          trackNumber: 1,
          discNumber: 1
        ),
        TrackPlanSnapshot(
          fileName: "02.flac",
          proposedFilename: "02 - Mandolin Rain.flac",
          title: "Mandolin Rain",
          album: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
          sortAlbum: "1996-05-21: Northampton, MA - Pearl Street Grill (SBD)",
          artist: "Bruce Hornsby and The Range",
          albumArtist: "Bruce Hornsby",
          trackNumber: 2,
          discNumber: 1
        ),
      ]
    )
  }

  @Test
  func reportsCountMismatchAsBlockingIssue() {
    let plan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: [audioFile(id: UUID(1), name: "01.flac", sortKey: "01.flac")],
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(
        tags: showTags,
        tracks: [
          SetlistTrack(id: UUID(101), title: "The Way It Is"),
          SetlistTrack(id: UUID(102), title: "Mandolin Rain"),
        ]
      ),
      metadata: showMetadata
    )

    expectNoDifference(plan.issues, [.fileCountMismatch(files: 1, tracks: 2)])
    expectNoDifference(plan.isReadyToImport, false)
    expectNoDifference(plan.tracks.map(\.proposedFilename), ["01 - The Way It Is.flac"])
  }

  @Test
  func reportsNoAudioEmptySetlistAndMissingTitles() {
    let emptyPlan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: [],
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(tags: showTags, tracks: []),
      metadata: showMetadata
    )

    expectNoDifference(emptyPlan.issues, [.noAudioFiles, .emptySetlist])
    expectNoDifference(emptyPlan.isReadyToImport, false)

    let missingTitlePlan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: [audioFile(id: UUID(1), name: "01.flac", sortKey: "01.flac")],
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(
        tags: showTags,
        tracks: [SetlistTrack(id: UUID(101), title: "  ")]
      ),
      metadata: showMetadata
    )

    expectNoDifference(missingTitlePlan.issues, [.missingTitle(trackIndex: 1)])
    expectNoDifference(missingTitlePlan.isReadyToImport, false)
  }

  @Test
  func sanitizesFilenameOnlyAndPreservesTitleTag() {
    let title = "Mandolin Rain / Brokedown Palace: radio intro"
    let plan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: [audioFile(id: UUID(1), name: "01.flac", sortKey: "01.flac")],
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(
        tags: showTags,
        tracks: [SetlistTrack(id: UUID(101), title: title)]
      ),
      metadata: showMetadata
    )

    expectNoDifference(
      plan.tracks[0].proposedFilename,
      "01 - Mandolin Rain - Brokedown Palace - radio intro.flac"
    )
    expectNoDifference(plan.tracks[0].proposedTags.title, title)
  }

  @Test
  func widensFilenamePaddingAtOneHundredTracks() {
    let files = (1...100).map { index in
      audioFile(
        id: UUID(index),
        name: "\(index).flac",
        sortKey: String(format: "%03d.flac", index)
      )
    }
    let tracks = (1...100).map { index in
      SetlistTrack(id: UUID(index + 100), title: "Track \(index)")
    }

    let plan = ShowPlan(
      folder: ScannedShowFolder(
        root: showRoot,
        audioFiles: files,
        setlistCandidates: [],
        coverCandidates: []
      ),
      setlist: SetlistDraft(tags: showTags, tracks: tracks),
      metadata: showMetadata
    )

    expectNoDifference(plan.tracks.first?.proposedFilename, "001 - Track 1.flac")
    expectNoDifference(plan.tracks.last?.proposedFilename, "100 - Track 100.flac")
  }
}

private let showRoot = URL(fileURLWithPath: "/Shows/BruceHornsby")

private let showTags = ShowTags(
  artist: .value("Bruce Hornsby and The Range"),
  albumArtist: .value("Bruce Hornsby"),
  date: .iso(year: 1996, month: 5, day: 21),
  venue: .value("Pearl Street Grill"),
  location: .value("Northampton, MA")
)

private let showMetadata = ShowMetadata(
  tags: showTags,
  source: SourceLabel(id: SourceLabel.builtIns[0].id, token: "SBD", isBuiltIn: true)
)

private func audioFile(id: UUID, name: String, sortKey: String) -> ScannedAudioFile {
  ScannedAudioFile(
    id: id,
    url: showRoot.appendingPathComponent(name),
    format: .flac,
    sortKey: sortKey
  )
}

private struct TrackPlanSnapshot: Equatable {
  var fileName: String
  var proposedFilename: String
  var title: String
  var album: String
  var sortAlbum: String
  var artist: String
  var albumArtist: String
  var trackNumber: Int
  var discNumber: Int
}
