#!/usr/bin/env bash
# 静态校验：libmain 通过 dlsym 查找的符号，必须真的由 HAP 内某个库导出。
# （历史上出现过 lanlu_self_inject 缺失导致引擎 dlopen 失败的问题。）
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# 临时目录必须落在有空间的卷上（/tmp 是 512M tmpfs，容易写满导致解包截断）
export TMPDIR="${TMPDIR:-/tmp}"
HAP="${1:-$(find_hap || echo "$HAP_OUT/entry-default-signed.hap")}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
unzip -o -q "$HAP" 'libs/arm64-v8a/*' -d "$WORK"
LIBS="$WORK/libs/arm64-v8a"

# P5：壳层已不依赖 SDL（窗口/输入/渲染都走 L 层），SDL_* 不再要求导出。
SYMS="cj_app_main InitCJRuntime LoadCJLibraryWithInit"

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

# ── 反向门禁（M0-4 结论的机制化）────────────────────────────────────────────
# 壳/引擎对 lanlu_* / lwp_* 的**未定义 C 符号引用**必须由同包内某个库导出。
# 只查纯小写 C 符号（`lanlu_font_list_create` 这类）：仓颉跨包类型信息（形如
# `pkg:Type.ti`）由仓颉运行时按自己的规则解析，不属于本门禁范围。
# 历史事故（horizon-ohos 2026-10-25）：缺 #[no_mangle] 时链接照样成功，得到一个 UNDEFINED
# 动态符号，第一次调用跳进只读数据 → SIGSEGV。docs/l-layer.md 的 M0-4 结论也指出：
# 这种失败在运行期是**静默**的（dlopen 成功、退出码 0），只能静态拦。
undef_missing=0
undef_count=0
for f in "$LIBS"/*.so*; do
  [ -f "$f" ] || continue
  for u in $(nm -D --undefined-only "$f" 2>/dev/null | awk '{print $2}' | sed 's/@.*//' \
             | grep -E '^(lanlu_|lwp_)[a-z0-9_]+$' | sort -u); do
    undef_count=$((undef_count+1))
    provider=""
    for g in "$LIBS"/*.so*; do
      [ -f "$g" ] || continue
      [ "$g" = "$f" ] && continue
      if nm -D --defined-only "$g" 2>/dev/null | awk '{print $3}' | sed 's/@.*//' | grep -qx "$u"; then
        provider=$(basename "$g")
        break
      fi
    done
    if [ -n "$provider" ]; then
      echo "  [ok] $(basename "$f") needs $u <- $provider"
    else
      echo "  [UNDEF] $(basename "$f") 需要 $u，但 HAP 内没有任何库导出它"
      undef_missing=$((undef_missing+1))
    fi
  done
done
echo "checked $undef_count lanlu_/lwp_ undefined refs; unresolved=$undef_missing"

[ "$missing" -eq 0 ] && [ "$undef_missing" -eq 0 ] && echo "[PASS] 符号一致" || echo "[FAIL] 符号缺失"
exit $((missing>0 || undef_missing>0))
