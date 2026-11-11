#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"
OUT=${1:-../libfontkit_native.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$OHOS_CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" -O2 -shared -fPIC "$DIR/fontkit_shim.c" -o "$OUT" -Wl,-soname,libfontkit_native.so
echo "built $OUT"
