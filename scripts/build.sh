#!/usr/bin/env bash
# Package the plugin as dist/KEXP-<version>.zip (+ sha1) for manual install
# or a custom repo.xml.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' src/KEXP/install.xml)
mkdir -p dist
rm -f "dist/KEXP-$version.zip"
(cd src && zip -qr "../dist/KEXP-$version.zip" KEXP -x '*.DS_Store')
shasum "dist/KEXP-$version.zip" | cut -d' ' -f1 > "dist/KEXP-$version.zip.sha1"
echo "dist/KEXP-$version.zip ($(cat dist/KEXP-$version.zip.sha1))"
