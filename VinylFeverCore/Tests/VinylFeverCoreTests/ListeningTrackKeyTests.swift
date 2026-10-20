import Testing
import VinylFeverListening
@testable import VinylFeverCore

@Suite("Listening track key integration")
struct ListeningTrackKeyTests {
  @Test("listening track keys match the library index key")
  func listeningTrackKeyMatchesLibraryIndexKey() {
    let titles = [
      "Song feat. Guest",
      "Song (featuring Guest)",
      "Song (feat. Guest)",
      "Song (2005 Remaster)",
    ]
    for title in titles {
      let indexKey = "\(SongTextNormalizer.artist("The Records"))|\(SongTextNormalizer.libraryTitle(title))"
      #expect(ListeningTextNormalizer.trackKey(artist: "The Records", title: title) == indexKey)
    }
  }
}
