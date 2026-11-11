#!/usr/bin/env bash
# 窗口/输入回归验证（P5）：确认
#   1) 系统窗口装饰已去掉（sysTop/cutTop/navBottom = 0）
#   2) 输入过滤器原点 == 窗口矩形原点（鼠标局部坐标换算正确）
# 用法：tools/verify-window.sh [device]
# 退出码：0 全部通过；1 有断言失败。
set -u

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
DEV="${1:-192.168.0.26:42113}"
DEVC=$OHOS_CLT
HDC="$DEVC/sdk/default/openharmony/toolchains/hdc"
BUNDLE=com.example.cmakehap
BASE="/data/app/el2/100/base/$BUNDLE/files"

say() { printf "%s\n" "$*"; }
hc() { "$HDC" -t "$DEV" shell "$@" 2>/dev/null | tr -d "\r"; }

if ! "$HDC" -t "$DEV" shell "echo ok" >/dev/null 2>&1; then
  say "[FAIL] 设备不可达: $DEV"; exit 1
fi

hc "rm -f $BASE/window_info.txt $BASE/filter_origin.txt"
hc "aa force-stop $BUNDLE" >/dev/null
sleep 1
hc "aa start -b $BUNDLE -a EntryAbility --ps lanlu.env.CN_UI_BACKEND lgpu --ps lanlu.env.CN_WINDOW lgpu" >/dev/null

say "等待探针文件（最多 25s）..."
for _ in $(seq 1 15); do
  WI=$(hc "cat $BASE/window_info.txt")
  FO=$(hc "cat $BASE/filter_origin.txt")
  if [ -n "$WI" ] && [ -n "$FO" ]; then break; fi
  sleep 1
done

PID=""
for _ in $(seq 1 10); do
  PID=$(hc "pidof $BUNDLE")
  [ -n "$PID" ] && break
  sleep 1
done
# pidof 偶发取不到（进程刚起/被后台回收），用 ps 兜底
if [ -z "$PID" ]; then
  PID=$(hc "ps -ef | grep $BUNDLE | grep -v grep | awk '{print \$2}' | head -1")
fi
say "pid=$PID"
say "window_info:   ${WI:-<空>}"
say "filter_origin: ${FO:-<空>}"

RC=0
# pidof 在部分设备/后台态取不到，进程存活只作为提示，不作为失败条件
if [ -z "$PID" ]; then say "[warn] 未取到 pid（探针已写出，说明应用确实启动过）"; fi

# rect=L,T,W,H
RECT=$(printf "%s" "$WI" | sed -n "s/.*rect=\([-0-9]*\),\([-0-9]*\),\([-0-9]*\),\([-0-9]*\).*/\1 \2 \3 \4/p")
SYSTOP=$(printf "%s" "$WI" | sed -n "s/.*sysTop=\([-0-9]*\).*/\1/p")
CUTTOP=$(printf "%s" "$WI" | sed -n "s/.*cutTop=\([-0-9]*\).*/\1/p")
NAVBOT=$(printf "%s" "$WI" | sed -n "s/.*navBottom=\([-0-9]*\).*/\1/p")
OX=$(printf "%s" "$FO" | sed -n "s/.*ox=\([-0-9.]*\).*/\1/p")
OY=$(printf "%s" "$FO" | sed -n "s/.*oy=\([-0-9.]*\).*/\1/p")

check() { if [ "$2" = "$3" ]; then say "[ok]   $1 = $2"; else say "[FAIL] $1 = $2 (期望 $3)"; RC=1; fi; }

if [ -n "$SYSTOP" ]; then check "sysTop(无标题栏)" "$SYSTOP" "0"; else say "[FAIL] window_info 缺失"; RC=1; fi
if [ -n "$CUTTOP" ]; then check "cutTop" "$CUTTOP" "0"; fi
if [ -n "$NAVBOT" ]; then check "navBottom" "$NAVBOT" "0"; fi
if [ -n "$RECT" ] && [ -n "$OX" ]; then
  RL=$(printf "%s" "$RECT" | awk "{print \$1}")
  RT=$(printf "%s" "$RECT" | awk "{print \$2}")
  check "origin.x == rect.left" "$(printf "%.0f" "$OX")" "$RL"
  check "origin.y == rect.top" "$(printf "%.0f" "$OY")" "$RT"
elif [ -z "$RECT" ]; then say "[FAIL] 无法解析 windowRect"; RC=1; fi

if [ "$RC" = "0" ]; then say "[PASS] 窗口装饰已去掉 + 鼠标原点换算一致"; else say "[FAIL] 窗口/输入回归未通过"; fi
exit "$RC"
