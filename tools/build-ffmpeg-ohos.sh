#!/usr/bin/env bash
# 为 OHOS(aarch64) 交叉编译 libavformat/libavcodec/libavutil/libswscale/libswresample。
#
# 背景：client-next 的播放链路（libvlc_ffi/native-ohos/vlc_shim.c）直接用 libav*，
# 解码能力完全取决于本脚本的 decoder 列表。曾因漏掉 PCM 解码器导致 WAV/PCM 音轨
# 无法播放（真机验证：avcodec_find_decoder(pcm_s16le) 返回 NULL）。
#
# 用法：bash tools/build-ffmpeg-ohos.sh [源码目录] [安装前缀]
#   默认源码 /workspace/tmp/ffsrc，前缀 /workspace/tmp/ffprefix
set -euo pipefail
SRC=${1:-/workspace/tmp/ffsrc}
PREFIX=${2:-/workspace/tmp/ffprefix}
CLT=/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony
CC=$CLT/native/llvm/bin/clang
SYSROOT=${OHOS_SYSROOT:-/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot}
export TMPDIR=/workspace/tmp
JOBS=${JOBS:-$(nproc)}

[ -d "$SRC" ] || { echo "缺少 ffmpeg 源码目录: $SRC"; exit 1; }

cd "$SRC"
make distclean >/dev/null 2>&1 || true

CFLAGS="--target=aarch64-linux-ohos --sysroot=$SYSROOT -fPIC -O2"
LDFLAGS="--target=aarch64-linux-ohos --sysroot=$SYSROOT"

./configure \
  --target-os=linux --arch=aarch64 --cpu=armv8-a \
  --enable-cross-compile --cc="$CC" --sysroot="$SYSROOT" \
  --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS" \
  --prefix="$PREFIX" \
  --disable-all --disable-programs --disable-doc --disable-everything --disable-stripping \
  --enable-avformat --enable-avcodec --enable-avutil --enable-swresample --enable-swscale \
  --disable-vulkan --disable-vaapi --disable-vdpau --disable-cuda --disable-cuvid --disable-nvenc \
  --enable-demuxer='matroska,mp4,mov,ogg,wav,flac,mp3,aac,avi,mpegts' \
  --enable-muxer=null \
  --enable-decoder='h264,hevc,vp8,vp9,opus,aac,flac,vorbis,mpegaudio,mp3,\
pcm_s16le,pcm_s16be,pcm_u8,pcm_s24le,pcm_s32le,pcm_f32le,pcm_f32be,pcm_alaw,pcm_mulaw,\
ass,ssa,srt,subrip,webvtt,mov_text' \
  --enable-parser='h264,hevc,vp8,vp9,opus,aac,flac,vorbis,mpegaudio,ass' \
  --enable-protocol='file,http,tcp' \
  --enable-shared --disable-static

make -j"$JOBS"
make install
echo "[build-ffmpeg-ohos] 完成：$PREFIX/lib"
ls -1 "$PREFIX"/lib/libav*.so.* | head -8
