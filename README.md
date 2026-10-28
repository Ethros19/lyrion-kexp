# KEXP for Lyrion

A [Lyrion Music Server](https://lyrion.org) plugin for [KEXP](https://kexp.org): the live stream, plus every show from the last two weeks of the archive.

- **Listen Live** — the 160 kbps AAC stream
- **Recent Shows** — browse by day (station time, Pacific)
- **Programs** — browse by program (Audioasis, Wo' Pop, Expansions, …)
- Each show opens to its tracklist. Play the whole show, or jump straight in at any song.
- While an archived show plays, now-playing shows the song that was on air at that moment (title, artist, album art), pulled from KEXP's playlist data.
- Seeking works: archive shows are plain seekable MP3s.

## Install

In Lyrion: *Settings → Manage Plugins*, scroll to the bottom, and add this repository URL:

```
https://raw.githubusercontent.com/Ethros19/lyrion-kexp/main/repo.xml
```

Save, find **KEXP** in the plugin list, tick it, apply, and restart when prompted. It shows up under **Radio** / **My Apps**.
Updates appear in the same place after a new release.

## Release

Bump `<version>` in `src/KEXP/install.xml`, commit, then `./scripts/release.sh`
(builds the zip, regenerates `repo.xml`, tags, pushes, and creates the GitHub release).

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
