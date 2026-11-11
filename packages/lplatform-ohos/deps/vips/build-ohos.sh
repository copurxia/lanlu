#!/usr/bin/env bash
# Build libvips.so (stb_image backed) for aarch64-linux-ohos.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"
OUT=${1:-../libvips.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$OHOS_CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" -O2 -I"$DIR" -shared -fPIC "$DIR/vips_shim.c" -o "$OUT" -lm -ldl -Wl,-soname,libvips.so
echo "built $OUT"
