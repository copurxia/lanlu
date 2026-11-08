#!/usr/bin/env bash
set -euo pipefail
CLANG=${OHOS_CLANG:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native/llvm/bin/clang}
SYSROOT=${OHOS_SYSROOT:-/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot}
FFDIR=${FFMPEG_LIB_DIR:-/workspace/lanlu/.research-ohos/ohos-stubs/ffmpeg}
FFSRC=${FFMPEG_SRC:-/workspace/tmp/ffsrc}
OUT=${1:-../libvlc.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$CLANG" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -O2 -I"$FFSRC" -shared -fPIC "$DIR/vlc_shim.c" -o "$OUT" \
  -L"$FFDIR" -lavformat -lavcodec -lswscale -lavutil -lswresample -lpthread -lm \
  -L"$SYSROOT/usr/lib/aarch64-linux-ohos" -lohaudio -Wl,-soname,libvlc.so
echo "built $OUT"
