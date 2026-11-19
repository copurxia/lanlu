#!/usr/bin/env bash
# 构建 HAP 打包器 hapgen（host 可执行文件）。源码在 packages/lpack-ohos（计划 §4.3）。
#
# 关键点（踩过的坑）：必须用 **host 工具链** $BASE=/workspace/.cjv/toolchains/sts-1.2.0，
# 不能用交叉工具链 sts-1.2.0-linux-x64-ohos —— 后者产出的二进制在运行时加载 host
# runtime 会断言失败（itfVExtensionDataStart is nullptr / SIGABRT）。
set -euo pipefail
BASE=${CJV_HOST_TOOLCHAIN:-/workspace/.cjv/toolchains/sts-1.2.0}
PKG=${PKG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}   # 本脚本已在本包 tools/ 下
cd "$PKG"
# 只清宿主工具链产物；target/<app>/ 是应用打包工作区（tools/build-ohos.sh 生成），
# 不能整目录删除，否则重建 hapgen 会把应用工程一起抹掉。
rm -rf target/release target/debug target/.dep-cache target/.cjpm-history
export CANGJIE_HOME="$BASE"
export LD_LIBRARY_PATH="$BASE/runtime/lib/linux_x86_64_cjnative:$BASE/lib/linux_x86_64_cjnative"
export PATH="$BASE/bin:${TOOLS_BIN:-/workspace/bin}:$PATH"
export TMPDIR=${TMPDIR:-/tmp}
"$BASE/tools/bin/cjpm" build
ls -l target/release/bin/main
