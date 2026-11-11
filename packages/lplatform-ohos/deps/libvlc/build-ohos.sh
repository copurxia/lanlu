#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"
FFDIR=${FFMPEG_LIB_DIR:-/workspace/lanlu/.research-ohos/ohos-stubs/ffmpeg}
FFSRC=${FFMPEG_SRC:-/workspace/tmp/ffsrc}
OUT=${1:-../libvlc.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$OHOS_CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" -O2 -I"$FFSRC" -shared -fPIC "$DIR/vlc_shim.c" -o "$OUT" \
  -L"$FFDIR" -lavformat -lavcodec -lswscale -lavutil -lswresample -lpthread -lm \
  -L"$OHOS_SYSROOT/usr/lib/aarch64-linux-ohos" -lohaudio -Wl,-soname,libvlc.so
echo "built $OUT"
