# Music Feedback shortcut

Music Feedback records a song reason from Shortcuts into iCloud Drive. It never changes Apple
Music. It was called VF Note until 2026-10-25, when Siri started hearing that name as a request
to the Notes app. How to use it day to day is in [the feedback guide](../feedback-guide.md).
Run it by name with Siri, from the Action button, or from Control Center. It also works through
CarPlay.

## One-time setup

1. Run `scripts/setup-mac --role chat --apply` on the chat Mac. This creates the empty
   `iCloud Drive/Vinyl Fever/Taste Intelligence/notes.jsonl` file if it is missing. Shortcuts
   cannot reliably create a `.jsonl` file itself.
2. In Shortcuts, create a shortcut named **Music Feedback**.
3. Add **Get Current Song**. If its title is empty, run **Recognize Music** and use that result
   as the song. Recognize Music is the fallback for songs the phone cannot read as the current
   track yet.
4. Ask for the reason with **Dictate Text**.
5. Build a Dictionary with `format` = `vf-taste-note`, `version` = `1`, `notedAt`, `title`,
   `artist`, `album`, `playCount`, `releaseDate`, `duration`, `note`, `source`, and `device`.
   Set `source` to `current-song` or `shazam` to show which identification path found it.
6. Use **Get Text from Input** on the Dictionary, then **Append to Text File** at
   `iCloud Drive/Vinyl Fever/Taste Intelligence/notes.jsonl`, with **Make New Line** enabled.

Shortcuts writes one JSON object per line. The reader accepts UTF-8, a missing final newline,
blank lines, and iCloud conflict copies such as `notes 2.jsonl`. It ignores an incomplete final
line and reports unknown formats or versions in coverage.

When both song-identification actions return no title, a time-only note is still useful. The
chat can use the listening log to suggest songs played within ten minutes; confirm the intended
song before treating the note as song-specific.
