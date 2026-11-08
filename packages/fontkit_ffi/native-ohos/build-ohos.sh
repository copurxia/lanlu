#!/usr/bin/env bash
set -euo pipefail
CLANG=${OHOS_CLANG:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native/llvm/bin/clang}
SYSROOT=${OHOS_SYSROOT:-/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot}
OUT=${1:-../libfontkit_native.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$CLANG" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -O2 -shared -fPIC "$DIR/fontkit_shim.c" -o "$OUT" -Wl,-soname,libfontkit_native.so
echo "built $OUT"
