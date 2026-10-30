import Foundation

public enum PlaylistTasteNotes {
  public static func matching(_ notes: [TasteNote], title: String, artist: String) -> [TasteNote] {
    let song = FeedbackSong(title: title, artist: artist)
    return notes.filter { note in
      guard !note.isTimeOnly else { return false }
      if let noteTitle = note.title, let noteArtist = note.artist,
        MusicFeedback.matches(song, FeedbackSong(title: noteTitle, artist: noteArtist)) {
        return true
      }
      return note.about?.songs.contains {
        MusicFeedback.matches(song, FeedbackSong(title: $0.title, artist: $0.artist))
      } ?? false
    }
    .sorted { $0.notedAt > $1.notedAt }
  }
}
