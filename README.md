# KEXP for Lyrion

A [Lyrion Music Server](https://lyrion.org) plugin for [KEXP](https://kexp.org): the live stream, plus every show from the last two weeks of the archive.

- **Listen Live** — the 160 kbps AAC stream
- **Recent Shows** — browse by day (station time, Pacific)
- **Programs** — browse by program (Audioasis, Wo' Pop, Expansions, …)
- Each show opens to its tracklist. Play the whole show, or jump straight in at any song.
- While an archived show plays, now-playing shows the song that was on air at that moment (title, artist, album art), pulled from KEXP's playlist data.
- Seeking works: archive shows are plain seekable MP3s.

## Install

**From a zip:** `./scripts/build.sh`, then unzip `dist/KEXP-*.zip` into your LMS `Plugins` folder
(e.g. `<cachedir>/InstalledPlugins/Plugins/` or, on Docker images, `/config/cache/Plugins/`) and restart LMS.
Enable it under *Settings → Manage Plugins* if needed. It shows up under **Radio** / **My Apps**.

## Develop

```sh
./scripts/dev-server.sh          # LMS on http://localhost:9000 with the plugin mounted
docker restart kexp-lms          # reload after editing Perl
docker logs -f kexp-lms          # plugin logs at INFO
./scripts/test-player.sh         # headless player for CLI testing
./scripts/lms.sh 00:11:22:33:44:55 '["kexp","items",0,10]'   # browse via JSON-RPC
prove tests/                     # unit tests for the pure helpers
```

See `CLAUDE.md` for notes on how the KEXP archive API behaves.
