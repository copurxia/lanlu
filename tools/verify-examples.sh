#!/usr/bin/env bash
# 编译框架仓库里所有示例与 bench 工程，确认"示例即文档、基准即用法"没有腐坏。
#
# 背景：examples/calendar 长期引用已随 SDL 移除的 Surface，从 P5 改写起就编不过，
# 而单元测试不覆盖示例、文档也不会报错——这类腐坏只能靠全量编译发现。
#
# 判定口径：**链接期**缺 SDL/vips 等原生符号属本机环境限制（无真实渲染后端），
# 视为通过；语义/类型/语法错误才算失败。
#
# 用法：tools/verify-examples.sh [p0|<worktree 名>]   默认 p0
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="${1:-p0}"
if [ "$TREE" = "p0" ]; then
  REPO="$ROOT/packages/cangjie-gui-p0"
else
  REPO="$ROOT/packages/cangjie-gui-$TREE"
fi
DIR="$REPO/examples"
[ -d "$DIR" ] || { echo "找不到示例目录：$DIR"; exit 2; }

export PATH="${CJ_BIN:-/workspace/.cjv/bin}:$PATH"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-/workspace/.cjv/stdx/lts/static/stdx}"

ok=0
fail=0
failed_names=()

compile_tree() {
  local base="$1"
  local label="$2"
  for d in "$base"/*/; do
    local name
    name="$(basename "$d")"
    [ -f "$d/cjpm.toml" ] || continue
    local log="/tmp/verify-$label-$name.log"
    ( cd "$d" && timeout 300 cjpm build --skip-script > "$log" 2>&1 )
    if [ $? -eq 0 ]; then
      ok=$((ok+1))
    elif grep -qE "undefined reference|cannot find -l" "$log" 2>/dev/null; then
      ok=$((ok+1))   # 仅链接期缺原生符号：本机环境限制
    else
      fail=$((fail+1))
      failed_names+=("$label/$name")
      echo "✗ $label/$name（日志：$log）"
      sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^error' -A 2 | head -6
    fi
  done
}

compile_tree "$DIR" "example"
[ -d "$REPO/bench" ] && compile_tree "$REPO/bench" "bench"

echo "== 示例+bench 编译：通过 $ok / 失败 $fail"
[ "$fail" -eq 0 ] || { echo "失败项：${failed_names[*]}"; exit 1; }
