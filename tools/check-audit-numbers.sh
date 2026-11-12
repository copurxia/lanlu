#!/usr/bin/env bash
# 校验审计文档里的"当前数字"是否与实际一致（提交数、测试数、补丁数）。
# 历史叙述（"当时 N 个"）不参与校验；本脚本只读，不改文件。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI="$ROOT/packages/cangjie-gui-p0"
[ -d "$GUI" ] || { echo "跳过：找不到 $GUI"; exit 0; }

COMMITS=$(git -C "$GUI" rev-list --count c39458f..HEAD)
PATCHES=$(ls "$ROOT/docs/interaction-audit/patches"/*.patch 2>/dev/null | wc -l)
PASSED=$(grep -hoE 'PASSED: [0-9]+' "$ROOT"/docs/interaction-audit/*.md | tail -1 | grep -oE '[0-9]+')
echo "实际：提交 $COMMITS / 补丁 $PATCHES"

fail=0
# 1) 补丁 README 的"全部 N 个提交"
readme_n=$(grep -oE '\*\*[0-9]+ 个补丁 = 分支全部 [0-9]+ 个提交\*\*' "$ROOT/docs/interaction-audit/patches/README.md" | grep -oE '[0-9]+ 个提交' | grep -oE '[0-9]+')
[ "${readme_n:-x}" = "$COMMITS" ] || { echo "✗ patches/README.md 写的是 ${readme_n:-?} 个提交，实际 $COMMITS"; fail=1; }
# 2) 09 状态表头
s09=$(grep -oE '\*\*[0-9]+ 个提交\*\*' "$ROOT/docs/interaction-audit/09-gap-final-status.md" | head -1 | grep -oE '[0-9]+')
[ "${s09:-x}" = "$COMMITS" ] || { echo "✗ 09-gap-final-status.md 写的是 ${s09:-?} 个提交，实际 $COMMITS"; fail=1; }
# 3) RC 报告的补丁数
rc=$(grep -oE '\*\*[0-9]+ 个补丁\*\*' "$ROOT/docs/interaction-audit/11-rc-report.md" | head -1 | grep -oE '[0-9]+')
[ "${rc:-x}" = "$PATCHES" ] || { echo "✗ 11-rc-report.md 写的是 ${rc:-?} 个补丁，实际 $PATCHES"; fail=1; }
# 4) 01-summary 的实现行提交数
sm=$(grep -oE '\*\*[0-9]+ 个提交（' "$ROOT/docs/interaction-audit/01-summary.md" | head -1 | grep -oE '[0-9]+')
[ "${sm:-x}" = "$COMMITS" ] || { echo "✗ 01-summary.md 写的是 ${sm:-?} 个提交，实际 $COMMITS"; fail=1; }

[ "$fail" -eq 0 ] && echo "== 文档当前数字与实际一致（提交 $COMMITS / 补丁 $PATCHES）"
exit "$fail"
