#!/usr/bin/env bash
# Build libvips.so (stb_image backed) for aarch64-linux-ohos.
set -euo pipefail
CLANG=${OHOS_CLANG:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native/llvm/bin/clang}
SYSROOT=${OHOS_SYSROOT:-/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot}
OUT=${1:-../libvips.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$CLANG" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -O2 -I"$DIR" -shared -fPIC "$DIR/vips_shim.c" -o "$OUT" -lm -ldl -Wl,-soname,libvips.so
echo "built $OUT"
