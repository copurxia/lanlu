#!/usr/bin/env bash
# Build in-memory/file-backed rocksdb C-API shim for aarch64-linux-ohos.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"
OUT=${1:-../liblanlu_rocksdb_bridge.so}
DIR=$(cd "$(dirname "$0")" && pwd)
"$OHOS_CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" -O2 -shared -fPIC "$DIR/rocksdb_bridge_ohos.c" -o "$OUT" -Wl,-soname,liblanlu_rocksdb_bridge.so
echo "built $OUT"
