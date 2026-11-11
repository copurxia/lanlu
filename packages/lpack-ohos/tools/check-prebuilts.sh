#!/usr/bin/env bash
# 校验“预编译材料目录”（RES）是否齐全，并告诉你每个缺失项该用哪个脚本生成。
#
# 为什么不做成入库的二进制：RES 里是第三方库的**交叉编译产物**（约 70MB，含 SDL3 61MB），
# 属于构建输出而非源码。计划 §4.7 的决定是：不 vendored 进 git，而是
#   1) 由脚本可重复生成；
#   2) 构建前用本脚本校验，缺失即报错并给出生成命令。
# M6 删除 SDL 后，`sdl3-ohos` 一组条目随之消失（只留 ohos-stubs）。
#
# 用法：bash packages/lpack-ohos/tools/check-prebuilts.sh
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

missing=0
check() {
  local path=$1 fix=$2 what=$3
  if [ -e "$RES/$path" ]; then
    echo "  [ok] $what"
  else
    echo "  [MISSING] $what -> $RES/$path"
    echo "            生成：$fix"
    missing=$((missing + 1))
  fi
}

echo "== 预编译材料目录：$RES"
echo "   （CN_OHOS_RES 可覆盖）"

# ohos-stubs：系统库的 OHOS 交叉编译结果 + 我们自己的 stub
check ohos-stubs/libass.so.9        "见 docs/ohos-port.md「依赖」一节（libass 交叉编译）" "libass（字幕排版）"
check ohos-stubs/libfreetype.so.6   "见 docs/ohos-port.md（freetype/fontconfig/harfbuzz 链）" "freetype"
check ohos-stubs/libfontconfig.so.1 "见 docs/ohos-port.md" "fontconfig"
check ohos-stubs/libharfbuzz.so.0   "见 docs/ohos-port.md" "harfbuzz"
check ohos-stubs/libfribidi.so.0    "见 docs/ohos-port.md" "fribidi"
check ohos-stubs/librocksdb.so      "见 docs/ohos-port.md（rocksdb 交叉编译）" "rocksdb"
check ohos-stubs/libvips.so         "bash packages/lplatform-ohos/deps/vips/build-ohos.sh $RES/ohos-stubs/libvips.so" "vips（图片）"
check ohos-stubs/libvlc.so          "bash packages/lplatform-ohos/deps/libvlc/build-ohos.sh $RES/ohos-stubs/libvlc.so" "vlc shim（媒体）"
check ohos-stubs/ffmpeg/libavcodec.so.61 "bash packages/lpack-ohos/tools/build-ffmpeg-ohos.sh" "ffmpeg（编解码）"
check ohos-stubs/ffmpeg/libavformat.so.61 "bash packages/lpack-ohos/tools/build-ffmpeg-ohos.sh" "ffmpeg（容器）"
check ohos-stubs/ffmpeg/libavutil.so.59   "bash packages/lpack-ohos/tools/build-ffmpeg-ohos.sh" "ffmpeg（工具库）"

# SDL3（M6 删除）：现在引擎/壳仍链接
if [ -d "$RES/sdl3-ohos" ]; then
  check sdl3-ohos/prefix-single/lib/libSDL3.so.0.5.0 "bash packages/lpack-ohos/tools/make-sdl3-noversion.sh（需先有 prefix-single）" "SDL3（过渡期）"
  check sdl3-ohos/prefix-nov/lib/libSDL3.so "bash packages/lpack-ohos/tools/make-sdl3-noversion.sh" "SDL3 SONAME 归一化"
else
  echo "  [skip] 没有 sdl3-ohos（M6 删 SDL 后正常）"
fi

echo
if [ "$missing" -eq 0 ]; then
  echo "[PASS] 预编译材料齐全"
  exit 0
fi
echo "[FAIL] 缺少 $missing 项预编译材料（见上面的生成命令）"
exit 1
