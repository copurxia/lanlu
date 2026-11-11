#!/usr/bin/env bash
# 真机输入探针（**坐标正确版**）：uitest 用的是**屏幕**坐标，
# 应用窗口有偏移，必须先从 window_info.txt 拿到窗口 rect 再换算。
#
# 用法：bash tools/ohos-input-probe.sh [x y]   # x/y 为**应用内**物理坐标，默认点搜索框
set -euo pipefail
HDC=${HDC:-/workspace/lanlu/.research-ohos/tools/clt-7.0/command-line-tools/sdk/default/openharmony/toolchains/hdc}
PKG=com.example.cmakehap
TRACE_APP=/data/app/el2/100/base/$PKG/files/probe.lwtrace
TRACE_HOST=/tmp/probe.lwtrace

"$HDC" shell "aa force-stop $PKG" >/dev/null 2>&1 || true
sleep 2
"$HDC" shell "rm -f $TRACE_APP" >/dev/null 2>&1 || true
"$HDC" shell "aa start -a EntryAbility -b $PKG --ps lanlu.env.LANLU_LWP_TRACE /data/storage/el2/base/files/probe.lwtrace" | tail -1
sleep 7
"$HDC" shell "aa start -a EntryAbility -b $PKG" >/dev/null 2>&1   # 前置窗口，否则输入到不了应用
sleep 3

# 窗口矩形：形如 rect=515,292,2090,1394
RECT=$("$HDC" shell "cat /data/app/el2/100/base/$PKG/files/window_info.txt" 2>/dev/null | sed -n 's/.*rect=//p' | cut -d, -f1,2)
WX=$(echo "$RECT" | cut -d, -f1); WY=$(echo "$RECT" | cut -d, -f2)
LX=${1:-690}; LY=${2:-21}          # 应用内坐标（默认：标题栏搜索框）
SX=$((WX + LX)); SY=$((WY + LY))
echo "窗口偏移=($WX,$WY) 应用内=($LX,$LY) -> 屏幕=($SX,$SY)"

"$HDC" shell "uitest uiInput click $SX $SY" >/dev/null && sleep 2
"$HDC" shell "uitest uiInput swipe $SX $SY $((SX+40)) $((SY+4)) 300" >/dev/null && sleep 3

"$HDC" file recv "$TRACE_APP" "$TRACE_HOST" >/dev/null
python3 tools/lwtrace.py stats "$TRACE_HOST" | grep -E 'pointer_button|pointer_motion|set_cursor|text_input' || echo "（没有相关消息）"
