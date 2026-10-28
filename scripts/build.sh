#!/usr/bin/env bash
# Package the plugin as dist/KEXP-<version>.zip (files at zip root, the
# layout LMS repo installs expect) and regenerate repo.xml to point at the
# matching GitHub release asset.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=Ethros19/lyrion-kexp
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' src/KEXP/install.xml)
zip="dist/KEXP-$version.zip"

mkdir -p dist
rm -f "$zip"
(cd src/KEXP && zip -qr "../../$zip" . -x '*.DS_Store')
sha=$(shasum "$zip" | cut -d' ' -f1)

cat > repo.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
	<details>
		<title lang="EN">KEXP</title>
	</details>
	<plugins>
		<plugin name="KEXP" version="$version" minTarget="8.0" maxTarget="*">
			<title lang="EN">KEXP</title>
			<desc lang="EN">Listen to KEXP live, play any show from the last two weeks of the archive, and browse every Live on KEXP session.</desc>
			<creator>Ethan Rosch</creator>
			<category>radio</category>
			<link>https://github.com/$REPO</link>
			<url>https://github.com/$REPO/releases/download/v$version/KEXP-$version.zip</url>
			<sha>$sha</sha>
		</plugin>
	</plugins>
</extensions>
EOF

echo "$zip ($sha)"
