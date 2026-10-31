import Foundation
import Testing
@testable import VinylFeverNotes

struct PlaylistTasteNotesTests {
  @Test func playlistNoteUsesTasteNoteV1KeysAndOptionalCatalogID() throws {
    let base = TasteNote(notedAt: Date(timeIntervalSince1970: 1_800_000_000), note: "Bright guitars.",
      source: "playlist", title: "Song", artist: "Artist", album: "Album")
    let withoutCatalog = try JSONSerialization.jsonObject(with: TasteNotesCodec.encode(base)) as? [String: Any]
    #expect(withoutCatalog?["format"] as? String == "vf-taste-note")
    #expect(withoutCatalog?["version"] as? Int == 1)
    #expect(withoutCatalog?["source"] as? String == "playlist")
    #expect(withoutCatalog?["catalogID"] == nil)

    var catalog = base
    catalog.catalogID = "i.song"
    let withCatalog = try JSONSerialization.jsonObject(with: TasteNotesCodec.encode(catalog)) as? [String: Any]
    #expect(withCatalog?["catalogID"] as? String == "i.song")
  }

  @Test func matchesAcrossFilesNewestFirstAndIgnoresTimeOnlyNotes() throws {
    let older = TasteNote(notedAt: Date(timeIntervalSince1970: 10), note: "Older note.", source: "shortcut",
      title: "Café", artist: "Bánd")
    let newer = TasteNote(notedAt: Date(timeIntervalSince1970: 20), note: "Newer note.", source: "playlist",
      title: "Cafe", artist: "Band")
    let timeOnly = TasteNote(notedAt: Date(timeIntervalSince1970: 30), note: "Just a thought.", source: "time-only")
    let files = [try TasteNotesCodec.encode(older) + TasteNotesCodec.encode(timeOnly), try TasteNotesCodec.encode(newer)]
    let notes = TasteNotesCodec.readFiles(files).notes
    let matching = PlaylistTasteNotes.matching(notes, title: "Cafe", artist: "Band")
    #expect(matching.map(\.note) == ["Newer note.", "Older note."])
  }
}
