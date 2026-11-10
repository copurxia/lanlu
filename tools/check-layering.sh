#!/usr/bin/env bash
# 分层守卫（Chromium layering check 风格）：
#   业务层 client-next/src、UI 框架 cangjie-gui/src、SDL 绑定 sdl/src
#   **不得**出现平台专有标识（OS 判断、平台路径、平台专有符号）。
# 平台差异必须落在 packages/lwindow（平台适配层）或 packages/ohos（ArkTS/C++ 壳）内。
#
# 用法：bash tools/check-layering.sh [--verbose]
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERBOSE="${1:-}"

DIRS=(
  "$ROOT/client-next/src"
  "$ROOT/packages/cangjie-gui/src"
  "$ROOT/packages/cangjie-gui/lgui/src"
)

PATTERNS='ohos_[a-z]|OHOS_|/system/lib64|/data/storage/el2|/system/fonts|XDG_SESSION_TYPE|HarmonyOS|libdecor|LIBDECOR_PLUGIN_DIR|SDL_OpenHarmony'

fail=0
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  while IFS= read -r hit; do
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    code="${rest#*:}"
    trimmed="$(echo "$code" | sed 's/^[[:space:]]*//')"
    case "$trimmed" in
      //*|\**|/\**) continue ;;
    esac
    fail=$((fail+1))
    if [ "$VERBOSE" = "--verbose" ]; then
      echo "[LAYERING] $file:$lineno: $trimmed"
    else
      echo "[LAYERING] ${file#$ROOT/}:$lineno"
    fi
  done < <(grep -rnE "$PATTERNS" "$d" --include='*.cj' 2>/dev/null)
done

if [ "$fail" -eq 0 ]; then
  echo "[PASS] 业务/UI/绑定层无平台专有标识"
  exit 0
fi
echo "[FAIL] 发现 $fail 处平台专有代码（应移入 packages/lwindow 或 packages/ohos）"
exit 1
