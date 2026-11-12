#!/usr/bin/env bash
# 一把落地：把 p0-focus-visible（gui 分支）与应用层接线落到仓库里。
#
# 用法：
#   tools/land-focus-interactions.sh --check    # 只检查前置条件（不写任何东西）
#   tools/land-focus-interactions.sh            # 真正落地（需要干净工作树）
#
# 前置条件（脚本会逐条检查并在 --check 模式下报告）：
#   1) packages/cangjie-gui 工作树干净（对方 WIP 必须先提交，否则拒绝执行）
#   2) 能读到 gui 分支 p0-focus-visible 或其补丁序列
#   3) 有 cjv 工具链与 stdx 路径
#
# 落地步骤：
#   合并 gui 分支（或 git am 补丁）→ 缺宿主机 link-option 则补 → 跑桩库测试比对基线
#   → cherry-pick 应用层分支 app-focus-wiring（若存在）→ 汇报结果。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUI="$ROOT/packages/cangjie-gui"
PATCHES="${PATCHES:-$ROOT/docs/interaction-audit/patches}"
MODE="apply"
for a in "$@"; do
  case "$a" in
    --check) MODE="check" ;;
    --emit-patches) MODE="emit" ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数：$a" >&2; exit 2 ;;
  esac
done

# --emit-patches：从 gui 工作树的分支重新生成补丁序列（提交后忘了 format-patch 的自救入口）。
if [ "$MODE" = "emit" ]; then
  git -C "$GUI" rev-parse -q --verify p0-focus-visible >/dev/null 2>&1 || fail "gui 仓库里没有 p0-focus-visible 分支"
  rm -f "$PATCHES"/*.patch
  ( cd "$GUI" && git format-patch --no-numbered --zero-commit -o "$PATCHES" c39458f..p0-focus-visible >/dev/null )
  echo "已生成 $(ls "$PATCHES"/*.patch | wc -l) 个补丁 → $PATCHES"
  exit 0
fi

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }

echo "== 1/5 前置检查"
[ -d "$GUI" ] || fail "找不到 $GUI"
dirty=$(git -C "$GUI" status --porcelain | wc -l)
if [ "$dirty" -ne 0 ]; then
  git -C "$GUI" status --short | head -12
  fail "packages/cangjie-gui 有 $dirty 个未提交文件——请先让对方提交或协调，绝不能在脏树上合并"
fi
ok "gui 工作树干净"

has_branch=0
git -C "$GUI" rev-parse -q --verify p0-focus-visible >/dev/null 2>&1 && has_branch=1
[ -d "$PATCHES" ] && patch_count=$(ls "$PATCHES"/*.patch 2>/dev/null | wc -l) || patch_count=0
if [ "$has_branch" -eq 0 ] && [ "$patch_count" -eq 0 ]; then
  fail "既没有 p0-focus-visible 分支，也没有补丁序列（$PATCHES）"
fi

# 补丁新鲜度（2026-11-12 教训）：用补丁落地时，数量必须与分支提交数一致；不一致说明
# 补丁目录过期，落地会静默丢掉最后几次修复。
if [ "$has_branch" -eq 1 ] && [ "$patch_count" -gt 0 ]; then
  base=$(git -C "$GUI" rev-parse -q --verify c39458f^{commit} 2>/dev/null || true)
  if [ -n "$base" ]; then
    branch_count=$(git -C "$GUI" rev-list --count "$base"..p0-focus-visible)
    if [ "$patch_count" -ne "$branch_count" ]; then
      fail "补丁过期：$patch_count 个补丁 vs 分支 $branch_count 个提交——先重新 format-patch"
    fi
  fi
fi
ok "落地来源：$([ "$has_branch" -eq 1 ] && echo "分支 p0-focus-visible" || echo "$patch_count 个补丁")"

command -v cjc >/dev/null 2>&1 || [ -x /workspace/.cjv/bin/cjc ] || fail "找不到 cjv 工具链"
ok "工具链可用"

if [ "$MODE" = "check" ]; then
  echo
  echo "前置条件全部满足——去掉 --check 即可执行落地。"
  exit 0
fi

echo "== 2/5 落地 gui 改动"
cd "$GUI"
if [ "$has_branch" -eq 1 ]; then
  git -c user.name=land -c user.email=land@local merge --no-ff p0-focus-visible -m "merge: p0-focus-visible（交互审计全部修复）"
else
  git -c user.name=land -c user.email=land@local am --3way "$PATCHES"/*.patch
fi
ok "gui 改动已落地（$(git rev-list --count HEAD) 个提交）"

echo "== 3/5 宿主机测试链接行"
for toml in cjpm.toml lgui/cjpm.toml; do
  if [ -f "$toml" ] && ! grep -q 'x86_64-unknown-linux-gnu' "$toml"; then
    printf '\n[target.x86_64-unknown-linux-gnu]\nlink-option = "-lSDL3 -lSDL3_ttf"\n' >> "$toml"
    ok "为 $toml 补宿主机 link-option（SDL3 仍需要；vips 已由 lcodec 运行期装载）"
  fi
done

echo "== 4/5 跑桩库测试并与基线比对"
export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-/workspace/.cjv/stdx/lts/static/stdx}"
if ! "$ROOT/tools/verify-cui-interactions.sh"; then
  fail "测试与基线不一致——先按上面 diff 排查，再决定是否继续"
fi

echo "== 5/5 应用层接线"
if git -C "$ROOT" rev-parse -q --verify app-focus-wiring >/dev/null 2>&1; then
  git -C "$ROOT" -c user.name=land -c user.email=land@local cherry-pick app-focus-wiring
  ok "已 cherry-pick app-focus-wiring（应用层 A/B/D）"
else
  echo "   未找到 app-focus-wiring 分支，可改用补丁："
  echo "   for f in $ROOT/docs/interaction-audit/patches-app/*.patch; do git -C $ROOT apply \"$f\"; done"
fi

echo
echo "== 完成。下一步：按 docs/interaction-audit/06-acceptance-checklist.md 做真机验收。"
