#!/usr/bin/env bash
# Build in-memory/file-backed rocksdb C-API shim for aarch64-linux-ohos.
set -euo pipefail
CLANG=${OHOS_CLANG:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native/llvm/bin/clang}
SYSROOT=${OHOS_SYSROOT:-/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot}
OUT=${1:-../liblanlu_rocksdb_bridge.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$CLANG" --target=aarch64-linux-ohos --sysroot="$SYSROOT" -O2 -shared -fPIC "$DIR/rocksdb_bridge_ohos.c" -o "$OUT" -Wl,-soname,liblanlu_rocksdb_bridge.so
echo "built $OUT"
