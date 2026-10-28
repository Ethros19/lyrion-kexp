#!/usr/bin/env bash
# Tiny JSON-RPC helper for the dev server: scripts/lms.sh <player|-> '<json array>'
p=$1; [ "$p" = - ] && p=""
curl -s -m 30 localhost:9000/jsonrpc.js -d "{\"id\":1,\"method\":\"slim.request\",\"params\":[\"$p\",$2]}"
