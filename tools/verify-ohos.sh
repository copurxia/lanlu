#!/usr/bin/env bash
# OHOS 移植静态验证（无需设备）：分层守卫 + HAP 依赖闭包 + 关键符号导出。
# 用法: bash tools/verify-ohos.sh [<signed.hap>]
set -uo pipefail
cd "$(dirname "$0")/.."
HAP="${1:-client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap}"
fail=0

echo "== 1/3 分层守卫 =="
bash tools/check-layering.sh || fail=1

echo "== 2/3 HAP 依赖闭包 =="
bash tools/check-hap-deps.sh "$HAP" || fail=1

echo "== 3/3 关键符号导出 =="
bash tools/check-hap-symbols.sh "$HAP" || fail=1

if [ "$fail" -ne 0 ]; then echo "[FAIL] 静态验证未通过"; exit 1; fi
echo "[PASS] 静态验证全部通过"
