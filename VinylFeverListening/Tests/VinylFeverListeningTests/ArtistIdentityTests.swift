import Testing
import VinylFeverListening

@Suite("Artist identity")
struct ArtistIdentityTests {
  @Test("base keys remove articles, punctuation differences, and band or live suffixes")
  func baseKeys() {
    let equalPairs = [
      ("Bruce Springsteen & The E Street Band (Live)", "Bruce Springsteen"),
      ("Bruce Hornsby and the Range", "Bruce Hornsby Solo"),
      ("Lyle Lovett and His Large Band", "Lyle Lovett"),
      ("The Eagles", "Eagles"),
      ("Cure, The", "The Cure"),
      ("Patrice O'Neal", "Patrice ONeal"),
      ("Kealiʻi Reichel", "Kealii Reichel"),
      ("Elvis Costello & The Attractions", "Elvis Costello"),
      ("Earth, Wind & Fire", "Earth Wind & Fire"),
    ]
    for (lhs, rhs) in equalPairs {
      #expect(ArtistIdentity.baseKey(lhs) == ArtistIdentity.baseKey(rhs))
    }
    #expect(ArtistIdentity.baseKey("Elvis") != ArtistIdentity.baseKey("Elvis Costello"))
    #expect(ArtistIdentity.baseKey("Moby") != ArtistIdentity.baseKey("Moby Grape"))
    #expect(ArtistIdentity.baseKey("Simon & Garfunkel") == "simon and garfunkel")
    #expect(ArtistIdentity.baseKey("The The") == "the")
  }

  @Test("credits recognize known duet partners without splitting band names")
  func credits() {
    let identity = ArtistIdentity(knownArtists: [
      "Paul Simon", "Sting", "Zapp", "Roger", "Love", "Cry", "Men", "Bruce Hornsby", "Band",
    ])
    #expect(identity.credits("Paul Simon & Sting") == ["paul simon and sting", "paul simon", "sting"])
    #expect(identity.credits("Zapp & Roger") == ["zapp and roger", "zapp", "roger"])
    #expect(identity.credits("Love and Rockets") == ["love and rockets"])
    #expect(identity.credits("Hue and Cry") == ["hue and cry"])
    #expect(identity.credits("Of Monsters and Men") == ["of monsters and men"])
    #expect(identity.credits("Bruce Hornsby & Band") == ["bruce hornsby and band", "bruce hornsby"])
  }

  @Test("aliases map one hop to a canonical base key")
  func aliases() {
    let identity = ArtistIdentity(
      aliases: ["John Cougar": "John Mellencamp", "John Mellencamp": "John Mellencamp"],
      knownArtists: ["John Cougar", "John Mellencamp"])
    #expect(identity.key("John Cougar") == "john mellencamp")
  }
}
