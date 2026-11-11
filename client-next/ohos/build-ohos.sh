#!/usr/bin/env bash
# 兼容入口：构建逻辑已迁至 packages/lpack-ohos/tools/build-ohos.sh（计划 §4.3）。
# 主仓不再存放鸿蒙构建配置；应用材料在 packages/lpack-ohos/app-profiles/<app>/。
#
# 保留本文件是为了不破坏既有脚本/文档里的 `bash client-next/ohos/build-ohos.sh` 调用。
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$HERE/../../packages/lpack-ohos/tools/build-ohos.sh" "$@"
