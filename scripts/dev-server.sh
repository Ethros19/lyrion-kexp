#!/usr/bin/env bash
# Run a throwaway Lyrion server in Docker with this plugin mounted live.
# Web UI: http://localhost:9000   (restart the container to reload Perl code)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .dev/config .dev/music
docker rm -f kexp-lms >/dev/null 2>&1 || true
docker run -d --name kexp-lms \
  -p 9000:9000 -p 9090:9090 -p 3483:3483 -p 3483:3483/udp \
  -v "$PWD/.dev/config:/config" \
  -v "$PWD/.dev/music:/music:ro" \
  -v "$PWD/src/KEXP:/config/cache/Plugins/KEXP:ro" \
  -e EXTRA_ARGS="--debug plugin.kexp=INFO" \
  lmscommunity/lyrionmusicserver:latest
echo "Lyrion starting on http://localhost:9000 (logs: docker logs -f kexp-lms)"
