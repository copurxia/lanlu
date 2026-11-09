#!/usr/bin/env bash
# 交叉编译 L 层渲染器（Rust → aarch64-linux-ohos staticlib）。
#
# 为什么用 horizon-ohos 的 rust190：本机没有系统 rust，且容器无法访问 crates.io；
# rust190 已装好 `aarch64-unknown-linux-ohos` std，/workspace/.cargo 里有离线 registry。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # -> packages/lgpu
NATIVE="$DIR/native"
RUST=${RUST:-/workspace/horizon-ohos/.tooling/rust190}
export CARGO_HOME=${CARGO_HOME:-/workspace/.cargo}
export PATH="$RUST/bin:/workspace/bin:$PATH"
export TMPDIR=${TMPDIR:-/workspace/tmp}

cd "$NATIVE"
"$RUST/bin/cargo" build --release --target aarch64-unknown-linux-ohos --offline
mkdir -p "$NATIVE/target/release"
cp -f "$NATIVE/target/aarch64-unknown-linux-ohos/release/liblgpu_native.a" "$NATIVE/target/release/liblgpu_native.a"
ls -l "$NATIVE/target/release/liblgpu_native.a" | awk '{print "staged liblgpu_native.a", $5}'
