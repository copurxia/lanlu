#!/usr/bin/env bash
# 构建 liblwp.so（壳与引擎共同依赖的独立共享库）。计划 §5.2。
#
# 为什么必须是独立 .so：壳（libmain.so）与引擎（liblanlu_client_next*.so）都要用它，
# 静态链会得到两份全局状态（现在的 lgpu 就是这种双份链接，见计划 §1.5）。
# 同时按 docs/l-layer.md 的 M0-4 结论：壳须 RTLD_GLOBAL 加载且早于引擎。
#
# 用法：bash packages/lwp/native/build.sh [输出目录]
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=${1:-$HERE/../lib}
CC=${CC:-cc}
mkdir -p "$OUT"
# -fvisibility=hidden：只导出 lwp_* 与 lwp__test_* 显式默认可见的符号，避免污染宿主命名空间
$CC -std=c11 -O2 -fPIC -shared -pthread \
    -fvisibility=hidden \
    -Wl,--version-script="$HERE/liblwp.map" \
    -o "$OUT/liblwp_native.so" "$HERE/liblwp.c"
echo "built $OUT/liblwp_native.so"
# 说明：C 库名带 _native 后缀，避免与仓颉包产物 liblwp.a 在 -llwp 上撞名
