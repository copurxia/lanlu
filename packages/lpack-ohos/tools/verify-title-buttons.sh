#!/usr/bin/env bash
# 三键平台化回归验证（docs/lwindow-title-buttons-plan.md P2/P3）：
#   1) 壳上报了平台三键矩形（ArkTS: title btn rect / 引擎: lwp title buttons）
#   2) 窗口几何仍为 decor=false（sysTop=0，三键悬浮不占布局）
#   3) 引擎侧不再自绘三键（日志断言 + 人工目视一次）
# 用法：bash packages/lpack-ohos/tools/verify-title-buttons.sh [device]
# 退出码：0 全部通过；1 有断言失败。
# 注意：会 force-stop 并启动一次应用（窗口会短暂出现在最前），完成后自动 force-stop。
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

hc "rm -f $BASE/window_info.txt $BASE/probe_trace.txt" >/dev/null
hc "aa force-stop $BUNDLE" >/dev/null
sleep 1
# 引擎探针要 LANLU_PROBE_LGPU=1（debug 包才落文件；release 包由 LANLU_DEBUGGABLE=0 门禁）；
# LANLU_PROBE_CAPTURE=1 额外抓一帧**应用自己的 surface**（不采屏幕，隐私安全），
# 用于自动量测标题栏右侧给系统三键留了多少空白。
hc "aa start -b $BUNDLE -a EntryAbility \
  --ps lanlu.env.CN_UI_BACKEND lgpu --ps lanlu.env.LANLU_MAIN_LGPU 1 \
  --ps lanlu.env.LANLU_PROBE_LGPU 1 --ps lanlu.env.LANLU_PROBE_CAPTURE 1" >/dev/null

say "等待探针（最多 30s）..."
TB=""
WI=""
for _ in $(seq 1 30); do
  TB=$(hc "grep 'lwp title buttons' $BASE/probe_trace.txt 2>/dev/null | tail -1")
  WI=$(hc "cat $BASE/window_info.txt 2>/dev/null")
  if [ -n "$TB" ] && [ -n "$WI" ]; then break; fi
  sleep 1
done

say "window_info: ${WI:-<空>}"
say "title_btn  : ${TB:-<空>}"

RC=0
check() { if [ "$2" = "$3" ]; then say "[ok]   $1 = $2"; else say "[FAIL] $1 = $2 (期望 $3)"; RC=1; fi; }

# 1) 三键矩形到达引擎：形如 "lwp title buttons 266x70px right=... top=... visible=true"
if [ -z "$TB" ]; then
  say "[FAIL] 未收到 lw_window.title_buttons_rect（壳未上报或能力位未置）"
  RC=1
else
  W=$(printf "%s" "$TB" | sed -n "s/.*buttons \([0-9]*\)x\([0-9]*\)px.*/\1/p")
  VIS=$(printf "%s" "$TB" | sed -n "s/.*visible=\([a-z]*\).*/\1/p")
  if [ -n "$W" ] && [ "$W" -gt 0 ] 2>/dev/null; then
    say "[ok]   三键宽度 = ${W}px（文档参考：140vp × 屏幕密度）"
  else
    say "[FAIL] 三键宽度 = ${W:-<空>}px（期望 >0）"; RC=1
  fi
  check "三键可见" "${VIS:-?}" "true"
fi

# 2) decor 仍隐藏（三键悬浮不占布局，鼠标坐标口径不回归）
SYSTOP=$(printf "%s" "$WI" | sed -n "s/.*sysTop=\([-0-9]*\).*/\1/p")
if [ -n "$SYSTOP" ]; then check "sysTop(无标题栏)" "$SYSTOP" "0"; else say "[warn] window_info 缺失（不影响三键断言）"; fi

# 3) 引擎侧确认走了"不自绘三键"分支：probe_trace 里应出现
#    "ui title buttons width=<w>vp selfDrawn=false"（w = 物理宽 / 屏幕密度）
SELF=$(hc "grep 'ui title buttons' $BASE/probe_trace.txt 2>/dev/null | tail -1")
say "self-drawn : ${SELF:-<空>}"
if [ -z "$SELF" ]; then
  say "[FAIL] 引擎未打点 ui title buttons（平台三键宽度分支未生效）"; RC=1
else
  case "$SELF" in
    *selfDrawn=false*) say "[ok]   引擎不再自绘三键（selfDrawn=false）" ;;
    *) say "[FAIL] 引擎仍在自绘三键：$SELF"; RC=1 ;;
  esac
  SELF_W=$(printf "%s" "$SELF" | sed -n "s/.*width=\([0-9]*\)\.\([0-9]*\)vp.*/\1/p")
  if [ -n "$SELF_W" ]; then
    say "[ok]   业务层避让宽度 = ${SELF_W}vp（文档参考 140vp）"
  fi
fi
# 4) 引擎 -> 壳：默认三键配置（位置/尺寸）应被壳应用（hilog；缓冲可能轮转，故 warn）
CFG=$(hc "hilog -x 2>/dev/null | grep 'title buttons cfg applied' | tail -1")
if [ -n "$CFG" ]; then
  say "[ok]   壳已应用引擎下发的三键配置"
else
  say "[warn] hilog 未见 'title buttons cfg applied'（缓冲轮转或引擎未发配置）"
fi

# 5) 应用自绘面量测：标题栏右侧应为系统三键留出空白（业务层不再画三键）
#    探针写的是逐帧文件 cap_f{N}.rgba（apps/desktop/src/main.cj frameProbeHook），
#    这里取设备上最新的一张；本地先删目标文件 —— hc 的退出码恒 0（管道尾是 tr），
#    只有 recv 后本地文件非空才算抓帧成功，否则会量到上次残留的旧帧。
CAP=/workspace/lanlu/tmp/cap_latest.rgba
mkdir -p /workspace/lanlu/tmp
rm -f "$CAP"
REMOTE_CAP=$(hc "ls -t $BASE/cap_f*.rgba 2>/dev/null | head -1")
if [ -n "$REMOTE_CAP" ]; then
  "$HDC" -t "$DEV" file recv "$REMOTE_CAP" "$CAP" >/dev/null 2>&1
else
  say "[warn] 设备上未找到 cap_f*.rgba（LANLU_PROBE_CAPTURE 未开启或帧钩子未触发）"
fi
if [ -s "$CAP" ]; then
    # 抓帧尺寸 = 窗口矩形（从 window_info 的 rect=L,T,W,H 解析，避免写死分辨率）
    RECTV=$(printf "%s" "$WI" | sed -n 's/.*rect=\([^ ]*\) .*/\1/p')
    [ -n "$RECTV" ] || RECTV=$(printf "%s" "$WI" | sed -n 's/.*rect=\(.*\)$/\1/p')
    CAPW=$(printf "%s" "$RECTV" | cut -d, -f3)
    CAPH=$(printf "%s" "$RECTV" | cut -d, -f4)
    [ -n "$CAPW" ] || CAPW=2090
    [ -n "$CAPH" ] || CAPH=1394
    RES=$(python3 - "$CAP" "$CAPW" "$CAPH" <<'PY'
import sys
p, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
data = open(p, "rb").read()
row = 50                      # 标题栏中部（56vp × 1.9 ≈ 106px）
bg = (data[0], data[1], data[2])   # 左上角像素 = 标题栏底色
last = -1
for x in range(w):
    o = (row * w + x) * 4
    if abs(data[o]-bg[0]) > 6 or abs(data[o+1]-bg[1]) > 6 or abs(data[o+2]-bg[2]) > 6:
        last = x
print(w - 1 - last if last >= 0 else -1)
PY
)
    if [ -n "$RES" ] && [ "$RES" -gt 200 ] 2>/dev/null; then
      say "[ok]   自绘面标题栏右侧留白 = ${RES}px（系统三键区 ≈266px，业务层未再画三键）"
    else
      say "[warn] 自绘面留白 = ${RES:-?}px（可能页面无右缘控件或抓帧帧号不同，人工目视兜底）"
    fi
fi
say "[info] 目视检查（人工）：右上角只有一组三键（系统），引擎自绘三键不得出现重影"

# 6) 关窗链路：模拟系统关闭钮（LANLU_PROBE_CLOSE=1 → lwpSendCloseRequest），
#    引擎应收到 close_request 并退出（与 windowWillClose 同一条下游路径）。
hc "aa force-stop $BUNDLE" >/dev/null
sleep 1
hc "aa start -b $BUNDLE -a EntryAbility --ps lanlu.env.CN_UI_BACKEND lgpu \
  --ps lanlu.env.LANLU_MAIN_LGPU 1 --ps lanlu.env.LANLU_PROBE_LGPU 1 \
  --ps lanlu.env.LANLU_PROBE_CLOSE 1" >/dev/null
EXITED=0
for _ in $(seq 1 12); do
  P=$(hc "pidof $BUNDLE")
  if [ -z "$P" ]; then EXITED=1; break; fi
  sleep 1
done
if [ "$EXITED" = "1" ]; then
  say "[ok]   close_request -> 引擎退出（进程已结束）"
else
  say "[FAIL] close_request 后引擎仍在运行（pid=$P）"; RC=1
fi
hc "aa force-stop $BUNDLE" >/dev/null

if [ "$RC" = "0" ]; then say "[PASS] 三键平台化链路通（rect 到达引擎 + decor=false + 关窗链路）"; else say "[FAIL] 三键平台化验证未通过"; fi
exit "$RC"
