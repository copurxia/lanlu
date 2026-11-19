#!/usr/bin/env bash
# 从 client-next 本体构建 OHOS HAP（src 在构建时复制到本包 target/<app>/，非 fork）。
# 依赖：
#   - cjv 工具链 sts-1.2.0-linux-x64-ohos + stdx 组件（cjv component add stdx --toolchain sts-1.2.0-linux-x64-ohos）
#   - packages/lplatform-ohos/deps/* 的 OHOS shim 与 ohos-stubs 预编译库
#   - packages/lpack-ohos 的 hapgen（ui=sdl3）
set -euo pipefail
# 本脚本属于 packages/lpack-ohos/tools（计划 §4.3）；app 的构建材料在
# packages/lpack-ohos/app-profiles/<app>/。
# 参数：默认构建；--self-check 只校验环境与材料（不构建，可用于本机/CI 预检）
SELF_CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --self-check) SELF_CHECK=1; shift ;;
    --app) LPACK_APP=$2; shift 2 ;;
    --build-dir) CN_OHOS_BUILD=$2; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "未知参数：$1（支持 --self-check / --app NAME / --build-dir DIR）" >&2; exit 2 ;;
  esac
done

HERE=$(cd "$(dirname "$0")" && pwd)          # packages/lpack-ohos/tools
LPACK=$(cd "$HERE/.." && pwd)                # packages/lpack-ohos
APP=${LPACK_APP:-lanlu}                      # 应用名
PROFILE=$LPACK/app-profiles/$APP             # 本应用的构建材料
PKG=$(cd "$LPACK/../.." && pwd)              # 仓库根
CN=$PKG/client-next                          # 引擎
LPLAT=$PKG/packages/lplatform-ohos
. "$LPLAT/deps/common-ohos.sh"                 # 解析 OHOS_CLT / OHOS_SYSROOT / OHOS_RUST 等
NATIVE=$OHOS_NATIVE_SDK
SYSROOT=$OHOS_SYSROOT
# 预编译材料（ohos-stubs、sdl3 prefix）：尚未迁入仓库，M0-7 收尾时改为 lpack-ohos 配置项
RES=${CN_OHOS_RES:-/workspace/lanlu/.research-ohos}
BUILD=${CN_OHOS_BUILD:-$LPACK/target/$APP}
CJV_TOOLCHAINS=${CJV_TOOLCHAINS:-/workspace/.cjv/toolchains}
OH=${CJV_OHOS_TOOLCHAIN:-$CJV_TOOLCHAINS/sts-1.2.0-linux-x64-ohos}
BASE=${CJV_HOST_TOOLCHAIN:-$CJV_TOOLCHAINS/sts-1.2.0}
for d in "$OH" "$BASE"; do
  [ -d "$d" ] || { echo "ERROR: 缺少仓颉工具链 $d（设置 CJV_TOOLCHAINS 或 CJV_OHOS_TOOLCHAIN/CJV_HOST_TOOLCHAIN）" >&2; exit 1; }
done
export TMPDIR=${TMPDIR:-$(dirname "$PKG")/tmp}; mkdir -p "$TMPDIR"
# 中立包 cjpm.toml 的 [target.aarch64-linux-ohos] 段用 ${OHOS_SYSROOT}/${OHOS_STDX}/${OHOS_STUBS}
# 引用这些变量（计划 M0-7：不写死机器路径），由 common-ohos.sh 解析后导出。
export CANGJIE_STDX_PATH=${OHOS_STDX}

# 0) 预编译材料自检（缺失即报错并给出生成命令，避免构建进行到一半才炸）
bash "$HERE/check-prebuilts.sh" > "$TMPDIR/prebuilts.log" 2>&1 || {
  echo "预编译材料不全："; sed 's/^/  /' "$TMPDIR/prebuilts.log"; exit 1;
}

if [ "$SELF_CHECK" = "1" ]; then
  echo "== lpack-ohos 自检（不构建）=="
  echo "  应用 profile : $PROFILE"
  [ -d "$PROFILE" ] || { echo "ERROR: 缺少 profile 目录 $PROFILE" >&2; exit 1; }
  echo "  OHOS SDK     : $NATIVE"
  echo "  sysroot      : $SYSROOT"
  echo "  仓颉工具链   : $OH"
  echo "  宿主工具链   : $BASE"
  echo "  构建目录     : $BUILD"
  echo "  预编译材料   : $RES"
  echo "[PASS] 自检通过（工具链与 profile 就位，预编译材料见上一步）"
  exit 0
fi

# 0.5) LWP 通道库（引擎与壳共用；必须与引擎一起随包）
LWP_OHOS_LIB=${LWP_OHOS_LIB:-$RES/lwp-ohos}
bash "$PKG/packages/lplatform-ohos/deps/lwp/build-ohos.sh" > "$TMPDIR/lwp-build.log" 2>&1 || {
  echo "liblwp_native.so 交叉编译失败："; tail -20 "$TMPDIR/lwp-build.log"; exit 1;
}

# 1) 结构性 shim（源码在 packages/lplatform-ohos/deps，产物进 ohos-stubs / 各包 native 目录）
DEPS=$LPLAT/deps
# vips shim 已下线：lcodec 在 OHOS 直连系统 ImageSource（libimage_source/libpixelmap，
# 随系统提供），不再需要 vips 形状的中间层。AVIF 系统解码器不支持的分支（4:4:4 等）
# 由 lcodec 的 libavif 回退承接（avif_backend.cj，当前未随包时明确跳过）。
"$DEPS/rocksdb/build-ohos.sh" "$PKG/packages/rocksdb_ffi/native/liblanlu_rocksdb_bridge.so"
"$DEPS/libvlc/build-ohos.sh" "$RES/ohos-stubs/libvlc.so"
bash "$DEPS/lgpu/build-ohos.sh"
# lcodec 原生后端（libblur 高斯模糊）：cdylib，随 HAP 打包、运行时 dlopen
bash "$DEPS/lcodec/build-ohos.sh"
"$DEPS/fontkit/build-ohos.sh" "$PKG/packages/fontkit_ffi/native/target/release/libfontkit_native.so"

# 1.5) webview(Blitz) 交叉静态库（需 rust;已构建则就位）
WV="$CN/../packages/webview/native"
if [ -f "$WV/target/aarch64-unknown-linux-ohos/release/libwebview_native.a" ]; then
  cp -f "$WV/target/aarch64-unknown-linux-ohos/release/libwebview_native.a" "$WV/target/release/libwebview_native.a"
  echo "webview .a staged"
fi

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
cp "$PROFILE/cjpm.toml.ohos" "$BUILD/cjpm.toml"
# LWP 库目录由构建脚本注入（模板里只写占位符，仓库不留机器路径）
sed -i "s|@LWP_OHOS_LIB@|$LWP_OHOS_LIB|g" "$BUILD/cjpm.toml"
# 仓库内原生库用 @REPO_ROOT@ 占位：写死绝对路径会让 worktree/CI 检出链接失败。
sed -i "s|@REPO_ROOT@|$PKG|g" "$BUILD/cjpm.toml"

# 2.5) 生成自检内嵌测试视频
if [ -f "$PROFILE/assets/test360.mp4" ]; then
  python3 "$PROFILE/gen_video_cj.py" "$PROFILE/assets/test360.mp4" "$BUILD/src/ohos_selftest_video.cj"
fi

# 2.6) 可选调试种子 KV（CN_OHOS_SEED_FILE=lanlu_kv.bin → src/ohos_seed.cj）
if [ -n "${CN_OHOS_SEED_FILE:-}" ] && [ -f "${CN_OHOS_SEED_FILE}" ]; then
  # 种子属于平台层：lwindow 首次启动时投放，生成到包内而非业务 src
  python3 "$PROFILE/gen_seed_cj.py" "${CN_OHOS_SEED_FILE}" "$CN/../packages/lwindow/src/ohos_seed.cj"
fi

# 2.9) 分层守卫：业务/UI/绑定层不得出现平台专有代码（平台差异归 lwindow/ohos 包）
bash "$CN/../tools/check-layering.sh" || { echo "分层检查未通过，终止构建"; exit 1; }

# 3) 交叉编译引擎（dynamic, @C cj_app_main）
export CANGJIE_HOME=$OH
export LD_LIBRARY_PATH=$BASE/runtime/lib/linux_x86_64_cjnative:$OH/lib/linux_x86_64_cjnative
export PATH=$OH/bin:$BASE/bin:$PATH
(cd "$BUILD" && "$OH/tools/bin/cjpm" build --target aarch64-linux-ohos --skip-script)

# 4) HAP 打包（hapgen, ui=sdl3）
export DEVECO_CLI_CLT_PATH=${DEVECO_CLI_CLT_PATH:-$OHOS_CLT}
export JAVA_HOME=${JAVA_HOME:-$OHOS_JAVA}
[ -d "$JAVA_HOME" ] || { echo "ERROR: 找不到 JDK（设置 JAVA_HOME 或 OHOS_JAVA）" >&2; exit 1; }
# cjv / devecocli 等宿主工具目录（可由 TOOLS_BIN 覆盖）
TOOLS_BIN=${TOOLS_BIN:-/workspace/bin}
export PATH=$JAVA_HOME/bin:$TOOLS_BIN:$PATH
# 平台包（计划 §4.2）：工程模板与生成器在 lpack-ohos，壳源码在 lplatform-ohos。
# 模板暂存：base + 覆盖层，再把 lplatform-ohos/shell 覆盖上去。
# 目的：壳源码只有 lplatform-ohos 一份，lpack-ohos 的模板里不重复存放。
STAGE=$BUILD/.hap-templates
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$LPACK/templates" "$STAGE/base"
cp -a "$LPACK/templates_sdl3" "$STAGE/base_sdl3"
mkdir -p "$STAGE/base_sdl3/entry/src/main/cpp" \
         "$STAGE/base_sdl3/entry/src/main/ets/pages" \
         "$STAGE/base_sdl3/entry/src/main/ets/entryability"
cp -a "$LPLAT/shell/native/." "$STAGE/base_sdl3/entry/src/main/cpp/"
cp -a "$LPLAT/shell/arkts/pages/." "$STAGE/base_sdl3/entry/src/main/ets/pages/"
cp -a "$LPLAT/shell/arkts/entryability/." "$STAGE/base_sdl3/entry/src/main/ets/entryability/"
export OHOS_TEMPLATES=$STAGE/base
export OHOS_ASSETS=$LPACK/assets/default
export OHOS_LIBCXX=$LPACK/assets/libcxx/libc++.so
export OHOS_UI=sdl3
# 应用元数据唯一来源（计划 §4.3）：包名/版本/API/设备/权限/querySchemes
export OHOS_APP_PROFILE=${OHOS_APP_PROFILE:-$LPACK/app-profiles/lanlu/app.toml}
# prefix-nov：同一份 libSDL3，但 SONAME 被改短为 "libSDL3.so"，让壳(libmain)与引擎/ttf
# 依赖同一个名字，进程里只加载一份 SDL3（双实例会导致钩子/事件队列错位、push 恒失败）。
export OHOS_LGPU_LIB=$CN/../packages/lgpu/native/target/release/liblgpu_native.a
# 壳侧 lwp_client.c 需要生成的协议头（计划 §5.1）
export OHOS_LWP_INCLUDE=$PKG/packages/lwp/include
export OHOS_SDL3_PREFIX=$RES/sdl3-ohos/prefix-nov
ST=$RES/ohos-stubs
PFX=$RES/sdl3-ohos/prefix-single/lib
PK=$CN/../packages
ENG=$BUILD/target/aarch64-linux-ohos/release/lanlu_client_next
export OHOS_STRIP=$NATIVE/llvm/bin/llvm-strip
export OHOS_EXTRA_LIBS="$ST:$ST/ffmpeg:$PFX:$PK/webview/native/target/release:$PK/rocksdb_ffi/native:$PK/libavformat_ffi/native:$PK/libass_ffi/native:$PK/fontkit_ffi/native/target/release:$PK/lcodec/native/target/ohos:$ENG:$LWP_OHOS_LIB"
ps aux | grep -iE 'hvigor|daemon-process-boot-script' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true
true
# 不动 .hvigor（守护进程持有 FUSE 句柄），只清生成物
find "$BUILD/target/ohos/hap" -mindepth 1 -maxdepth 1 ! -name '.hvigor' -exec rm -rf {} + 2>/dev/null || true
rm -rf "$BUILD/target/ohos/hap/entry/.cxx" 2>/dev/null || true
# 4.4) vips shim 残留清理：lcodec 已直连系统 ImageSource，HAP 不再带 libvips.so。
rm -f "$RES/ohos-stubs/libvips.so" 2>/dev/null || true
# 4.5) 瘦身：strip 源库调试信息（hapgen 复制时带入 HAP）
for d in "$ST" "$ST/ffmpeg" "$PFX" "$PK/webview/native/target/release" "$PK/rocksdb_ffi/native" "$PK/libavformat_ffi/native" "$PK/libass_ffi/native" "$PK/fontkit_ffi/native/target/release" "$ENG"; do
  find "$d" -maxdepth 1 -name '*.so*' -type f -exec "$NATIVE/llvm/bin/llvm-strip" --strip-debug {} \; 2>/dev/null || true
done
HAPGEN=$LPACK/target/release/bin/main
[ -x "$HAPGEN" ] || { echo "缺少 hapgen：先运行 packages/lpack-ohos/tools/build-hapgen.sh"; exit 1; }
# 签名只走一条路径：hapgen 只生成工程与 HAP（devecocli signature generate 会向 AGC 申请
# provision，配额耗尽时**无限挂起**——2026-11-15 实测卡死 10 分钟以上）。签名由 sign-hap.sh
# 复用本机已有材料完成（tools/sign-hap.sh），两条路径同时签名还会互相覆盖 hvigor 配置。
(cd "$BUILD" && "$HAPGEN" gen)

HAP_OUT="$BUILD/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap"
echo "HAP: $HAP_OUT"

# 5) 静态验证门禁（分层 / 依赖闭包 / 关键符号）——失败即构建失败
if [ "${CN_OHOS_SKIP_VERIFY:-0}" != "1" ]; then
  # hapgen 阶段通常产出 unsigned（签名在 tools/sign-reuse 那步），两者任选其一
  GATE_HAP="$HAP_OUT"
  [ -f "$GATE_HAP" ] || GATE_HAP="$BUILD/target/ohos/hap/entry/build/default/outputs/default/entry-default-unsigned.hap"
  CN="$CN" bash "$CN/../packages/lpack-ohos/tools/verify-ohos.sh" "$GATE_HAP" || { echo "[FAIL] 静态验证未通过"; exit 1; }
fi
