#!/usr/bin/env bash
# 交叉编译 libavif（+ dav1d）供 lcodec 的 AVIF 回退使用，产物直接落到 ohos-stubs/
# （build-ohos.sh 会把 ohos-stubs/*.so* 打进 HAP）。
#
# 为什么需要它们：系统 ImageSource 的 AvifDecoderImpl 只认 4:2:0 布局，
# 服务端若给出 4:4:4 / 12-bit 的 AVIF 封面会解不出来（真机日志
# "IsSupportedPixelFormat unsupported layout : 3"）。这一层是兜底。
#
# 依赖：meson 不在本机 PATH 里 —— 脚本会自动从 PyPI 拉 wheel 解压到
#   $RES/tools/meson（纯 Python，无需安装）。
# 用法：bash packages/lplatform-ohos/deps/avif/build-ohos.sh [--clean]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common-ohos.sh"

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RES=${CN_OHOS_RES:-/workspace/lanlu/.research-ohos}
SRC=$RES/avif-src
PREFIX=$SRC/prefix
STUBS=${OHOS_STUBS:-$RES/ohos-stubs}
CMAKE_BIN=$OHOS_NATIVE_SDK/build-tools/cmake/bin
DAV1D_VER=1.4.3
AVIF_VER=1.1.1

CLEAN=0
[ "${1:-}" = "--clean" ] && CLEAN=1

mkdir -p "$SRC" "$STUBS"

# ── 0) 工具：cmake/ninja 用 SDK 自带；meson 用 pip wheel 解压 ──────────────
export PATH="$CMAKE_BIN:$PATH"
NINJA=$CMAKE_BIN/ninja

if ! python3 -c "import sys; sys.path.insert(0,'$RES/tools/meson'); import mesonbuild" 2>/dev/null; then
  echo "== 准备 meson（PyPI wheel，仅解压不安装）=="
  mkdir -p "$RES/tools/meson"
  WHL=$SRC/meson.whl
  [ -f "$WHL" ] || curl -sSL --max-time 60 -o "$WHL" \
    "https://files.pythonhosted.org/packages/py3/m/meson/meson-1.5.2-py3-none-any.whl"
  ( cd "$RES/tools/meson" && python3 -c "import zipfile;zipfile.ZipFile('$WHL').extractall('.')" )
fi
cat > "$RES/tools/meson/meson.py" <<'PY'
import sys
sys.path.insert(0, '/workspace/lanlu/.research-ohos/tools/meson')
from mesonbuild import mesonmain
sys.exit(mesonmain.main())
PY
MESON="python3 $RES/tools/meson/meson.py"

# ── 1) 源码（缓存在 $SRC，缺失才下载）────────────────────────────────────
[ -d "$SRC/dav1d-$DAV1D_VER" ] || {
  [ -f "$SRC/dav1d.tar.gz" ] || curl -sSL --max-time 120 -o "$SRC/dav1d.tar.gz" \
    "https://github.com/videolan/dav1d/archive/refs/tags/$DAV1D_VER.tar.gz"
  tar xzf "$SRC/dav1d.tar.gz" -C "$SRC"
}
[ -d "$SRC/libavif-$AVIF_VER" ] || {
  [ -f "$SRC/libavif.tar.gz" ] || curl -sSL --max-time 120 -o "$SRC/libavif.tar.gz" \
    "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$AVIF_VER.tar.gz"
  tar xzf "$SRC/libavif.tar.gz" -C "$SRC"
}

# ── 2) 交叉文件（meson）─────────────────────────────────────────────────
cat > "$SRC/ohos-cross.txt" <<EOF
[binaries]
c = '$OHOS_LLVM_BIN/clang'
cpp = '$OHOS_LLVM_BIN/clang++'
ar = '$OHOS_LLVM_BIN/llvm-ar'
strip = '$OHOS_LLVM_BIN/llvm-strip'
pkg-config = '/usr/bin/pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_args = ['--target=aarch64-linux-ohos', '--sysroot=$OHOS_SYSROOT', '-O2', '-fPIC']
c_link_args = ['--target=aarch64-linux-ohos', '--sysroot=$OHOS_SYSROOT']
EOF

# ── 3) dav1d ────────────────────────────────────────────────────────────
cd "$SRC/dav1d-$DAV1D_VER"
if [ "$CLEAN" = "1" ]; then rm -rf build; fi
[ -d build ] || $MESON setup build --cross-file "$SRC/ohos-cross.txt" \
  -Ddefault_library=shared -Denable_tests=false -Denable_tools=false \
  -Denable_examples=false -Dbitdepths=8,16
$NINJA -C build
DESTDIR="$PREFIX" $MESON install -C build >/dev/null
echo "== dav1d: $PREFIX/usr/local/lib/libdav1d.so =="

# ── 4) libavif（dav1d 走 pkg-config 发现）───────────────────────────────
cd "$SRC/libavif-$AVIF_VER"
if [ "$CLEAN" = "1" ]; then rm -rf build; fi
export PKG_CONFIG_PATH="$PREFIX/usr/local/lib/pkgconfig"
CMAKE=cmake
"$CMAKE" -S . -B build -G Ninja \
  -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="$OHOS_LLVM_BIN/clang" -DCMAKE_AR="$OHOS_LLVM_BIN/llvm-ar" \
  -DCMAKE_SYSROOT="$OHOS_SYSROOT" \
  -DCMAKE_C_FLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT -O2 -fPIC -I$PREFIX/usr/local/include" \
  -DCMAKE_SHARED_LINKER_FLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX/usr/local" \
  -DBUILD_SHARED_LIBS=ON -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF \
  -DAVIF_ENABLE_WERROR=OFF -DAVIF_CODEC_DAV1D=SYSTEM -DAVIF_LIBYUV=OFF >/dev/null
$NINJA -C build
AVIF_SO=$(ls build/libavif.so.* | grep -vE '\.so\.(16)$' | head -1)

# ── 5) 产物落到 stubs（文件名按 SONAME 归一，hapgen 仍会再归一一次）─────
cp -f "$AVIF_SO" "$STUBS/libavif.so.16.1.1"
cp -f "$PREFIX/usr/local/lib/libdav1d.so.7.0.0" "$STUBS/libdav1d.so.7.0.0"
"$OHOS_LLVM_BIN/llvm-strip" --strip-unneeded "$STUBS/libavif.so.16.1.1" "$STUBS/libdav1d.so.7.0.0" 2>/dev/null || true
ls -l "$STUBS/libavif.so.16.1.1" "$STUBS/libdav1d.so.7.0.0" | awk '{print "staged", $5, $9}'
