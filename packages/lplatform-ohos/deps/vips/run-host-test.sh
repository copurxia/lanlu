#!/usr/bin/env bash
# Host regression test: decodeFileToRgba's handle/unref sequence against vips_shim.c.
# Catches the double-free class of bug the OHOS port hit (conversions aliasing the
# input -> each handle unref'd separately). Run with ASAN; exits non-zero on error.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=$(mktemp -d)/shim_test
cc -g -O1 -fsanitize=address -o "$OUT" "$DIR/test_shim_double_free.c" "$DIR/vips_shim.c" -I"$DIR" -ldl -lm
"$OUT" "$1"
