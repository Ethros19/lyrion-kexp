# KEXP for Lyrion

Lyrion Music Server (LMS) plugin: KEXP live stream + the two-week show archive.

## Layout
- `src/KEXP/` — the plugin itself (installs as `Plugins/KEXP/`, package prefix `Plugins::KEXP::`)
  - `Plugin.pm` — OPML menus (Live, Recent Shows by day, Programs, per-show tracklist)
  - `ProtocolHandler.pm` — `kexp://show/<id>[/<secondsIntoShow>]` and `kexp://program/<id>/latest` → archive MP3. Pre-roll hidden: track secs/duration = show length, `getSeekData` adds `fileOffset` to every seek and reports show-relative `timeOffset`. Dynamic now-playing via `getMetadataFor`
  - `Live.pm` — live-stream now-playing (RemoteMetadata provider on the streamguys live URLs), polls plays/shows every 30 s only while a player is on live
  - `API.pm` — async api.kexp.org client + caching
  - `LiveOnKEXP.pm` — Live on KEXP podcast (Omny RSS, ~1,300 eps), cached 6 h; RemoteMetadata provider for now-playing
  - `Settings.pm` + `HTML/EN/plugins/KEXP/settings/basic.html` — read-only about page (version, Donate link)
  - `Util.pm` — pure time/format/RSS helpers (unit tested)
- `tests/` — `prove tests/` (only Util is testable outside LMS); `KEXP_FEED=<saved podcast.rss> prove tests/` also checks the real feed
- `scripts/dev-server.sh` — Docker LMS on :9000 with the plugin mounted read-only; `docker restart kexp-lms` to reload code
- `scripts/test-player.sh` — headless squeezelite in Docker (plays faster than real time); `scripts/lms.sh` — JSON-RPC helper
- `scripts/build.sh` — zip to `dist/`
- `scripts/installs.sh` — install counts (Lyrion community stats + GitHub release downloads)
- `scripts/smoke.py` — checks the KEXP services behave as the plugin assumes (run weekly in CI; locally on python.org Python use `SSL_CERT_FILE=/etc/ssl/cert.pem`)

## Gotchas
- Material icon: the PNG is named `kexp-logo_svg.png` so Material swaps in `kexp-logo.svg` (same dir, 24×24, all fills/strokes `#000`, ≥2 px margin) and recolours it per theme. Other skins use the PNG. See github.com/CDrummond/lms-material/wiki/10-Icons.
- Icon style pref `iconStyle` (`auto`|`orange`): `Plugin::_pluginDataFor` returns `kexp-logo-orange.png` (same PNG, name Material won't remap) only when `orange` AND `menuLocation` is `apps` — Material forces Radio top-level icons to monochrome (`mapIcon` fallback `radio-station` in browse-resp.js), so in Radio the `_svg` mapping is the better result.
- Menu location (`plugin.kexp` pref `menuLocation`: `radio`|`apps`) is read once at startup (OPMLBased `is_app`); changing it needs an LMS restart, which the settings page says.
- Session setlists (`parseSessionNotes`) come from free-form episode notes in four historical formats: `<ol>/<ul>` lists (2020+), a "Songs: A / B" line, a `<br>` paragraph between intro and credits, and inline "4 songs: A, B" (2014–19). Coverage ~96%; `KEXP_FEED=… prove tests/` asserts >90%. Some notes are truncated ("Cath...") in KEXP's own feed.
- Genres come from program `tags` via `genresForTags` (generic Rock/Eclectic dropped, neighbours merged, unknown tags pass through). Live on KEXP has no genre data.
- Bump the `kexp:liveonkexp:vN` cache key when the parsed episode shape changes.
- LMS/browsers cache resized icons by path: when changing an image, give it a new filename (e.g. `kexp-logo.png`), don't overwrite.
- In CLI list mode LMS drops `weblink` entirely; LyrionJS ≥ 0.2.33 works around it by re-fetching in menu mode.
- Live on KEXP enclosures redirect traffic.omny.fm → kexp-podcast.streamguys1.com; the queued track keeps the redirected URL, so metadata is matched by Omny clip id, not host.
- The feed is ~5 MB; parse with regex (`parseRssItems`), not XML::Simple, to avoid blocking the server.
- `/v2/plays/` always returns a `next` link, even past the end — `_getAll` stops on short pages.
- Most CLI menu queries hang without a connected player; start the test player.
- Plain-HTTP egress from containers returns 500 on this machine; HTTPS works.

## LyrionJS compatibility (verified v0.2.31 and v0.2.33, Oct 2026)
- LyrionJS sets `mp3StreamingMethod: 1` (proxied) on its players (MAC `02:4c:4a:…`), so the browser only fetches from LMS — no CORS concerns for the CDNs. Keep handlers proxy-friendly (seekdata/Range on the server side).
- Its own UI browses via `<cmd> items … want_url:1` (not menu mode): it uses `name` + `line2` and only offers play/add menus on `isaudio` items. Since 0.2.33 it re-asks in menu mode for text items' `weblink` (our issue #16), so Donate works; before that, text items were inert.
- To retest: unzip its release into `.dev/config/cache/Plugins/LyrionJS/`, start the dev server, open http://localhost:9000/plugins/LyrionJS/ (Playwright works; plays in real time).

## KEXP archive facts (verified Oct 2026)
- `GET https://api.kexp.org/get_streaming_url/?timestamp=<ISO UTC>` → `{sg-url, sg-url-next, sg-offset}`
- One static MP3 per show on `kexp-archive.streamguys1.com`, spanning show start − 10 min → show end. 128 kbps CBR, byte-range seekable, downloads far faster than real time. `bitrate` param is ignored.
- Archive depth is exactly 14 days by timestamp (`get_streaming_url` returns nothing at 336 h). Menus hide shows within 30 min of expiry (`API::isArchived`).
- `/v2/shows/` has no program filter (params ignored) — fetch the whole window (`limit=500`) and group client-side.
- `/v2/plays/?show_ids=<id>` works; `play_type` is `trackplay` or `airbreak`.
- Times carry the station's Pacific offset; menus display station wall-clock time.

## No secrets
The KEXP API is public and unauthenticated; there is no `.env`.
