import Foundation
import VinylFeverCore

enum LibraryTestFixtures {
  static func tracks(date: Date) -> [LibraryTrack] {
    (0..<30).map { index in
      let artist = index == 0 ? "Beyoncé" : "Artist \(index % 3)"
      let title = index == 0 ? "Café Song feat. Guest" : "Song \(index)"
      let genre = index.isMultiple(of: 2) ? "Rock" : "Jazz"
      let lastPlayed = index.isMultiple(of: 2) ? date : nil
      let availability: LibraryAvailability = index == 0 ? .uploaded : .subscription
      return LibraryTrack(
        persistentID: "id-\(index)", name: title, artist: artist, albumArtist: artist,
        album: "Album \(index % 4)", genre: genre, year: 1980 + index, playCount: index,
        favorited: index.isMultiple(of: 5),
        dateAdded: date.addingTimeInterval(Double(index) * 60),
        lastPlayed: lastPlayed, availability: availability)
    }
  }
}
