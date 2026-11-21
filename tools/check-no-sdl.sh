#!/usr/bin/env bash
# "去 SDL"进度尺：统计各层对 SDL 的引用数，并检查**上层不许出现 SDL**。
#
# 目标形态：cui / apps/desktop 只依赖 L 层接口，SDL 只可能出现在过渡期的 backend 里。
# 阶段说明：
#   P0 基线           : sdl 包存在，cui/apps-desktop 允许少量 SDL_ 引用（待 P4 清除）
#   P5 完成后         : SDL 渲染壳删除，lgui 仅存 SDL 绑定过渡层
#   P6 吸收完成（当前）: lgui 包已整体并入 cui —— SDL 过渡债随之进入 cui/src
#                       （renderer/texture/dialogs 等遗留路径），以本脚本计数、只允许下降；
#                       M6 彻底清除 SDL 时归零
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# 只统计**代码**里的引用：注释里提到 SDL 不算依赖（分层守卫也豁免注释）。
count_refs() {
  grep -rh --include='*.cj' -E 'SDL_[A-Za-z0-9_]*|import sdl|sdl\.[a-z]' "$1" 2>/dev/null \
    | sed -E 's@//.*@@' \
    | grep -v -E '^[[:space:]]*(\*|/\*)' \
    | grep -o -E 'SDL_[A-Za-z0-9_]*|import sdl|sdl\.[a-z]' | wc -l
}

# P6 吸收后：lgui 包不存在，SDL 过渡债在 cui/src（原 lgui 的 renderer/texture/input 等）。
if [ -d "packages/cangjie-gui/lgui" ]; then
  echo "[FAIL] packages/cangjie-gui/lgui 应已并入 cui 并删除（P6 吸收完成）"
  exit 1
fi

cui_refs=$(count_refs packages/cangjie-gui/src 2>/dev/null)
cn_refs=$(count_refs apps/desktop/src 2>/dev/null)

echo "[cui] SDL 过渡债：cui 层引用=$cui_refs（含吸收自 lgui 的遗留路径）  apps/desktop 层引用=$cn_refs"

# 基线阈值：只允许下降，不允许上升（防止新增 SDL 依赖）。
# BASELINE_CUI 是 P6 吸收完成时 cui/src 的过渡债存量（**固定值**），M6 清 SDL 时归零。
# 注意：不要用「当前存量」当默认值 —— 那样棘轮永远不响（$cui_refs > $cui_refs 恒假）；
# 需要临时放宽时显式 export BASELINE_CUI。
# 2026-11-19：421 → 425（并行色彩补丁触及 events/sdl_types_raw）；随后 P6 拆包
# 重构 + 清理不可编译的 SDL 读回测试后降至 400，基线同步收紧。
BASELINE_CUI=${BASELINE_CUI:-400}
BASELINE_CN=${BASELINE_CN:-0}
if [ "$cui_refs" -gt "$BASELINE_CUI" ]; then
  echo "[FAIL] cui 对 SDL 的引用增加了（$cui_refs > $BASELINE_CUI）"
  fail=1
fi
if [ "$cn_refs" -gt "$BASELINE_CN" ]; then
  echo "[FAIL] apps/desktop 对 SDL 的引用增加了（$cn_refs > $BASELINE_CN）"
  fail=1
fi

# 低于基线：提示在清理完成后把脚本默认值同步收紧（存量只降不升）。
if [ "$cui_refs" -lt "$BASELINE_CUI" ]; then
  echo "[hint] cui 引用已降至 $cui_refs（基线 $BASELINE_CUI）：清理完成后请下调脚本默认值"
fi

[ "$fail" -eq 0 ] && echo "[PASS] SDL 依赖未增加（去 SDL 进度尺）"
exit "$fail"
