#!/usr/bin/env bash
# OHOS 移植静态验证（无需设备）：分层守卫 + HAP 依赖闭包 + 关键符号导出。
# 用法: bash tools/verify-ohos.sh [<signed.hap>]
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default
HAP="${1:-}"
if [ -z "$HAP" ]; then
  # 优先用签名版（真机安装用），构建阶段可能只有 unsigned
  for cand in "$OUT/entry-default-signed.hap" "$OUT/entry-default-unsigned.hap"; do
    [ -f "$cand" ] && HAP="$cand" && break
  done
fi
[ -f "$HAP" ] || { echo "[FAIL] 找不到 HAP（先跑 build-ohos.sh）"; exit 1; }
echo "检查 HAP: $HAP"
fail=0

echo "== 1/3 分层守卫 =="
bash tools/check-layering.sh || fail=1

echo "== 2/3 HAP 依赖闭包 =="
bash tools/check-hap-deps.sh "$HAP" || fail=1

echo "== 3/3 关键符号导出 =="
bash tools/check-hap-symbols.sh "$HAP" || fail=1

if [ "$fail" -ne 0 ]; then echo "[FAIL] 静态验证未通过"; exit 1; fi
echo "[PASS] 静态验证全部通过"
