#!/usr/bin/env python3
"""Smoke test the KEXP services the plugin depends on (stdlib only).

The archive endpoints are undocumented, so this checks the behaviour the
plugin relies on, not just that URLs answer. Exits non-zero on any failure;
run weekly by .github/workflows/checks.yml.
"""
import json
import re
import sys
import urllib.request
from datetime import datetime, timedelta, timezone

API = "https://api.kexp.org"
FEED = ("https://www.omnycontent.com/d/playlist/bad5d079-8dcb-4630-8770-aa090049131d/"
        "18f3a48e-1c64-43e8-96e9-aa40002038ee/856f4314-821f-46ca-bc8e-aa40002038f2/podcast.rss")
LIVE = "https://kexp.streamguys1.com/kexp160.aac"
UA = {"User-Agent": "lyrion-kexp-smoke/1 (+https://github.com/Ethros19/lyrion-kexp)"}

failures = []


def get(url, headers=None, limit=None):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, r.headers, (r.read(limit) if limit else r.read())


def check(name):
    def wrap(fn):
        try:
            detail = fn()
            print(f"ok    {name}" + (f" ({detail})" if detail else ""))
        except Exception as e:  # noqa: BLE001 - report everything
            failures.append(name)
            print(f"FAIL  {name}: {e}")
        return fn
    return wrap


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


state = {}


@check("shows API lists the last two weeks")
def _():
    after = iso(datetime.now(timezone.utc) - timedelta(days=14))
    _, _, body = get(f"{API}/v2/shows/?format=json&limit=500&start_time_after={after}")
    shows = json.loads(body)["results"]
    assert len(shows) > 50, f"only {len(shows)} shows"
    for key in ("id", "start_time", "program_name", "program", "program_tags", "host_names"):
        assert key in shows[0], f"show is missing '{key}'"
    # a show from ~2 days ago that has certainly finished
    target = datetime.now(timezone.utc) - timedelta(days=2)
    show = min(shows, key=lambda s: abs(datetime.fromisoformat(s["start_time"]).astimezone(timezone.utc) - target))
    state["show"] = show
    return f"{len(shows)} shows"


@check("get_streaming_url resolves a show to an archive file")
def _():
    show = state["show"]
    start = datetime.fromisoformat(show["start_time"]).astimezone(timezone.utc)
    _, _, body = get(f"{API}/get_streaming_url/?bitrate=128&timestamp={iso(start + timedelta(seconds=30))}")
    data = json.loads(body)
    assert data.get("sg-url", "").endswith(".mp3") or ".mp3?" in data.get("sg-url", ""), f"unexpected sg-url: {data}"
    assert isinstance(data.get("sg-offset"), int), f"sg-offset not an int: {data}"
    # the plugin assumes ~10 min of pre-roll before the show
    assert 300 <= data["sg-offset"] <= 1200, f"sg-offset {data['sg-offset']}s outside the expected pre-roll"
    state["file"] = data["sg-url"]
    return f"offset {data['sg-offset']}s"


@check("archive file is a seekable MP3")
def _():
    status, headers, body = get(state["file"], {"Range": "bytes=1000000-1000999"})
    assert status == 206, f"range request returned {status}"
    assert "audio/mpeg" in headers.get("Content-Type", ""), headers.get("Content-Type")
    assert len(body) == 1000, f"got {len(body)} bytes"


@check("archive is ~14 days deep")
def _():
    def has(days):
        ts = iso(datetime.now(timezone.utc) - timedelta(days=days))
        return bool(json.loads(get(f"{API}/get_streaming_url/?timestamp={ts}")[2]).get("sg-url"))
    assert has(13.5), "nothing 13.5 days back"
    assert not has(14.2), "archive is now deeper than 14 days (update ARCHIVE_DAYS?)"


@check("plays API filters by show")
def _():
    sid = state["show"]["id"]
    _, _, body = get(f"{API}/v2/plays/?format=json&limit=500&ordering=airdate&show_ids={sid}")
    plays = json.loads(body)["results"]
    assert plays, "no plays"
    assert all(p.get("show") == sid for p in plays), "show_ids filter ignored"
    assert {p.get("play_type") for p in plays} <= {"trackplay", "airbreak"}, "new play_type values"
    return f"{len(plays)} plays"


@check("now playing (latest play + current show)")
def _():
    play = json.loads(get(f"{API}/v2/plays/?format=json&limit=1")[2])["results"][0]
    show = json.loads(get(f"{API}/v2/shows/?format=json&limit=1")[2])["results"][0]
    assert play.get("airdate") and show.get("start_time")


@check("Live on KEXP feed")
def _():
    _, _, body = get(FEED)
    xml = body.decode("utf-8")
    items = re.findall(r"<item>(.*?)</item>", xml, re.S)
    assert len(items) > 1000, f"only {len(items)} episodes"
    assert all("<enclosure" in i for i in items[:20]), "recent episodes without audio"
    url = re.search(r'<enclosure[^>]*\burl="([^"]+)"', items[0]).group(1).replace("&amp;", "&")
    status, headers, _ = get(url, {"Range": "bytes=0-999"})
    assert status in (200, 206) and "audio" in headers.get("Content-Type", ""), f"{status} {headers.get('Content-Type')}"
    return f"{len(items)} episodes"


@check("live stream")
def _():
    status, headers, body = get(LIVE, limit=4096)
    assert status == 200 and "aac" in headers.get("Content-Type", ""), f"{status} {headers.get('Content-Type')}"
    assert len(body) == 4096


if failures:
    print(f"\n{len(failures)} check(s) failed")
    sys.exit(1)
print("\nall checks passed")
