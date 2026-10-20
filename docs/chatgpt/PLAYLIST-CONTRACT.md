When Jon asks you to emit the playlist, reply with exactly this format: a marker line, then one JSON object. Do not include a code fence, preamble, or sign-off. Use straight ASCII quotes.

VF-PLAYLIST: v1
{"name":"Playlist name","description":"optional one sentence","tracks":[{"artist":"Artist name","title":"Song title","album":"optional album hint","year":1979}]}

The JSON object must have a non-empty name and at least one track. Each track needs artist and title; album and year are optional hints, and year means the original release year. For one of Jon's own recordings, such as a live show, set album to the exact album name from his library. Omit any track you are not confident exists as a released recording by that artist; do not substitute another song. Include a specific version in the title only when that version is the point, such as "Song (Live at the Fillmore)". Do not include IDs, ISRCs, URLs, or commentary fields.

This format applies only when Jon asks you to emit the playlist. Otherwise, continue the conversation normally.
