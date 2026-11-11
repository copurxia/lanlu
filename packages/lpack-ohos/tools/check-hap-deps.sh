#!/usr/bin/env bash
# 静态验证 HAP 可加载性（权威版，无需设备）。
# 对 HAP 内每个库的 NEEDED：
#   - 在 HAP 内 → OK（随包）
#   - 在 OHOS NDK sysroot 内 → OK（系统库，设备上有）
#   - 否则 → UNKNOWN（很可能是名字拼错/漏包，运行时会加载失败）
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
export TMPDIR="${TMPDIR:-/tmp}"
SYSROOT="${SYSROOT:-$OHOS_SYSROOT}"
SYSLIBS="$SYSROOT/usr/lib/aarch64-linux-ohos"
HAP="${1:-$(find_hap || echo "$HAP_OUT/entry-default-signed.hap")}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -o -q "$HAP" 'libs/arm64-v8a/*' -d "$WORK"
LIBS="$WORK/libs/arm64-v8a"
cd "$LIBS" || exit 1

missing=0; unknown=0; checked=0
while read -r dep; do
  checked=$((checked+1))
  [ -e "$dep" ] && continue
  if [ -e "$SYSLIBS/$dep" ]; then continue; fi
  # 少数系统库只在设备上（ohos 私有 .z.so 等），按命名规律放行
  case "$dep" in
    lib*.z.so|libc++.so|libclang_rt.*|libunwind.so|libEGL.so*|libGLESv*.so*) continue ;;
  esac
  echo "[UNKNOWN] 既不在 HAP 也不在 sysroot: $dep"
  unknown=$((unknown+1))
done < <(for f in *.so *.so.*; do
           [ -f "$f" ] || continue
           readelf -d "$f" 2>/dev/null | grep NEEDED | awk '{print $NF}' | tr -d '[]'
         done | sort -u)

echo "检查 $checked 个唯一依赖（HAP 内 $(ls *.so* 2>/dev/null | wc -l) 个库，sysroot 提供 $(ls "$SYSLIBS" 2>/dev/null | wc -l) 个库）"

# 架构门禁：误打 x86_64 库会导致设备上无法加载
badarch=0
for f in *.so *.so.*; do
  [ -f "$f" ] || continue
  m=$(readelf -h "$f" 2>/dev/null | awk '/Machine:/{print $2}')
  if [ "$m" != "AArch64" ]; then
    echo "[BADARCH] $f ($m)"
    badarch=$((badarch+1))
  fi
done
if [ "$badarch" -eq 0 ]; then echo "[PASS] 全部库为 AArch64"; else echo "[FAIL] $badarch 个库架构不符"; fi
unknown=$((unknown+badarch))
if [ "$unknown" -eq 0 ]; then echo "[PASS] 全部依赖可解析（随包或系统）"; else echo "[FAIL] $unknown 项来源未知"; fi
exit $((unknown>0))
