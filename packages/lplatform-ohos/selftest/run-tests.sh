#!/usr/bin/env bash
# 平台包自测入口（宿主可跑，不需要设备）。计划 §16.2 T1。
#
# 现在只有一项：壳侧 LWP 发送端（lwp_client.cpp）的字节级契约测试。
# 后续 portcheck 自检迁移过来后也挂在这里。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/workspace/lanlu/tmp}/lplat-test.XXXXXX")}
mkdir -p "$OUT"
fail=0

echo "== 重新构建 liblwp_native.so（宿主）"
bash "$REPO/packages/lwp/native/build.sh" >/dev/null || { echo "[FAIL] 构建 liblwp"; exit 1; }
LWP_LIB="$REPO/packages/lwp/lib"

echo "== 壳侧 LWP 发送端：协议模式"
c++ -std=c++17 -Wall -Wextra -O1 -o "$OUT/test_lwp_client" \
    -DLWP_HOST_SELFTEST=1 \
    "$HERE/test_lwp_client.cpp" \
    "$REPO/packages/lplatform-ohos/shell/native/lwp_client.cpp" \
    "$REPO/packages/lplatform-ohos/shell/native/lwp_window.cpp" \
    -I "$REPO/packages/lwp/include" -L "$LWP_LIB" -llwp_native -ldl || fail=1
[ $fail -ne 0 ] || LD_LIBRARY_PATH="$LWP_LIB:${LD_LIBRARY_PATH:-}" "$OUT/test_lwp_client" protocol || fail=1
echo "== 壳侧 LWP 发送端：回落模式"
# M6 后 LWP 默认开启，回退模式必须显式 LANLU_LWP=0（此时输入被丢弃）
[ $fail -ne 0 ] || LANLU_LWP=0 LD_LIBRARY_PATH="$LWP_LIB:${LD_LIBRARY_PATH:-}" "$OUT/test_lwp_client" fallback || fail=1

rm -rf "$OUT"
if [ $fail -eq 0 ]; then
  echo "[PASS] 平台包自测通过"
  exit 0
fi
echo "[FAIL] 平台包自测失败"
exit 1
