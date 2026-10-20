import Testing
import VinylFeverListening
@testable import VinylFeverCore

@Suite("Listening track key integration")
struct ListeningTrackKeyTests {
  @Test("listening artist keys match the library index key")
  func listeningTrackKeyMatchesLibraryIndexKey() {
    let titles = [
      "Song feat. Guest",
      "Song (featuring Guest)",
      "Song (feat. Guest)",
      "Song (2005 Remaster)",
    ]
    for title in titles {
      let indexKey = "records|\(SongTextNormalizer.libraryTitle(title))"
      #expect("\(ArtistIdentity.empty.key("The Records"))|\(SongTextNormalizer.libraryTitle(title))" == indexKey)
    }
  }
}
