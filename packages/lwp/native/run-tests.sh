#!/usr/bin/env bash
# LWP 的 C 侧测试：协议布局（生成物）+ 通道实现。
# 计划 §5.2、§10 M1。不需要仓颉工具链。
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 容器 /tmp 常以 noexec 挂载；默认落到仓库同级 tmp/（不再写死 Gitea 的绝对路径）
REPO=$(cd "$HERE/../.." && pwd)
mkdir -p "${TMPDIR:-$REPO/../tmp}"
OUT=${OUT:-$(mktemp -d "${TMPDIR:-$REPO/../tmp}/lwp-test.XXXXXX")}
mkdir -p "$OUT"
CC=${CC:-cc}
CFLAGS="-std=c11 -Wall -Wextra -Werror -O2 -pthread"
fail=0

echo "== 1/2 协议布局（C 静态断言 + 运行时）"
$CC $CFLAGS -o "$OUT/test_protocol" "$HERE/test_protocol.c" || fail=1
[ $fail -ne 0 ] || "$OUT/test_protocol" || fail=1

echo "== 2/3 通道实现（收发 / 满队列 / 多生产者 / blob / wait-wake / 检查器 / 录制）"
mkdir -p "$OUT"
# LWP_TEST_HOOKS 仅用于构造非法头部消息，生产构建不带
$CC $CFLAGS -DLWP_TEST_HOOKS -o "$OUT/test_channel" "$HERE/test_channel.c" "$HERE/liblwp.c" || fail=1
# 录制文件落在 OUT 下，供第 3 步解析
[ $fail -ne 0 ] || LWP_TRACE_PATH="$OUT/channel.lwtrace" "$OUT/test_channel" || fail=1

echo "== 3/3 lwtrace 工具解析（录制文件 → stats/dump）"
TRACE="$OUT/channel.lwtrace"
if [ -f "$TRACE" ]; then
  ROOT=$(cd "$HERE/../../.." && pwd)
  python3 "$ROOT/tools/lwtrace.py" stats "$TRACE" > "$OUT/stats.txt" || fail=1
  grep -q "记录数：6" "$OUT/stats.txt" || { echo "  [FAIL] stats 记录数不符"; cat "$OUT/stats.txt"; fail=1; }
  grep -q "lw_core.hello" "$OUT/stats.txt" || { echo "  [FAIL] stats 未解析出消息名"; fail=1; }
  python3 "$ROOT/tools/lwtrace.py" dump "$TRACE" > "$OUT/dump.txt" || fail=1
  grep -q "lw_core.hello" "$OUT/dump.txt" || { echo "  [FAIL] dump 未解析出消息名"; fail=1; }
  echo "  [ok]   lwtrace stats/dump 解析正常"

  # 语义 diff：同一文件应一致；改一个字节应报差异
  if python3 "$ROOT/tools/lwtrace.py" verify "$TRACE" > "$OUT/verify.txt" 2>&1; then
    echo "  [ok]   lwtrace verify：结构完整"
  else
    echo "  [FAIL] lwtrace verify 失败"; cat "$OUT/verify.txt"; fail=1
  fi
  # 截断文件必须被 verify 抓出来
  head -c 40 "$TRACE" > "$OUT/trunc.lwtrace"
  if python3 "$ROOT/tools/lwtrace.py" verify "$OUT/trunc.lwtrace" > /dev/null 2>&1; then
    echo "  [FAIL] verify 未发现被截断的文件"; fail=1
  else
    echo "  [ok]   lwtrace verify：能发现截断"
  fi

  if python3 "$ROOT/tools/lwtrace.py" diff "$TRACE" "$TRACE" > "$OUT/diff-same.txt" 2>&1; then
    echo "  [ok]   lwtrace diff：同文件语义一致"
  else
    echo "  [FAIL] lwtrace diff 对同一文件报差异"; cat "$OUT/diff-same.txt"; fail=1
  fi
  cp "$TRACE" "$OUT/mutated.lwtrace"
  python3 - "$OUT/mutated.lwtrace" <<'PYEOF'
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
d[-1] ^= 0xFF
open(p, 'wb').write(d)
PYEOF
  if python3 "$ROOT/tools/lwtrace.py" diff "$TRACE" "$OUT/mutated.lwtrace" > "$OUT/diff-bad.txt" 2>&1; then
    echo "  [FAIL] lwtrace diff 未发现被篡改的载荷"; fail=1
  else
    grep -q "共 1 处差异" "$OUT/diff-bad.txt" && echo "  [ok]   lwtrace diff：发现载荷差异" \
      || { echo "  [FAIL] diff 输出不符合预期"; cat "$OUT/diff-bad.txt"; fail=1; }
  fi
else
  echo "  [FAIL] 没有生成 $TRACE"; fail=1
fi

rm -rf "$OUT"
if [ $fail -eq 0 ]; then
  echo "[PASS] lwp C 测试全部通过"
  exit 0
fi
echo "[FAIL] lwp C 测试失败"
exit 1
