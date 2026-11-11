#!/usr/bin/env bash
# 文件桥计数守卫（计划 §11「现状渠道 → 新协议对照」的机械化）。
#
# 背景：引擎与壳之间历史上靠一堆文件通信（input_events.txt、clip_*.txt、filedlg_*.txt …）。
# 计划要求把这些逐步换成 LWP 协议，M6 时全部删除。这个脚本做两件事：
#   1) 统计当前还有多少处「文件桥写入/读取点」，与基线比较——**只允许减少**；
#   2) 新增写入点直接失败，防止一边迁移一边又长出来。
#
# 与 §11 表的对应关系：表里「已短路」的行，这里的计数仍会算上写入侧代码（因为回落路径还在），
# 直到 M6 真正删掉那几行。计数下降就是删除进度的量化证据。
#
# 用法：
#   bash tools/check-no-file-bridge.sh              # 校验
#   bash tools/check-no-file-bridge.sh --report     # 打印每处命中
#   bash tools/check-no-file-bridge.sh --update-baseline
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASELINE="$ROOT/tools/file-bridge-baseline.toml"

# 计划 §11 列出的文件桥名字（只统计这些；日志文件如 vlclog 不算桥）
NAMES='input_events\.txt|key_events\.txt|text_input\.txt|clip_out\.txt|clip_req\.txt|clip_in\.txt|filedlg_req\.txt|filedlg_result\.txt|window_cmd\.txt|snapshot_req\.txt|locale\.txt|lanlu_env\.txt'

MODE=${1:-check}
HITS=$(mktemp)
trap 'rm -f "$HITS"' EXIT

# 扫描范围：引擎 + 平台包（third_party 与构建产物排除）
grep -rInE "$NAMES" \
    "$ROOT/client-next/src" \
    "$ROOT/packages/lwindow/src" \
    "$ROOT/packages/lplatform-ohos/shell" \
    "$ROOT/packages/lplatform-wayland" \
    2>/dev/null \
  | grep -vE '/target/|/build/|_test\.cj' \
  | sed 's|//.*$||' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*$' \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|\*|--)' \
  | sed "s|$ROOT/||" \
  | sed -E 's/^([^:]+):[0-9]+:/\1:/' \
  | sort > "$HITS"

COUNT=$(wc -l < "$HITS" | tr -d ' ')

if [ "$MODE" = "--report" ]; then
    echo "文件桥命中点（$COUNT 处）："
    cat "$HITS"
    exit 0
fi

if [ "$MODE" = "--update-baseline" ]; then
    {
        echo "# 文件桥基线（计划 §11 / M6 删除进度）——由 tools/check-no-file-bridge.sh 生成，勿手改。"
        echo "# 记录每一处命中（文件:行:内容），数量只允许下降；删除后运行 --update-baseline 刷新。"
        echo "keys = ["
        sed 's/\\/\\\\/g; s/"/\\"/g; s/^/  "/; s/$/",/' "$HITS"
        echo "]"
    } > "$BASELINE"
    echo "[baseline] 已记录 $COUNT 处"
    exit 0
fi

if [ ! -f "$BASELINE" ]; then
    echo "[FAIL] 缺少基线：先运行 bash tools/check-no-file-bridge.sh --update-baseline"
    exit 1
fi

KEYS=$(mktemp)
trap 'rm -f "$HITS" "$KEYS"' EXIT
sed -n '/^keys = \[/,/^\]/p' "$BASELINE" \
  | grep -E '^  "' \
  | sed 's/^  "//; s/",$//; s/\\"/"/g; s/\\\\/\\/g' > "$KEYS"

BASE=$(wc -l < "$KEYS" | tr -d ' ')
if [ "$COUNT" -lt "$BASE" ]; then
    echo "[PASS] 文件桥 $COUNT 处（基线 $BASE，已减少 $((BASE - COUNT)) 处）"
    echo "       可运行 --update-baseline 刷新基线"
    exit 0
elif [ "$COUNT" -eq "$BASE" ] && diff -q "$KEYS" "$HITS" >/dev/null; then
    echo "[PASS] 文件桥 $COUNT 处（未新增）"
    exit 0
fi

echo "[FAIL] 文件桥出现新增/变动（基线 $BASE，现状 $COUNT）："
comm -13 "$KEYS" "$HITS" | sed 's/^/  [新增] /'
comm -23 "$KEYS" "$HITS" | sed 's/^/  [已删] /' | head -5
exit 1
