#!/usr/bin/env bash
# How many people use our plugins, and has the official Mixcloud plugin
# picked up our fix yet?
#  1. Lyrion community stats: servers (opted into anonymous stats) with the
#     plugin installed, last 30 days. Undercounts: stats are opt-in.
#  2. GitHub release downloads: every install AND every update downloads the
#     zip, so this runs higher than the number of people.
#  3. Upstream watch: danielvijge/lms_mixcloud PR #51 (login on LMS < 9.2),
#     issue #46, and whether the latest official release contains the fix.
# Set GH_TOKEN to avoid GitHub's anonymous rate limit (60 requests/hour).
set -euo pipefail

# python.org Python on macOS has no CA bundle of its own
if [ -z "${SSL_CERT_FILE:-}" ] && [ -f /etc/ssl/cert.pem ]; then export SSL_CERT_FILE=/etc/ssl/cert.pem; fi

DAYS=${DAYS:-30}
STATS=$(curl -fsS -m 30 "https://stats.lms-community.org/api/stats/plugins?days=$DAYS")

STATS=$STATS DAYS=$DAYS python3 - <<'PY'
import json, os, urllib.request, urllib.error

def gh(path, raw=False):
    url = path if path.startswith("https://") else "https://api.github.com/" + path
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "installs.sh"})
    if os.environ.get("GH_TOKEN") and "api.github.com" in url:
        req.add_header("Authorization", "Bearer " + os.environ["GH_TOKEN"])
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode()
            return body if raw else json.loads(body)
    except urllib.error.HTTPError as e:
        return None if e.code == 404 else {"_error": f"HTTP {e.code}"}
    except urllib.error.URLError as e:
        return {"_error": str(e.reason)}

stats = {k: v for d in json.loads(os.environ["STATS"]) for k, v in d.items()}
print(f"Lyrion community stats (servers, last {os.environ['DAYS']} days):")
for name, note in (("KEXP", ""), ("MixcloudDirect", "Mixcloud Direct (ours)"),
                   ("MixCloud", "official Mixcloud plugin"),
                   ("YouTubeDirect", "YouTube Direct (ours)"), ("YouTube", "philippe44's YouTube plugin"), ("LyrionJS", ""), ("WFMU", ""), ("SomaFM", "")):
    print(f"  {name:<15} {stats.get(name, 0):>5}  {note}")
print(f"  ({len(stats)} plugins tracked)")

for repo in ("Ethros19/lyrion-kexp", "Ethros19/lyrion-mixcloud", "Ethros19/lyrion-youtube"):
    print(f"\nGitHub release downloads, {repo} (installs + updates):")
    releases = gh(f"repos/{repo}/releases?per_page=100") or []
    if isinstance(releases, dict):
        print(f"  unavailable ({releases.get('_error')})")
        continue
    total = 0
    for r in releases:
        n = sum(a["download_count"] for a in r["assets"])
        total += n
        print(f"  {r['tag_name']:<8} {n}")
    print(f"  total    {total}")

# -- upstream watch --------------------------------------------------------
UP = "danielvijge/lms_mixcloud"
print(f"\nOfficial Mixcloud plugin ({UP}):")

pr = gh(f"repos/{UP}/pulls/51") or {}
if "_error" in pr or not pr:
    print(f"  PR #51: unavailable ({pr.get('_error', 'not found')})")
else:
    state = "MERGED" if pr.get("merged") else pr["state"].upper()
    when = (pr.get("merged_at") or pr.get("closed_at") or pr.get("updated_at") or "")[:10]
    print(f"  PR #51 (login on LMS < 9.2): {state}  ({when}, {pr.get('comments', 0)} comments, "
          f"{pr.get('review_comments', 0)} review comments)  {pr['html_url']}")

issue = gh(f"repos/{UP}/issues/46") or {}
if issue and "_error" not in issue:
    print(f"  Issue #46 (auth on older LMS): {issue['state'].upper()}")

release = gh(f"repos/{UP}/releases/latest") or {}
tag = release.get("tag_name")
if not tag:
    print("  Latest release: unavailable")
else:
    print(f"  Latest release: {tag} ({release.get('published_at', '')[:10]})")

    # Does that release contain the fix? Exact answer if the PR was merged
    # (is the merge commit an ancestor of the tag?); otherwise look for a
    # fix of his own in the release's Plugin.pm.
    verdict = None
    if pr.get("merged") and pr.get("merge_commit_sha"):
        cmp = gh(f"repos/{UP}/compare/{pr['merge_commit_sha']}...{tag}") or {}
        if cmp.get("status") in ("ahead", "identical"):
            verdict = "YES: the release includes PR #51"
        elif cmp.get("status"):
            verdict = "not yet: PR #51 is merged but not in a release yet"
    if verdict is None:
        src = gh(f"https://raw.githubusercontent.com/{UP}/{tag}/Plugin.pm", raw=True) or ""
        if not isinstance(src, str) or not src:
            verdict = "unknown (couldn't read Plugin.pm)"
        elif "Async::HTTP" in src or "is required for the Mixcloud plugin to work correctly" not in src:
            verdict = "LIKELY: the release changed its login code (check the changelog)"
        else:
            verdict = "no: the release still has the LMS 9.2 login warning"
    print(f"  Login fix in latest release: {verdict}")

    # Our PR #51 test build is 0.13.0.51; a server running it updates itself
    # to any official release with a higher version.
    def ver(v):
        return [int(x) for x in v.split(".") if x.isdigit()]
    if ver(tag) > ver("0.13.0.51"):
        print(f"  → {tag} is newer than our test build (0.13.0.51): servers running it")
        print("    switch to it at the next restart if automatic plugin updates are on.")

master = gh(f"repos/{UP}/commits?per_page=1") or []
if isinstance(master, list) and master:
    c = master[0]
    print(f"  Last commit on master: {c['commit']['author']['date'][:10]} {c['commit']['message'].splitlines()[0]}")
PY
