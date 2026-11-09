#!/usr/bin/env bash
# "去 SDL"进度尺：统计各层对 SDL 的引用数，并检查**上层不许出现 SDL**。
#
# 目标形态：cui / client-next 只依赖 L 层接口，SDL 只可能出现在过渡期的 backend 里。
# 阶段说明：
#   P0 基线（当前）: sdl 包存在，cui/client-next 允许少量 SDL_ 引用（待 P4 清除）
#   P5 完成后    : packages/cangjie-gui/sdl 必须不存在，全仓 SDL_ 引用为 0
set -uo pipefail
cd "$(dirname "$0")/.."

SDL_PKG="packages/cangjie-gui/sdl"
fail=0

# 只统计**代码**里的引用：注释里提到 SDL 不算依赖（分层守卫也豁免注释）。
count_refs() {
  grep -rh --include='*.cj' -E 'SDL_[A-Za-z0-9_]*|import sdl|sdl\.[a-z]' "$1" 2>/dev/null \
    | sed -E 's@//.*@@' \
    | grep -v -E '^[[:space:]]*(\*|/\*)' \
    | grep -o -E 'SDL_[A-Za-z0-9_]*|import sdl|sdl\.[a-z]' | wc -l
}

sdl_files=$(find "$SDL_PKG" -name '*.cj' 2>/dev/null | wc -l)
sdl_lines=$(find "$SDL_PKG" -name '*.cj' -exec cat {} + 2>/dev/null | wc -l)
cui_refs=$(count_refs packages/cangjie-gui/src 2>/dev/null)
cn_refs=$(count_refs client-next/src 2>/dev/null)

echo "[sdl] 过渡层文件数=$sdl_files 行数=$sdl_lines"
echo "[sdl] cui 层引用=$cui_refs  client-next 层引用=$cn_refs"

# P0 基线阈值：只允许下降，不允许上升（防止新增 SDL 依赖）
BASELINE_CUI=${BASELINE_CUI:-224}
BASELINE_CN=${BASELINE_CN:-0}
if [ "$cui_refs" -gt "$BASELINE_CUI" ]; then
  echo "[FAIL] cui 对 SDL 的引用增加了（$cui_refs > $BASELINE_CUI）"
  fail=1
fi
if [ "$cn_refs" -gt "$BASELINE_CN" ]; then
  echo "[FAIL] client-next 对 SDL 的引用增加了（$cn_refs > $BASELINE_CN）"
  fail=1
fi

# 若 sdl 包已删除（P5 完成），则要求全仓零引用
if [ "$sdl_files" -eq 0 ]; then
  left=$(grep -rho 'SDL_[A-Za-z0-9_]*' packages client-next/src --include='*.cj' 2>/dev/null | wc -l)
  echo "[sdl] sdl 包已移除；剩余 SDL_ 引用=$left"
  if [ "$left" -ne 0 ]; then echo "[FAIL] 仍有 SDL 引用残留"; fail=1; fi
fi

[ "$fail" -eq 0 ] && echo "[PASS] SDL 依赖未增加（去 SDL 进度尺）"
exit "$fail"
