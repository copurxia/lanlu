#!/usr/bin/env bash
# 同步 wgpu-hal 的 OHOS 补丁副本（vendored）。
#
# 为什么需要：上游 wgpu-hal 不支持 HarmonyOS 的 VK_OHOS_surface（XComponent 原生窗口
# 作 vulkan surface）。horizon-ohos 维护了一份打过补丁的 wgpu-hal 30.0.1，我们 vendored
# 到 packages/lgpu/native/third_party/wgpu-hal 并通过 [patch.crates-io] 使用。
#
# 升级 wgpu 时：版本号必须与 wgpu 主 crate 一致（当前 wgpu = =30.0.1），并确认
#   src/vulkan/instance.rs 里仍有 create_surface_ohos / VK_OHOS_surface。
set -euo pipefail
SRC=${SRC:-/workspace/horizon-ohos/horizon/third_party/wgpu-hal}
DST="$(cd "$(dirname "$0")/.." && pwd)/packages/lgpu/native/third_party/wgpu-hal"
[ -d "$SRC" ] || { echo "[FAIL] 源目录不存在: $SRC"; exit 1; }
rm -rf "$DST"; cp -r "$SRC" "$DST"
ver=$(grep -m1 '^version' "$DST/Cargo.toml" | cut -d'"' -f2)
echo "synced wgpu-hal $ver"
grep -q 'create_surface_ohos' "$DST/src/vulkan/instance.rs" \
  && echo "[PASS] OHOS surface 补丁在位" \
  || { echo "[FAIL] OHOS 补丁丢失"; exit 1; }
