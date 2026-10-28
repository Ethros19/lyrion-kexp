#!/usr/bin/env bash
# How many people use the plugin?
#  1. Lyrion community stats: servers (opted into anonymous stats) with the
#     plugin installed, last 30 days. Undercounts: stats are opt-in.
#  2. GitHub release downloads: every install AND every update downloads the
#     zip, so this runs higher than the number of people.
set -euo pipefail

DAYS=${DAYS:-30}
STATS=$(curl -fsS -m 30 "https://stats.lms-community.org/api/stats/plugins?days=$DAYS")
RELEASES=$(curl -fsS -m 30 https://api.github.com/repos/Ethros19/lyrion-kexp/releases)

STATS=$STATS RELEASES=$RELEASES DAYS=$DAYS python3 - <<'PY'
import json, os

stats = {k: v for d in json.loads(os.environ["STATS"]) for k, v in d.items()}
print(f"Lyrion community stats (servers, last {os.environ['DAYS']} days):")
for name in ("KEXP", "LyrionJS", "WFMU", "SomaFM"):
    print(f"  {name:<10} {stats.get(name, 0)}")
print(f"  ({len(stats)} plugins tracked)")

print("\nGitHub release downloads (installs + updates):")
total = 0
for r in json.loads(os.environ["RELEASES"]):
    n = sum(a["download_count"] for a in r["assets"])
    total += n
    print(f"  {r['tag_name']:<8} {n}")
print(f"  total    {total}")
PY
