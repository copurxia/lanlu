#!/usr/bin/env bash
# 同步 vendored winit（Wayland 壳的窗口/输入栈）到 packages/lplatform-wayland/third_party/winit。
#
# 为什么：桌面壳用 winit 0.31 的 winit-wayland 后端（计划 §9.3、§15.3）。本机离线，
# crates.io 不可达，而 horizon-ohos 已 vendored 一份带 OHOS 后端的 winit 家族并保持
# 可构建；两侧共用一份源码，补丁也只需要维护一处。
#
# 用法：
#   bash tools/sync-winit.sh                 # 同步
#   bash tools/sync-winit.sh --check         # 只检查源是否就位（CI 用）
#   SRC=/path/to/winit bash tools/sync-winit.sh
#
# 升级 winit 时：改 SRC 指向新的 upstream 检出，同步后重跑
#   (cd packages/lplatform-wayland && cargo build --offline)
# 并确认 winit-wayland 仍有 zwp_text_input_v3 / fractional-scale / viewporter /
# drag_window（见计划 §8A 的映射表）。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${SRC:-/workspace/horizon-ohos/horizon/third_party/winit}
DST=$ROOT/packages/lplatform-wayland/third_party/winit

if [ ! -d "$SRC" ]; then
  echo "ERROR: 找不到 winit 源：$SRC（用 SRC=... 指定）" >&2
  exit 1
fi
for sub in winit winit-core winit-common winit-wayland winit-x11 dpi; do
  [ -d "$SRC/$sub" ] || { echo "ERROR: 源缺少 $sub 目录" >&2; exit 1; }
done

if [ "${1:-}" = "--check" ]; then
  echo "[ok] winit 源就位：$SRC"
  exit 0
fi

mkdir -p "$(dirname "$DST")"
# 不复制 examples/ 与 target/：体积大且与本项目无关
rsync -a --delete \
  --exclude 'target/' --exclude 'examples/' --exclude '.git/' \
  "$SRC/" "$DST/"

# 记录来源，便于升级时比对
{
  echo "source: $SRC"
  echo "synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if git -C /workspace/horizon-ohos rev-parse --short HEAD >/dev/null 2>&1; then
    echo "horizon-ohos-commit: $(git -C /workspace/horizon-ohos rev-parse --short HEAD)"
  fi
} > "$DST/SYNCED-FROM.txt"

echo "synced -> $DST"
du -sh "$DST"
