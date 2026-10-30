# Feedback guide — how to tell Vinyl Fever what you think

*Jon's manual for the listening side of Taste Intelligence: what to do with Apple's New Music
each week, what to do with a playlist the chat made, and when a Music Feedback note is worth
leaving. The design is in [taste-intelligence.md](taste-intelligence.md). How outcomes are
counted is in [M17](milestones/archive/M17-taste-intelligence.md) and
[M18](milestones/M18-taste-outcomes.md). If this guide and those milestones disagree, the
milestones are right, and this guide needs fixing.*

## The short version

- **Keep a song by filing it.** Add it to a `keepers` playlist: the Selections playlist for its
  release year, or Vinyl Fever Keepers. That's the whole keep signal. There's no button to press
  and no note to leave.
- **Pass by doing nothing.** If you play a song and don't file it within 14 days, it's a pass.
  A skip counts as playing it.
- **Leave a Music Feedback note only when you know why.** One sentence about why a song
  missed, or why it surprised you, is worth more than any rating.
- **Open Vinyl Fever on the laptop at least once a week.** That's when it sees what you filed.

## What Vinyl Fever can see

| You do | Vinyl Fever sees it through | It means |
| --- | --- | --- |
| Start a song, even for a few seconds, or let autoplay start it | the listening log (hourly, from Apple's recently played) | heard |
| Add a song to a `keepers` playlist | the library snapshot and the curation log | kept |
| Play a song and not file it within 14 days | the log and the snapshot together | passed |
| Never start a song | nothing | unheard: it counts neither way |
| Leave a Music Feedback note, or tell the chat something | the notes in `Taste Intelligence/` | your reasons, word for word |
| Favorite or Suggest Less | the curation log, for songs in your library only | recorded, but not used for outcomes yet |

Some consequences:
- **A skip is a pass.** If the first ten seconds told you enough, skipping is the right answer.
  You don't need to hear a song you don't like to the end.
- **Starting a song matters.** A song you never start is left out of the comparison, so try to
  at least start every song in a batch.
- **Songs you already knew don't count.** Vinyl Fever works out what was new to you when the
  playlist was staged (owned, heard, in a playlist, noted, or recommended before) and scores
  only those. If it got one wrong (you knew a song from the radio, say), a Music Feedback note
  ("already knew this one") keeps the record straight.
- **Adding and then removing a song between two snapshot refreshes isn't seen.** Don't worry
  about filing something by mistake.

## Apple's New Music, every Friday

Apple replaces the New Music playlist each Friday with 25 songs, almost all from this year.
The poller on the mini saves each week's list, so there's nothing to do to capture it.

1. **Before you listen (once M18 S2 ships):** ask the chat in the ChatGPT Project which of this
   week's songs you'll keep. It records its picks before you hear anything. That's the fair
   test of the chat on new releases (M18 Decision 1). Ask it not to tell you its picks until the
   week is over, so they can't sway you.
2. **Listen within 14 days.** Start every song. Skip anything that doesn't grab you.
3. **Keep:** add the song to the Selections playlist for its release year, which for New Music is
   almost always this year's. Siri works on a first hearing: "add this to my 2026 Selections".
4. **Don't keep:** do nothing. You don't need to dislike it.
5. **Feedback:** optional. Leave a Music Feedback note when:
   - a song nearly made it ("good verse, the chorus is too polished");
   - you notice a pattern ("another big synth chorus, I always skip these");
   - a keep surprised you ("not my usual thing, but the harmonies got me").

   You don't need a note for an ordinary keep or an ordinary skip. The filing and the skip
   already say it.

Keep New Music finds out of Vinyl Fever Keepers. Filing them there wouldn't break anything,
because a song counts by where it was shown to you, not where you file it. But Vinyl Fever
Keepers reads best as the list of the chat's hits.

## A Vinyl Fever playlist from the chat

When you ask the chat for recommendations, it stages a playlist, and you create it in Vinyl
Fever. Vinyl Fever records which songs were new to you at that moment (M18 S1's ledger).

1. **Listen within 14 days.** Start every song, and skip freely.
2. **Keep:** add the song to **Vinyl Fever Keepers**. If it also belongs in the Selections
   playlist for its release year, add it there too. Both count as kept. Selections exist from
   2020 on, so older finds go only in Vinyl Fever Keepers.
3. **Don't keep:** leave it alone. A song you played and didn't file is a pass.
4. **Feedback goes on the misses.** For a song you didn't like, say why in a sentence if you
   know: "too slick", "the vocals grate", "this is the AOR I keep passing on". A keep needs no
   note. Its filing says it. The chat learns most from what separates a pass from a keep.
5. **When you're done, delete the playlist if you like.** Nothing depends on it after staging.
   The ledger has the list, and kept means filed in a `keepers` playlist.
6. **Telling the chat directly works too.** "Note that I passed on X because …" is recorded word
   for word, the same as a Music Feedback note.

## Music Feedback, the shortcut

The shortcut was called VF Note until 2026-10-25. Siri heard "VF Note" as a request to take a
note in the Notes app, so it's now **Music Feedback**. The file and the format are unchanged.
Setup is in [setup/music-feedback.md](setup/music-feedback.md).

- **Run it** by saying "Music Feedback" to Siri (CarPlay included), or from the Action button or
  Control Center. It works with the phone locked.
- **Say one sentence about the song you're hearing.** Lead with the reason: "the guitar tone is
  great, but the song goes nowhere".
- **On Discovery Station,** skip forward and back first. Otherwise the shortcut can't read the
  current song and falls back to Shazam.
- **If it can't identify the song** (a noisy car, say), the note keeps only the time. It's still
  useful: the chat matches it against what you were playing and asks you to confirm.
- **Any time, about anything:** a song, an artist, or a whole playlist ("this playlist is too
  samey"). You can never leave too few.

## The chat's questions (once M18 S4 ships)

The chat may record a question while it builds a list, such as "you kept X but passed Y. Was it
the tempo or the vocals?". At the start of a taste conversation, it asks at most one.

- **Answer in your own words.** It's recorded word for word.
- **"Skip" or "not now" is final.** The question won't come back.
- Questions expire after 21 days, and at most 3 are open at once, so they never pile up.

## Housekeeping

- **Open Vinyl Fever on the laptop at least weekly.** It refreshes the library snapshot at launch
  when the snapshot is more than 6 hours old. Playlists → **Refresh Library Snapshot** forces one.
  Keeps are seen only at a refresh. A pass is final only once a snapshot is newer than the
  song's 14-day window.
- **A new playlist needs a role.** If you make a playlist you choose songs into, label it in
  **Settings → Taste → Playlist Roles…** (`keepers`, `curated`, `situational`, and so on).
  Unlabeled playlists still count as "you know this song", but only `keepers` count as kept.
- **After installing a new Vinyl Fever, refresh the Vinyl Fever tools** in ChatGPT and Codex, or
  start a new thread. Open threads keep the old tool list, and a Codex session can keep running
  an old copy of the connector. Ask the chat which tools it has (or, once M16 S4 ships, which
  connector build) before trusting it with a new feature. There's nothing to copy from
  Settings: the chat gets Vinyl Fever's instructions from the connector.
