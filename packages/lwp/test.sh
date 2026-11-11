#!/usr/bin/env bash
# LWP 全部测试入口：C 侧（协议布局 / 通道 / 检查器 / 录制 / lwtrace）+ 仓颉侧（解码 / 通道 FFI）。
#
# 用法：bash packages/lwp/test.sh
# 依赖：cc；若要跑仓颉测试还需要仓颉 host 工具链（CANGJIE_HOME 或 CJV_HOST_TOOLCHAIN）。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
fail=0

echo "== 1/3 生成物与 IDL 一致"
python3 "$ROOT/tools/lwp-gen.py" --check || fail=1
python3 "$ROOT/tools/lwp-gen.py" --check-abi || fail=1

echo "== 2/3 C 侧测试"
bash "$HERE/native/run-tests.sh" || fail=1

echo "== 3/3 仓颉侧测试（链接 liblwp_native.so）"
BASE=${CJV_HOST_TOOLCHAIN:-${CANGJIE_HOME:-/workspace/.cjv/toolchains/sts-1.2.0}}
if [ ! -x "$BASE/bin/cjc" ]; then
  echo "  [skip] 没有仓颉 host 工具链（$BASE），跳过仓颉测试"
else
  bash "$HERE/native/build.sh" >/dev/null || fail=1
  (
    export CANGJIE_HOME="$BASE"
    export LD_LIBRARY_PATH="$BASE/runtime/lib/linux_x86_64_cjnative:$BASE/lib/linux_x86_64_cjnative"
    export PATH="$BASE/bin:$PATH"
    export LWP_LIB_DIR="$HERE/lib"
    export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-/workspace/.cjv/stdx/sts-1.2.0-linux-x64-ohos/static}"
    cd "$HERE" && "$BASE/tools/bin/cjpm" test --no-color
  ) || fail=1
fi

if [ $fail -eq 0 ]; then
  echo "[PASS] lwp 全部测试通过"
  exit 0
fi
echo "[FAIL] lwp 测试失败"
exit 1
