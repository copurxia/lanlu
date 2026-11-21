#!/usr/bin/env bash
# 图片解码归属守卫（"只有一个解码器"闸门）。
#
# 背景（2026-11-17）：lgui 曾把图片当 PNG 交给 lgpu 的 Rust `png` crate 解码
# （Renderer.uploadTexturePng → lgpu_texture_create_from_png），形成与 lcodec 并行的
# 第二条解码路径：只认 PNG、纹理宽高恒为 0×0（ImageView 算出空矩形 → 顶栏/登录卡
# logo 静默消失）、失败完全无声。清理后约定：
#
#   1. 解码只能发生在 packages/lcodec（设备：系统 ImageSource；桌面：系统 libvips）；
#   2. cui / lgui / lgpu 只能调用 lcodec，或接收已经解好的 RGBA 像素；
#   3. 渲染器（lgpu，含 Rust native）不得引入图片解码 crate；
#   4. 解码入口不得被"优化"掉（正向断言）。
#
# 用法：bash tools/check-image-decode.sh [--verbose]
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERBOSE="${1:-}"
fail=0

# 冻结快照 / 生成物 / 历史副本不参与判定。
EXCLUDE_RE='/target/|/\.agents/|/lcodec-rehearsal/|/cangjie-gui-p0/|build-script-cache'

# 去掉注释行（//、*、/* 开头）——注释里提到旧符号名是允许的（历史说明）。
strip_comments() {
  awk -F: '{
    code = $0
    sub(/^([^:]*:){2}/, "", code)       # 去掉 file:line: 前缀
    trimmed = code
    sub(/^[[:space:]]+/, "", trimmed)
    if (trimmed ~ /^(\/\/|\*|\/\*)/) next
    print
  }'
}

report() {
  fail=$((fail+1))
  echo "[IMG-DECODE] $1"
}

# 1) 已删除的"后端解 PNG"接口不得复活（Cangjie 与 Rust 两侧都查）。
while IFS= read -r hit; do
  [ -z "$hit" ] || report "${hit#$ROOT/} —— 后端不再提供 PNG 字节解码（解码归 lcodec）"
done < <(grep -rnE '\b(uploadTexturePng|loadTexturePngFromMemory|createTextureFromPng|lgpu_texture_create_from_png|texturePngSink)\b' \
  "$ROOT/packages" "$ROOT/apps/desktop" --include='*.cj' --include='*.rs' 2>/dev/null \
  | grep -Ev "$EXCLUDE_RE" | strip_comments)

# 2) 框架层不得自己打开图片解码库（只允许 lcodec 内部做）。
for d in "$ROOT/packages/cangjie-gui/src" "$ROOT/packages/lgpu/src"; do
  [ -d "$d" ] || continue
  while IFS= read -r hit; do
    [ -z "$hit" ] || report "${hit#$ROOT/} —— 框架层不得直接解码图片（应经 lcodec）"
  done < <(grep -rnE 'import (vips_ffi|vips)|foreign func .*\b(vips_|stbi_)' "$d" --include='*.cj' 2>/dev/null \
    | grep -Ev "$EXCLUDE_RE" | strip_comments)
done

# 3) 渲染器 Rust 侧不得依赖图片解码 crate。
CARGO="$ROOT/packages/lgpu/native/Cargo.toml"
if [ -f "$CARGO" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] || report "${CARGO#$ROOT/}:$hit —— 渲染器不得引入图片解码 crate（解码归 lcodec）"
  done < <(grep -nE '^(png|image|stb_image|jpeg-decoder|zune-inflate)[[:space:]]*=' "$CARGO" 2>/dev/null)
fi

# 4) 正向断言：唯一解码入口必须存在（避免"删干净了却没人解码"）。
DECODE="$ROOT/packages/lcodec/src/decode.cj"
grep -q 'public func decodeFileToRgba' "$DECODE" 2>/dev/null ||
  report "${DECODE#$ROOT/} —— 缺少 decodeFileToRgba（文件解码入口）"
grep -qE 'public func decodeBytes[A-Za-z]*' "$DECODE" 2>/dev/null ||
  report "${DECODE#$ROOT/} —— 缺少内存字节解码入口（内嵌资源用）"

if [ "$fail" -eq 0 ]; then
  echo "[PASS] 图片解码唯一入口 = lcodec（框架层与渲染器无自带解码器）"
  exit 0
fi
echo "[FAIL] 发现 $fail 处越界解码（解码只能发生在 packages/lcodec）"
exit 1
