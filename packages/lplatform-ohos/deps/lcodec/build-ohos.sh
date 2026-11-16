#!/usr/bin/env bash
# 交叉编译 lcodec 原生后端（Rust/libblur → aarch64-linux-ohos cdylib）。
# 产物 liblcodec_native.so 随 HAP 打包，由 lcodec 运行时 dlopen（业务层零链接依赖）。
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$(cd "$HERE/../../../lcodec/native" && pwd)"   # -> packages/lcodec/native
RUST=${RUST:-${OHOS_RUST:-/workspace/horizon-ohos/.tooling/rust190}}
export CARGO_HOME=${CARGO_HOME:-${OHOS_CARGO_HOME:-/workspace/.cargo}}
export PATH="$RUST/bin:/workspace/bin:$PATH"
export TMPDIR=${TMPDIR:-/workspace/tmp}
# cdylib 需要真链接器：用 SDK 的 clang + sysroot
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$OHOS_CLANG"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_RUSTFLAGS="-C link-arg=--target=aarch64-linux-ohos -C link-arg=--sysroot=$OHOS_SYSROOT -C link-arg=-Wl,-soname,liblcodec_native.so"

cd "$NATIVE"
"$RUST/bin/cargo" build --release --target aarch64-unknown-linux-ohos --offline
OUT="$NATIVE/target/ohos"
mkdir -p "$OUT"
cp -f "$NATIVE/target/aarch64-unknown-linux-ohos/release/liblcodec_native.so" "$OUT/liblcodec_native.so"
ls -l "$OUT/liblcodec_native.so" | awk '{print "staged liblcodec_native.so", $5}'
