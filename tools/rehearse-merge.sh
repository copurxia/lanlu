#!/usr/bin/env bash
# 合并演练：把 gui 补丁序列应用到一个"主仓当前工作树快照"的副本上并跑测试。
#
# 为什么需要：主仓 packages/cangjie-gui 长期有他人未提交改动，无法直接在原地合并验证。
# 本脚本复制一份工作树（含对方未提交改动）→ 把改动落成快照提交 → git am 应用补丁 →
# 跑桩库测试并与基线名册比对。全程不触碰主仓工作树。
#
# 用法：
#   tools/rehearse-merge.sh                # 演练 + 跑测试，成功后清理副本
#   tools/rehearse-merge.sh --keep         # 保留副本（排查用）
#   tools/rehearse-merge.sh --no-test      # 只验证补丁能否干净应用
#
# 依赖：tools/verify-cui-interactions.sh、docs/interaction-audit/patches/*.patch、
#       以及 packages/lcodec（若 lgui 依赖它；脚本会做隔离副本并改写副本内的相对路径）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/packages/cangjie-gui"
PATCHES="${PATCHES:-$ROOT/docs/interaction-audit/patches}"
COPY="${COPY:-$ROOT/packages/cangjie-gui-rehearse}"
LCODEC="$ROOT/packages/lcodec"
LCODEC_COPY="$ROOT/packages/lcodec-rehearsal"
KEEP=0
TEST=1
for a in "$@"; do
  case "$a" in
    --keep) KEEP=1 ;;
    --no-test) TEST=0 ;;
    *) echo "未知参数：$a" >&2; exit 2 ;;
  esac
done

command -v rsync >/dev/null || { echo "需要 rsync" >&2; exit 2; }
[ -d "$SRC" ] || { echo "缺少 $SRC" >&2; exit 2; }
[ -d "$PATCHES" ] || { echo "缺少补丁目录 $PATCHES" >&2; exit 2; }

echo "== 1/5 复制主仓工作树快照 → $COPY"
rm -rf "$COPY"
mkdir -p "$COPY"
rsync -a --exclude target --exclude build-ohos "$SRC/" "$COPY/"

echo "== 2/5 把对方的未提交改动落成快照提交（仅副本内）"
cd "$COPY"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c user.name=rehearsal -c user.email=rehearsal@local commit -q -m "rehearsal: 主仓工作树快照（含未提交改动）"
  echo "   已提交 $(git rev-list --count HEAD) 个提交的快照"
else
  echo "   工作树干净，无需快照提交"
fi

# lgui 可能依赖 packages/lcodec：做隔离副本，只改演练副本里的相对路径。
if [ -f "$LCODEC/cjpm.toml" ]; then
  if grep -q 'lcodec' "$COPY/lgui/cjpm.toml" 2>/dev/null; then
    echo "== 3/5 隔离 lcodec 依赖 → $LCODEC_COPY"
    rm -rf "$LCODEC_COPY"
    mkdir -p "$LCODEC_COPY"
    rsync -a --exclude target "$LCODEC/" "$LCODEC_COPY/"
    sed -i 's#lcodec = { path = "../../lcodec" }#lcodec = { path = "../../lcodec-rehearsal" }#' "$COPY/lgui/cjpm.toml"
  else
    echo "== 3/5 lgui 未依赖 lcodec，跳过隔离"
  fi
else
  echo "== 3/5 无 lcodec 包，跳过隔离"
fi

echo "== 4/5 应用 gui 补丁（git am --3way）"
if ! git -c user.name=rehearsal -c user.email=rehearsal@local am --3way "$PATCHES"/*.patch; then
  echo "!! 补丁应用失败（冲突或上下文漂移），副本保留在 $COPY" >&2
  echo "   查看：cd $COPY && git status && git am --show-current-patch=diff" >&2
  exit 1
fi
echo "   已应用 $(ls "$PATCHES"/*.patch | wc -l) 个补丁"

# 宿主机测试链接行兜底：迁移中的工作树可能删掉了 [target.x86_64-unknown-linux-gnu] 的
# link-option，导致测试可执行文件缺 SDL_* 符号。演练副本里补一条已知可用的链接行，
# 让测试跑起来（只影响副本，不改主仓；桩库同时提供 SDL 与 vips 符号）。
if [ "$TEST" -eq 1 ]; then
  for toml in "$COPY/cjpm.toml" "$COPY/lgui/cjpm.toml"; do
    [ -f "$toml" ] || continue
    if ! grep -q 'x86_64-unknown-linux-gnu' "$toml"; then
      printf '\n# 演练脚手架：宿主机测试链接行（主仓工作树当前缺失，见 05-merge-rehearsal.md）\n[target.x86_64-unknown-linux-gnu]\nlink-option = "-lvips -lgio-2.0 -lgobject-2.0 -lglib-2.0"\n' >> "$toml"
      echo "   已给 $(basename "$(dirname "$toml")")/$(basename "$toml") 补宿主机 link-option（演练脚手架）"
    fi
  done
fi

if [ "$TEST" -eq 0 ]; then
  echo "== 5/5 跳过测试（--no-test）"
else
  echo "== 5/5 跑桩库测试并与基线名册比对"
  export CANGJIE_STDX_PATH="${CANGJIE_STDX_PATH:-/workspace/.cjv/stdx/lts/static/stdx}"
  if ! PKG_DIR="$COPY" LOG="${LOG:-/workspace/tmp/rehearse-merge.log}" \
      "$ROOT/tools/verify-cui-interactions.sh"; then
    echo "!! 测试与基线不一致（见上面的 diff），副本保留在 $COPY" >&2
    exit 1
  fi
fi

if [ "$KEEP" -eq 1 ]; then
  echo "== 完成；副本保留：$COPY"
else
  echo "== 完成；清理副本"
  rm -rf "$COPY"
fi
