#!/usr/bin/env bash
# 最小用例：引擎（仓颉 dylib）调用壳（C）导出的符号 —— 复现 docs/l-layer.md 记录的历史崩溃。
#
# 每个变体都是**断言**而不是演示：行为变了就退出非零（计划 §16.9 完成定义）。
# 结论见 docs/l-layer.md「M0-4 最小用例结论」。
#
# 用法：bash run.sh          断言当前行为符合结论
#      bash run.sh --verbose  额外打印各变体完整输出
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE=${CJV_HOST_TOOLCHAIN:-${CANGJIE_HOME:-/workspace/.cjv/toolchains/sts-1.2.0}}
OUT=${OUT:-$HERE/out}
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1
rm -rf "$OUT"; mkdir -p "$OUT"

export CANGJIE_HOME="$BASE"
export LD_LIBRARY_PATH="$BASE/runtime/lib/linux_x86_64_cjnative:$BASE/lib/linux_x86_64_cjnative"
export PATH="$BASE/bin:$PATH"

echo "== 1. 壳（C）"
cc -shared -fPIC -O1 -o "$OUT/libshell.so" "$HERE/shell.c" -lpthread || exit 1
cc -shared -fPIC -O1 -o "$OUT/libshell_ctor.so" "$HERE/shell_ctor.c" -ldl || exit 1
cc -shared -fPIC -O1 -o "$OUT/libshell_ctor2.so" "$HERE/shell_ctor2.c" -ldl -lpthread || exit 1

echo "== 2. 引擎（仓颉 dylib，不链接壳：符号在 dlopen 时才解析）"
"$BASE/bin/cjc" --output-type=dylib -O1 -o "$OUT/libengine.so" "$HERE/engine.cj" 2>&1 | tail -3
[ -f "$OUT/libengine.so" ] || { echo "FAIL: 引擎未生成"; exit 1; }

echo "== 3. 宿主（C）"
cc -O1 -o "$OUT/loader" "$HERE/loader.c" -ldl || exit 1

fails=0
# run <mode> <shell> <期望的标记正则> <说明>
check() {
  local mode=$1 shell=$2 expect=$3 desc=$4
  local log rc
  log=$(cd "$OUT" && LD_LIBRARY_PATH=".:$LD_LIBRARY_PATH" ./loader ./libengine.so "$shell" "$mode" 2>&1)
  rc=$?
  [ "$VERBOSE" = 1 ] && { echo "---- $mode 输出 ----"; printf '%s\n' "$log"; }
  if printf '%s' "$log" | grep -qE "$expect"; then
    echo "  [ok]   $mode —— $desc"
  else
    echo "  [FAIL] $mode —— 期望匹配 /$expect/，实际："
    printf '%s\n' "$log" | sed 's/^/         /' | head -12
    fails=$((fails + 1))
  fi
  return 0
}

echo "== 4. 断言（5 个变体）"
# 正确顺序：壳先以 RTLD_GLOBAL 加载 → 引擎能解析、调用得到 43、外部线程回调得到 63
check shell-first-g    ./libshell.so        'cj_app_main returned 43'  '壳先加载 → 引擎调壳 43、外部线程回调 63'
check shell-first-g    ./libshell.so        'foreign thread call -> 63' '外部线程（pthread）调仓颉 @C 可用'
# 壳后加载：LoadCJLibraryWithInit 失败，但 dlopen(RTLD_LAZY) 仍"成功"、退出码 0 —— 静默错误
check engine-first     ./libshell.so        'LoadCJLibraryWithInit rc=-1' '壳后加载 → 加载失败（静默：退出码仍为 0）'
# RTLD_LOCAL：引擎永远看不到壳符号
check shell-local      ./libshell.so        'undefined symbol'        'RTLD_LOCAL → 符号永远不可见'
# 构造函数里同步启动：壳自身符号尚未进入全局作用域
check ctor             ./libshell_ctor.so   'undefined symbol'        '构造函数内同步启动 → 失败'
# 构造函数只起线程、稍后启动：能过（但不保证时序）
check ctor             ./libshell_ctor2.so  'cj_app_main returned 43'  '构造函数起线程、稍后启动 → 能过（时序碰运气）'

echo
if [ "$fails" -eq 0 ]; then
  echo "[PASS] ffi-call 探针：5 个变体行为与 docs/l-layer.md 的结论一致"
  exit 0
fi
echo "[FAIL] ffi-call 探针：$fails 个变体行为与结论不符（先 nm -D 核对导出符号，再改结论）"
exit 1
