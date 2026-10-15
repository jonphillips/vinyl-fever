# Vinyl Fever Chat Project

Set up the Project once so its final playlist replies use Vinyl Fever's pinned format.

1. In Vinyl Fever, open **Settings → Playlist Builder** and choose **Copy ChatGPT Project Instructions**.
2. In ChatGPT, create a Project named **Vinyl Fever Chat**.
3. Open the Project's instructions and paste the copied text. Save the Project.
4. In that Project, discuss and refine a song list normally. When it is ready, ask ChatGPT to **emit the playlist**.
5. Copy the complete reply, including the `VF-PLAYLIST: v1` marker, into Vinyl Fever's **Playlists** area. Resolve and review the matches before creating the playlist.

Smoke test: ask for a short playlist with two well-known songs, then ask the Project to emit it. The final response should contain the marker line and one JSON object, with no code fence or surrounding prose. Paste it into Vinyl Fever and confirm both songs resolve before creating a test playlist. Delete the test playlist by hand in Music.app when finished.
