#!/usr/bin/env bash
# Host regression test for the OHOS fontkit shim (dir scan, filtering, cleanup).
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
mkdir -p "$TMP/fonts"
touch "$TMP/fonts/a.ttf" "$TMP/fonts/b.otf" "$TMP/fonts/c.txt" "$TMP/fonts/d.ttc" "$TMP/fonts/.hidden.ttf"
cc -g -O1 -fsanitize=address -o "$TMP/ftest" "$DIR/test_shim_host.c" "$DIR/fontkit_shim.c"
ASAN_OPTIONS=detect_leaks=0 "$TMP/ftest" "$TMP/fonts"
