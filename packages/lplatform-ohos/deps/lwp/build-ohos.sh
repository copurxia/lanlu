#!/usr/bin/env bash
# 为 OHOS(aarch64) 交叉编译 liblwp_native.so。计划 §5.2、§4.4。
#
# 为什么必须随 HAP 打包：引擎（liblanlu_client_next*.so）与壳（libmain.so）都要用它，
# 静态链会得到两份全局状态；而且壳必须 RTLD_GLOBAL 加载它、且早于引擎
# （docs/l-layer.md M0-4 结论：晚加载会静默失败，退出码仍是 0）。
#
# 产物：${LWP_OHOS_OUT:-$RES/lwp-ohos}/liblwp_native.so
# 用法：bash packages/lplatform-ohos/deps/lwp/build-ohos.sh
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)   # deps/lwp -> packages -> 仓库根
# C 源码属于中立包 packages/lwp（协议本体），交叉编译脚本属于平台包（计划 §2）
SRC=$REPO/packages/lwp/native
# shellcheck source=/dev/null
. "$HERE/../common-ohos.sh"

OUT=${LWP_OHOS_OUT:-${RES:-/workspace/lanlu/.research-ohos}/lwp-ohos}
mkdir -p "$OUT"

"$OHOS_CLANG" --target=aarch64-linux-ohos --sysroot="$OHOS_SYSROOT" \
    -std=c11 -O2 -fPIC -shared -pthread \
    -fvisibility=hidden \
    -Wl,--version-script="$SRC/liblwp.map" -Wl,-soname,liblwp_native.so \
    -o "$OUT/liblwp_native.so" "$SRC/liblwp.c"

echo "built $OUT/liblwp_native.so"
"$OHOS_LLVM_BIN"/llvm-readelf -d "$OUT/liblwp_native.so" | grep -E 'SONAME|NEEDED' || true
