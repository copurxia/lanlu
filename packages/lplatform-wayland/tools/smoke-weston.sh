#!/usr/bin/env bash
# Wayland 壳冒烟：在 weston（headless backend）里真跑一次壳。
#
# 本机没有 weston 时**优雅跳过**（CI 里装了就必须跑，用 --require）。
#
# 用法：
#   bash packages/lplatform-wayland/tools/smoke-weston.sh [--require] [--seconds N]
set -euo pipefail

REQUIRE=0
SECONDS_TO_RUN=6
while [ $# -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1; shift ;;
    --seconds) SECONDS_TO_RUN=$2; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

HERE=$(cd "$(dirname "$0")/.." && pwd)     # packages/lplatform-wayland
BIN="$HERE/target/release/lanlu"

if ! command -v weston >/dev/null 2>&1; then
  if [ "$REQUIRE" = "1" ]; then
    echo "error: --require 但没有 weston（CI 里请 apt-get install weston）" >&2
    exit 1
  fi
  echo "[SKIP] 本机没有 weston，跳过 Wayland 冒烟（CI 里会跑）"
  exit 0
fi

[ -x "$BIN" ] || { echo "error: 先 cargo build --release（缺 $BIN）" >&2; exit 1; }

run_dir=$(mktemp -d)
cleanup() {
  if [ -n "${weston_pid:-}" ]; then kill "$weston_pid" 2>/dev/null || true; fi
  rm -rf "$run_dir"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="$run_dir"
chmod 700 "$XDG_RUNTIME_DIR"
weston --backend=headless-backend.so --socket=lanlu-smoke --idle-time=0 \
  --log="$run_dir/weston.log" >/dev/null 2>&1 &
weston_pid=$!

# 等 socket 出现（最多 10s）
for _ in $(seq 1 100); do
  [ -S "$XDG_RUNTIME_DIR/lanlu-smoke" ] && break
  sleep 0.1
done
[ -S "$XDG_RUNTIME_DIR/lanlu-smoke" ] || { echo "error: weston 没起来"; tail -20 "$run_dir/weston.log"; exit 1; }

export WAYLAND_DISPLAY=lanlu-smoke
out="$run_dir/shell.log"
# 壳会一直跑（等窗口事件）；跑够时间就杀掉，再看日志里有没有握手与建窗
timeout "${SECONDS_TO_RUN}s" "$BIN" >"$out" 2>&1 || true

fail=0
grep -q 'hello 已发出' "$out" || { echo "[FAIL] 未见 hello"; fail=1; }
grep -q 'window.create' "$out" || echo "[WARN] 未见 window.create（无输入时壳不会建窗，属正常）"
if [ "$fail" = "1" ]; then tail -30 "$out"; exit 1; fi
echo "[PASS] Wayland 冒烟：壳在 weston 下完成握手"
