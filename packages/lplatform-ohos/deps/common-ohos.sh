#!/usr/bin/env bash
# 鸿蒙交叉编译工具链解析（被 deps/*/build-ohos.sh 与 deps/lgpu/build-ohos.sh source）。
#
# 计划 §4.2：平台路径与工具链位置只允许出现在平台包内，且不得写死机器路径。
# 解析顺序：环境变量 → 已知默认位置 → 报错退出。
#
#   OHOS_CLT        命令行工具根（含 sdk/default/openharmony）
#   OHOS_CLANG      clang 可执行文件
#   OHOS_SYSROOT    openharmony native sysroot
#   OHOS_LLVM_BIN   llvm 工具目录（llvm-strip / llvm-nm / llvm-readelf）
#   OHOS_RUST       Rust 工具链（含 aarch64-unknown-linux-ohos std）
#   OHOS_CARGO_HOME 离线 registry 所在的 CARGO_HOME
#   FFMPEG_SRC / FFMPEG_LIB_DIR  libvlc shim 需要的 ffmpeg 头与库

set -euo pipefail

_lp_first_dir() {
  local d
  for d in "$@"; do
    [ -n "$d" ] && [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

# 命令行工具根：OHOS_CLT / DEVECO_SDK_HOME 的上级，或已知安装位置
if [ -z "${OHOS_CLT:-}" ]; then
  if [ -n "${DEVECO_SDK_HOME:-}" ]; then
    OHOS_CLT=$(cd "$DEVECO_SDK_HOME/.." 2>/dev/null && pwd) || true
  fi
fi
if [ -z "${OHOS_CLT:-}" ]; then
  OHOS_CLT=$(_lp_first_dir \
    /workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools \
    /workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools) || {
    echo "ERROR: 找不到 OHOS 命令行工具；请设置 OHOS_CLT 指向 command-line-tools 根目录" >&2
    exit 1
  }
fi
export OHOS_CLT

OHOS_NATIVE_SDK=${OHOS_NATIVE_SDK:-$OHOS_CLT/sdk/default/openharmony/native}
export OHOS_NATIVE_SDK

export OHOS_CLANG=${OHOS_CLANG:-$OHOS_NATIVE_SDK/llvm/bin/clang}
export OHOS_LLVM_BIN=${OHOS_LLVM_BIN:-$OHOS_NATIVE_SDK/llvm/bin}

if [ -z "${OHOS_SYSROOT:-}" ]; then
  OHOS_SYSROOT=$(_lp_first_dir \
    "$OHOS_NATIVE_SDK/sysroot" \
    /workspace/horizon-ohos/.tooling/sdk26/clt/command-line-tools/sdk/default/openharmony/native/sysroot) || {
    echo "ERROR: 找不到 openharmony native sysroot；请设置 OHOS_SYSROOT" >&2
    exit 1
  }
fi
export OHOS_SYSROOT

export OHOS_RUST=${OHOS_RUST:-$( _lp_first_dir /workspace/horizon-ohos/.tooling/rust190 || true )}
export OHOS_JAVA=${OHOS_JAVA:-$( _lp_first_dir \
  /workspace/horizon-ohos/.tooling/jdk17 \
  /usr/lib/jvm/java-17-openjdk-amd64 \
  /usr/lib/jvm/java-21-openjdk-amd64 || true )}
export OHOS_CARGO_HOME=${OHOS_CARGO_HOME:-/workspace/.cargo}

# cjpm [target.aarch64-linux-ohos] 段用 ${VAR} 引用以下变量（不写死机器路径）：
export OHOS_STDX=${OHOS_STDX:-$( _lp_first_dir \
  /workspace/.cjv/stdx/sts-1.2.0-linux-x64-ohos/static \
  "$(dirname "$(dirname "$OHOS_CLT")")"/stdx/sts-1.2.0-linux-x64-ohos/static || true )}
export OHOS_STUBS=${OHOS_STUBS:-$( _lp_first_dir \
  /workspace/lanlu/.research-ohos/ohos-stubs || true )}

for tool in "$OHOS_CLANG"; do
  [ -x "$tool" ] || { echo "ERROR: 缺少工具 $tool" >&2; exit 1; }
done
