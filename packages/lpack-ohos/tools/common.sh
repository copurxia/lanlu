#!/usr/bin/env bash
# lpack-ohos 工具脚本的公共定位逻辑（source 本文件，不要执行）。
#
# 计划 §4.2：鸿蒙相关的构建/打包/门禁脚本属于平台包，路径解析集中在这里，
# 脚本里不写死机器路径。工具链位置由 lplatform-ohos/deps/common-ohos.sh 统一解析。
#
# 提供：
#   REPO_ROOT   仓库根（含 apps/desktop/ 与 packages/）
#   LPACK_DIR   本包根（packages/lpack-ohos）
#   HAP_OUT     HAP 输出目录
#   CN_BUILD    引擎构建目录（packages/lpack-ohos/target/<app>）

# shellcheck shell=bash

_TOOLS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LPACK_DIR=$(cd -- "$_TOOLS_DIR/.." && pwd)
REPO_ROOT=$(cd -- "$LPACK_DIR/../.." && pwd)
export REPO_ROOT LPACK_DIR

# 工具链（clang/sysroot/rust/JDK/CLT/stdx/stubs）
# shellcheck source=/dev/null
. "$REPO_ROOT/packages/lplatform-ohos/deps/common-ohos.sh"

# 临时目录：HAP 解包要 >100MB，而容器 /tmp 常是 512M tmpfs（曾因此构建中途 ENOSPC）。
# 默认放在仓库同级的 tmp/ 下；TMPDIR 显式设置时以调用方为准。
TMP_ROOT=${TMP_ROOT:-$(dirname "$REPO_ROOT")/tmp}
mkdir -p "$TMP_ROOT" 2>/dev/null || true
export TMPDIR=${TMPDIR:-$TMP_ROOT}

CN_BUILD=${CN_BUILD:-$LPACK_DIR/target/${LPACK_APP:-lanlu}}
export CN_BUILD
HAP_OUT=${HAP_OUT:-$CN_BUILD/target/ohos/hap/entry/build/default/outputs/default}
export HAP_OUT

# 预编译材料（ohos-stubs、sdl3 prefix）：仍是仓外目录，M0-7 收尾时决定去向
RES=${CN_OHOS_RES:-/workspace/lanlu/.research-ohos}
export RES

# 找到要检查的 HAP：优先签名版
find_hap() {
  local cand
  for cand in "$HAP_OUT/entry-default-signed.hap" "$HAP_OUT/entry-default-unsigned.hap"; do
    [ -f "$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}
