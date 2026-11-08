#!/usr/bin/env bash
# Host regression test for the OHOS rocksdb bridge: default/CF isolation,
# batch, iteration order, seek, delete, and persistence round-trip.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
BIN=$TMP/kvtest
cc -g -O1 -fsanitize=address -o "$BIN" "$DIR/test_bridge_host.c" "$DIR/rocksdb_bridge_ohos.c"
ASAN_OPTIONS=detect_leaks=0 "$BIN" "$TMP"
