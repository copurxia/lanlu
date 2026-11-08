#!/usr/bin/env bash
# 从 client-next 本体构建 OHOS HAP（src 在构建时复制到 build/ohos，非 fork）。
# 依赖：
#   - cjv 工具链 sts-1.2.0-linux-x64-ohos + stdx 组件（cjv component add stdx --toolchain sts-1.2.0-linux-x64-ohos）
#   - packages/* 的 OHOS shim（native-ohos/*/build-ohos.sh）与 ohos-stubs 预编译库
#   - packages/ohos 的 hapgen（ui=sdl3）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)          # client-next/ohos
CN=$(cd "$HERE/.." && pwd)                   # client-next
RES=${CN_OHOS_RES:-/workspace/lanlu/.research-ohos}
NATIVE=${OHOS_NATIVE:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/native}
BUILD=${CN_OHOS_BUILD:-$CN/build/ohos}
OH=/workspace/.cjv/toolchains/sts-1.2.0-linux-x64-ohos
BASE=/workspace/.cjv/toolchains/sts-1.2.0
SYSROOT=/workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot
export TMPDIR=/workspace/tmp; mkdir -p "$TMPDIR"

# 1) 结构性 shim（源码在 packages/*/native-ohos，产物进 ohos-stubs / 各包 native 目录）
"$CN/../packages/vips_ffi/native-ohos/build-ohos.sh" "$RES/ohos-stubs/libvips.so"
"$CN/../packages/rocksdb_ffi/native-ohos/build-ohos.sh" "$CN/../packages/rocksdb_ffi/native/liblanlu_rocksdb_bridge.so"
"$CN/../packages/libvlc_ffi/native-ohos/build-ohos.sh" "$RES/ohos-stubs/libvlc.so"
"$CN/../packages/fontkit_ffi/native-ohos/build-ohos.sh" "$CN/../packages/fontkit_ffi/native/target/release/libfontkit_native.so"

# 2) 构建目录：复制 src + 载入 OHOS cjpm 配置（临时产物，可随时删）
# .hvigor 由 hvigor 守护进程持有（FUSE 句柄），整体删除会失败：只清生成物
find "$BUILD" -mindepth 1 -maxdepth 1 ! -name '.hvigor' -exec rm -rf {} + 2>/dev/null || true
mkdir -p "$BUILD"
cp -r "$CN/src" "$BUILD/src"
# build.cj 的内嵌 logo 产物（--skip-script 下需预生成）
python3 - "$CN" "$BUILD/src" <<'PYEOF'
import sys, os
cn, src = sys.argv[1], sys.argv[2]
png = open(os.path.join(cn, "assets/lanlu_logo_gold.png"), "rb").read()
out = os.path.join(src, "ui/embedded_logo.cj")
with open(out, "w") as f:
    f.write("package lanlu_client_next.ui\n\n// generated from assets/lanlu_logo_gold.png\n")
    f.write("public let EMBEDDED_LOGO_PNG: Array<UInt8> = [\n")
    for i in range(0, len(png), 16):
        f.write("    " + ", ".join("0x%02Xu8" % b for b in png[i:i+16]) + ",\n")
    f.write("]\n")
print("embedded_logo.cj:", len(png), "bytes")
PYEOF
cp "$HERE/cjpm.toml.ohos" "$BUILD/cjpm.toml"

# 2.5) 生成自检内嵌测试视频
if [ -f "$HERE/assets/test360.mp4" ]; then
  python3 "$HERE/gen_video_cj.py" "$HERE/assets/test360.mp4" "$BUILD/src/ohos_selftest_video.cj"
fi

# 3) 交叉编译引擎（dynamic, @C cj_app_main）
export CANGJIE_HOME=$OH
export LD_LIBRARY_PATH=$BASE/runtime/lib/linux_x86_64_cjnative:$OH/lib/linux_x86_64_cjnative
export PATH=$OH/bin:$BASE/bin:$PATH
(cd "$BUILD" && "$OH/tools/bin/cjpm" build --target aarch64-linux-ohos --skip-script)

# 4) HAP 打包（hapgen, ui=sdl3）
export DEVECO_CLI_CLT_PATH=${DEVECO_CLI_CLT_PATH:-$RES/tools/clt-7.0/command-line-tools}
export JAVA_HOME=${JAVA_HOME:-/workspace/horizon-ohos/.tooling/jdk17}
export PATH=$JAVA_HOME/bin:/workspace/bin:$PATH
export OHOS_TEMPLATES=$RES/packages/ohos/templates
export OHOS_ASSETS=$RES/packages/ohos/assets/default
export OHOS_LIBCXX=$RES/packages/ohos/assets/libcxx/libc++.so
export OHOS_UI=sdl3
export OHOS_SDL3_PREFIX=$RES/sdl3-ohos/prefix-single
ST=$RES/ohos-stubs
PFX=$RES/sdl3-ohos/prefix-single/lib
PK=$CN/../packages
ENG=$BUILD/target/aarch64-linux-ohos/release/lanlu_client_next
export OHOS_EXTRA_LIBS="$ST:$ST/ffmpeg:$PFX:$PK/webview/native/target/release:$PK/rocksdb_ffi/native:$PK/libavformat_ffi/native:$PK/libass_ffi/native:$PK/fontkit_ffi/native/target/release:$ENG"
ps aux | grep -iE 'hvigor|daemon-process-boot-script' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
# 不动 .hvigor（守护进程持有 FUSE 句柄），只清生成物
find "$BUILD/target/ohos/hap" -mindepth 1 -maxdepth 1 ! -name '.hvigor' -exec rm -rf {} + 2>/dev/null || true
rm -rf "$BUILD/target/ohos/hap/entry/.cxx" 2>/dev/null || true
# 4.5) 瘦身：strip 源库调试信息（hapgen 复制时带入 HAP）
for d in "$ST" "$ST/ffmpeg" "$PFX" "$PK/webview/native/target/release" "$PK/rocksdb_ffi/native" "$PK/libavformat_ffi/native" "$PK/libass_ffi/native" "$PK/fontkit_ffi/native/target/release" "$ENG"; do
  find "$d" -maxdepth 1 -name '*.so*' -type f -exec "$NATIVE/llvm/bin/llvm-strip" --strip-debug {} \; 2>/dev/null || true
done
(cd "$BUILD" && "$RES/packages/ohos/target/release/bin/main" gen --sign)
echo "HAP: $BUILD/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap"
