#!/usr/bin/env bash
# Cut a release: build zip + repo.xml, commit, tag, push, and upload the zip
# to a GitHub release. Bump <version> in src/KEXP/install.xml first — LMS
# only offers an update when the version in repo.xml increases.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=Ethros19/lyrion-kexp
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' src/KEXP/install.xml)

if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
	echo "v$version already released; bump <version> in src/KEXP/install.xml" >&2
	exit 1
fi

prove tests/
./scripts/build.sh

# Push as Ethros19 without changing the active gh account
token=$(gh auth token --user Ethros19)
export GH_TOKEN=$token
cred='!f() { echo username=Ethros19; echo "password=$GH_TOKEN"; }; f'

git add repo.xml
git diff --cached --quiet || git commit -q -m "Release v$version"
git tag "v$version"
git -c credential.helper= -c credential.helper="$cred" push -q origin HEAD "v$version"

gh release create "v$version" "dist/KEXP-$version.zip" --repo "$REPO" \
	--title "v$version" --notes "KEXP for Lyrion v$version"

echo "Released v$version. Repo URL for Lyrion:"
echo "  https://raw.githubusercontent.com/$REPO/main/repo.xml"
