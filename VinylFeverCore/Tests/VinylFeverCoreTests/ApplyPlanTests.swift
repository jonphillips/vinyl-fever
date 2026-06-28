import CustomDump
import Foundation
import Testing
@testable import VinylFeverCore

@Suite
struct ApplyPlanTests {
  @Test
  func buildsOrderedCopyAndTagOperationsIntoWorking() {
    let showPlan = makeShowPlan(
      files: [
        makeAudioFile(id: UUID(1), name: "b.flac", format: .flac, sortKey: "02.flac"),
        makeAudioFile(id: UUID(2), name: "a.flac", format: .flac, sortKey: "01.flac"),
      ],
      trackTitles: [
        "Mandolin Rain / Brokedown Palace: radio intro",
        "The Way It Is",
      ]
    )
    let coverURL = applyShowRoot.appendingPathComponent("front.jpg")
    let applyPlan = ApplyPlan(showPlan: showPlan, showRoot: applyShowRoot, coverURL: coverURL)

    expectNoDifference(
      applyPlan.operations.map(ApplyOperationSnapshot.init(operation:)),
      [
        .copy(
          source: "/Shows/BruceHornsby/a.flac",
          destination: "/Shows/BruceHornsby/Working/01 - Mandolin Rain - Brokedown Palace - radio intro.flac"
        ),
        .writeTags(
          file: "/Shows/BruceHornsby/Working/01 - Mandolin Rain - Brokedown Palace - radio intro.flac",
          format: .flac,
          title: "Mandolin Rain / Brokedown Palace: radio intro",
          trackNumber: 1,
          trackTotal: 2,
          cover: "/Shows/BruceHornsby/front.jpg"
        ),
        .copy(
          source: "/Shows/BruceHornsby/b.flac",
          destination: "/Shows/BruceHornsby/Working/02 - The Way It Is.flac"
        ),
        .writeTags(
          file: "/Shows/BruceHornsby/Working/02 - The Way It Is.flac",
          format: .flac,
          title: "The Way It Is",
          trackNumber: 2,
          trackTotal: 2,
          cover: "/Shows/BruceHornsby/front.jpg"
        ),
      ]
    )
    expectNoDifference(applyPlan.requiredTools, [.metaflac])
  }
}
