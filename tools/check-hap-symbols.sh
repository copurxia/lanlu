#!/usr/bin/env bash
# 静态校验：libmain 通过 dlsym 查找的符号，必须真的由 HAP 内某个库导出。
# （历史上出现过 lanlu_self_inject 缺失导致引擎 dlopen 失败的问题。）
set -uo pipefail
# 临时目录必须落在有空间的卷上（/tmp 是 512M tmpfs，容易写满导致解包截断）
export TMPDIR="${TMPDIR:-/workspace/tmp}"
HAP="${1:-/workspace/lanlu/lanlu/client-next/build/ohos/target/ohos/hap/entry/build/default/outputs/default/entry-default-signed.hap}"
WORK=$(mktemp -d)
unzip -o -q "$HAP" 'libs/arm64-v8a/*' -d "$WORK"
LIBS="$WORK/libs/arm64-v8a"

SYMS="cj_app_main InitCJRuntime LoadCJLibraryWithInit SDL_OpenHarmonySetWindowActionHook SDL_OpenHarmonySetFileDialogHook SDL_main"

missing=0
count=0
for s in $SYMS; do
  count=$((count+1))
  found=""
  for f in "$LIBS"/*.so*; do
    [ -f "$f" ] || continue
    exports=$(nm -D --defined-only "$f" 2>/dev/null | awk '{print $3}' | sed 's/@.*//')
    if grep -qx "$s" <<< "$exports"; then
      found=$(basename "$f")
      break
    fi
  done
  if [ -n "$found" ]; then
    echo "  [ok] $s <- $found"
  else
    echo "  [MISSING] $s 未在任何随包库中导出"
    missing=$((missing+1))
  fi
done
echo "checked $count symbols; missing=$missing"
[ "$missing" -eq 0 ] && echo "[PASS] 符号一致" || echo "[FAIL] 符号缺失"
exit $((missing>0))
