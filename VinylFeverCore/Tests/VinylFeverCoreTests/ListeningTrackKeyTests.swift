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

  @Test("Taste Intelligence applies artist aliases through the shared key")
  func tasteIntelligenceAppliesAliases() {
    let identity = ArtistIdentity(aliases: ["John Cougar Mellencamp": "John Mellencamp"],
      knownArtists: ["John Mellencamp", "John Cougar Mellencamp"])
    #expect(TasteIntelligence.songKey(artist: "John Cougar Mellencamp", title: "Small Town", identity: identity)
      == TasteIntelligence.songKey(artist: "John Mellencamp", title: "Small Town", identity: identity))
  }

  @Test("Without aliases, Taste Intelligence's key is the mobile key")
  func tasteIntelligenceMatchesMobileKeyWithoutAliases() {
    let identity = ArtistIdentity(knownArtists: ["The Records"])
    #expect(TasteIntelligence.songKey(artist: "The Records", title: "Me & Magdalena", identity: identity)
      == ListeningTrackKey.make(artist: "The Records", title: "Me & Magdalena"))
  }
}
