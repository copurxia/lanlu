#!/usr/bin/env bash
# 构建 HAP 打包器 hapgen（host 可执行文件）。
#
# 关键点（踩过的坑）：必须用 **host 工具链** $BASE=/workspace/.cjv/toolchains/sts-1.2.0，
# 不能用交叉工具链 sts-1.2.0-linux-x64-ohos —— 后者产出的二进制在运行时加载 host
# runtime 会断言失败（itfVExtensionDataStart is nullptr / SIGABRT）。
set -euo pipefail
BASE=${BASE:-/workspace/.cjv/toolchains/sts-1.2.0}
PKG=${PKG:-/workspace/lanlu/.research-ohos/packages/ohos}
cd "$PKG"
rm -rf target cjpm.lock
export CANGJIE_HOME="$BASE"
export LD_LIBRARY_PATH="$BASE/runtime/lib/linux_x86_64_cjnative:$BASE/lib/linux_x86_64_cjnative"
export PATH="$BASE/bin:/workspace/bin:$PATH"
export TMPDIR=${TMPDIR:-/workspace/tmp}
"$BASE/tools/bin/cjpm" build
ls -l target/release/bin/main
