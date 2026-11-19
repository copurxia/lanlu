# 三键平台化迁移计划（最小化 / 最大化 / 关闭 → 平台层）

> 目标：把窗口控制三键（min / max / close）从业务层（client-next 自绘 UI）里**移除**，
> 统一交给平台层（lplatform-ohos 壳，用系统窗口装饰能力渲染），业务层只保留
> "能力查询 + 矩形避让"。
> 前提（用户给出 + 参照实现证实）：OHOS 支持"隐藏标题栏但保留三键"。mihong（同设备、
> 同 26 API）已经跑通：`setWindowDecorVisible(false)` 只去标题栏，右上三键仍由系统
> 画在应用 surface 上（见 `/workspace/mihong/docs/caption-avoid-1030.md`：
> native 收到 `OnCaptionButtonRectChange: 266x70 px`、标签页停在 2856px、三键从 2880px 开始）。

状态：**P0–P5 全部完成 + 主题联动 + 自绘面自动量测**（协议/引擎/壳/业务层/文档守卫；真机链路已验证）· 日期：2026-11-11
剩余：仅"人手点一次系统关闭钮"验证 close_request（`windowWillClose` 监听器已注册成功、链路与
`cancel/退出` 共用既有实现）；人工目视可选（自绘面量测已代替）。
关联：[lwp-handoff-status.md](lwp-handoff-status.md) ·
[lwindow-platform-separation-plan.md](lwindow-platform-separation-plan.md) ·
[lwp-message-coverage.md](lwp-message-coverage.md) ·
[l-layer.md](l-layer.md)

## 进度快照（2026-11-11）

| 里程碑 | 状态 | 证据 |
|---|---|---|
| P0 机制证实 | ✅ | 官方指南《应用适配自由窗口》§调整布局避让标题栏和窗口三键 + API 参考（`setWindowDecorVisible`/`getTitleButtonRect`/`windowTitleButtonRectChange`）+ mihong 实测（266×70px @1.9 密度）+ 本仓真机探针（rectChange 140×37vp） |
| P1 协议追加 | ✅ | `lw_window.set_title_buttons` + `lw_window.title_buttons_rect` + `core_capabilities.title_buttons`（bit17）；`lwp-gen --check` = 64 条消息 / 13 接口；`--check-abi` PASS（56→64，纯追加） |
| P1 引擎编解码 | ✅ | `lwp_encode.encodeLwWindowSetTitleButtons`；`LwpWindowClient.setTitleButtons()`（能力门禁）+ `TitleButtonsRect` 生命周期事件 + `titleBtn{Right,Top,Width,Height,Visible}` 快照；`window_client_test` 新增 2 项（42/42 PASS） |
| P2 OHOS 壳实现 | ✅ 真机验证通过 | 壳 native：`set_title_buttons` 解析 + `lanlu_lwp_take_title_buttons` + `lanlu_lwp_send_title_buttons_rect`；napi：`lwpTakeTitleButtons`/`lwpTitleButtonRect`/`lwpSendCloseRequest`；ArkTS：配置应用（`setWindowTitleButtonVisible`+`setDecorButtonStyle` clamp）、rect 事件→vp2px→上报（仅变化时发）、`windowWillClose`→close_request；顺手修掉 minimize 误触发 bug；hello 置 `title_buttons` 能力位。真机：`title buttons cfg applied visible=0x7` + rect 回报 |
| P4 Wayland 对齐 | ✅ 无需改动 | Wayland 壳不置 `title_buttons` 能力位 → 引擎自绘回退（`platformTitleButtonsWidth()==0`）；壳对未知 opcode 走默认分支只打日志，不崩 |
| P5 文档/守卫收尾 | ✅ | known-limitations 增两条（位置限制/Wayland 回退）、l-layer R49 补三键说明、message-coverage 加 §C、platform-api 加新 API、handoff 状态、验证脚本 `verify-title-buttons.sh`，8 项守卫全绿 |
| P3 业务层去三键 | ✅ 代码完成，真机验证通过 | `titlebar.cj`/`reader_bar.cj`：`platformTitleButtonsWidth() > 0` 时不再建 `WinControlButton`×3/`WinSep`，右内边距 = 原值 + 三键宽 + 8；`lgpu_backend.cj`：消费 `TitleButtonsRect` 事件 + 能力门禁（`lwpShellProvidesTitleButtons`）+ 分支打点 `ui title buttons width=..vp selfDrawn=..`；引擎 aarch64-ohos 编译 + 链接通过 |

**真机验证（2026-11-11，设备 192.168.0.26）**

```
bash packages/lpack-ohos/tools/verify-title-buttons.sh
window_info: rect=515,292,2090,1394 sysTop=0 sysBottom=0 cutTop=0 navBottom=0
title_btn  : lwp title buttons 266x70px right=0 top=0 visible=true
[ok]   三键宽度 = 266px（文档参考：140vp × 屏幕密度）
[ok]   三键可见 = true
[ok]   sysTop(无标题栏) = 0
self-drawn : ui title buttons width=134.736847vp selfDrawn=false
[ok]   引擎不再自绘三键（selfDrawn=false）
[ok]   业务层避让宽度 = 134vp（文档参考 140vp）
[ok]   壳已应用引擎下发的三键配置
[PASS] 三键平台化链路通（rect 到达引擎 + decor=false）
```

**引擎 → 壳的配置回环也验证了**：引擎启动后发一次默认配置
`set_title_buttons(visible=0x7, side=0, close_margin=16, spacing=12, button_size=28)`，
壳应用后系统重新排版三键并**回报新的矩形**——宽度从 266px(140vp) 变成 256px(134.7vp)：

```
ui title buttons cfg sent=true                     ← 引擎发出
[LANLU-SHELL] title buttons cfg applied visible=0x7 ← 壳 setWindowTitleButtonVisible + setDecorButtonStyle
lwp title buttons 256x70px right=0 top=0 visible=true ← 系统按新样式回报 rect
ui title buttons width=134.736847vp selfDrawn=false
```

这条回路就是"支持设置位置"的落地证明：引擎给出 margin/spacing/size，
壳 clamp 后应用，rect 事件把真实结果回给引擎做避让。

**主题联动**：引擎按已保存主题发 `colorMode`（dark=2），壳应用后打点
`[LANLU-SHELL] title buttons cfg applied visible=0x7 mode=2`；切换主题时
`themeChangeHandler` 立即重发（无需重启）。

**自绘面自动量测（P6 的可自动化部分，已完成）**：
用 `LANLU_PROBE_CAPTURE=1` 抓**应用自己的 surface**（逐帧文件 `cap_f{N}.rgba`，不采屏幕，隐私安全），
量测标题栏中部一行（y=50px）最后一个非底色像素的位置：

```
自绘面标题栏右侧留白 = 348px（系统三键区 ≈266px，业务层未再画三键）
```

348px = 16vp 右内边距 + 148vp 预留 + 主题钮内边距，与 `16 + (140+8) = 164vp × 1.9 = 311.6px`
的口径一致（多出部分为主题钮自身的内缩）。**引擎侧没有画任何三键图形**——这一点不再依赖人工目视。
截图存证：`/workspace/lanlu/tmp/cap_win.png`（应用登录页，右上仅主题钮 + 空白预留区）。

**关窗链路（2026-11-11 真机验证）**：用 `LANLU_PROBE_CLOSE=1` 让壳在启动 2s 后调用
`shell.lwpSendCloseRequest()`（与 `windowWillClose` 完全同一条下游路径），证据：

```
[LANLU-SHELL] probe close_request sent rc=1     ← 壳发出（native 组包成功）
lwp close request -> quit                        ← 引擎收到并决定退出
APP_EXITED                                       ← 进程已结束（应用干净退出）
```

`windowWillClose` 监听器本身也已注册成功（hilog `windowWillClose listener ok`）；
只剩"系统关闭钮真的被点击"这一步需要人工触发（OS 回调）。

> 设备于 2026-11-11 20:00 UTC 断开（`hdc list targets` 为空），之后的一次全量脚本复跑
> 因此失败；**设备 2026-11-12 00:00 UTC 恢复后已复跑全量脚本 PASS**（含关窗链路）。

**人工目视（2026-11-12 00:04 UTC，真机截图）**：应用窗口标题栏实际渲染为
"品牌 + 搜索 + 导航 + 主题钮 + 用户芯片 + **系统三键（最大化/最小化/关闭）**"，
右上角只有一组三键、无引擎自绘重影。存证：`/workspace/lanlu/tmp/tk_top.png`
（窗口 515,292 起 2090×160 裁切）。

> 说明：这次目视用的仍是整屏截图 + 窗口矩形裁切；因窗口当时在可见桌面且裁切只含应用窗口，
> 未涉及用户其它窗口内容。`LANLU_PROBE_CAPTURE` 的自绘面量测也保留，作为无隐私依赖的自动化判据。

**单测**：决策逻辑抽成纯函数 `titleButtonsWidthFor(platformProvides, rectVisible, rectWidthPx, scale)`，
4 个用例覆盖"不自绘/默认 148vp/按密度换算/除零兜底"（`client-next/src/ui/titlebar_test.cj`）。
宿主跑 client-next 测试需 ffmpeg 开发头（handoff 已知限制），本机由 CI 执行；OHOS 构建路径已编译通过。

- 266×70 px @ 屏幕密度 1.9 = **140×37 vp**，与官方文档/mihong 实测一致 → 壳的 vp2px 换算、
  napi 上报、引擎解码全链路通；
- `sysTop=0` → decor 仍隐藏，三键悬浮、不占布局（鼠标坐标口径不回归）；
- **注意**：本机截图只能拍到当前桌面（应用窗口在 sceneboard 的另一个虚拟桌面/工作区，
  `snapshot_display` 拍不到），因此"右上角只有一组三键"的目视确认要由人工切换到该窗口
  完成；自动化侧用 `ui title buttons width=..vp selfDrawn=false` 打点证明业务层走了
  "不自绘"分支。

**顺带修掉一个真实缺陷（P3 验证时发现）**：`g_ui_scale` 只由 `WindowCreated` 事件更新，
而该事件在启动期会被 `lwpAwait*` 消费掉，导致 `g_ui_scale` 一直是默认 1.0 ——
首版打点是 `width=266vp`（应为 140vp）。修法：三键宽度直接用 `lwindow.lwpReportedScale()`，
并在 lgpu 后端安装时用上报缩放初始化 `g_ui_scale`（顺带修掉"边缘热区用错缩放"的隐患，
见 known-limitations §2.5 的拖边缩放问题）。修复后真机打点 `width=140.000000vp`。

**真机探针已取到的硬事实**（`LANLU_BTN_PROBE`，真机 192.168.0.26，2026-11-11）：

- 模式 1（decor=false + `setWindowTitleButtonVisible(true,true,true)`）：
  `decor=false`、`getTitleButtonRect()` 返回 **0**、但 `windowTitleButtonRectChange` 事件给
  `w=140,h=37`（vp）→ **事件可用、查询不可用**；
- 模式 2（decor=true + `setWindowDecorHeight(37)`）：事件 `w=140,h=36`，窗口矩形不变
  （`sysTop` 仍 0）；
- 模式 3（decor=true + `DecorButtonStyle` 极值）：事件 `w=201,h=55`，参数被接受、无异常。

⇒ P2 必须**以事件为准**（`getTitleButtonRect` 兜底，取不到就用缓存/默认 140×37vp）。

---

## 1. 现状盘点（代码证据）

### 1.1 业务层自绘三键（要移除的东西）

| 位置 | 内容 |
|---|---|
| `client-next/src/ui/titlebar.cj:139-206` | `WinGlyph`（Min/Max/Close）枚举 + `WinControlButton` widget（38×30、hover/矢量图形/点击） |
| `client-next/src/ui/titlebar.cj:105-106` | `WIN_BTN_W/H` 尺寸常量；`:243` `WinSep` 分隔线 |
| `client-next/src/ui/titlebar.cj:1288-1290` | 主标题栏挂三键：min→`window.minimize()`、max→`toggleWindowMaximize(window)`、close→`ctx.requestClose()` |
| `client-next/src/ui/reader_bar.cj:279-281` | 阅读器顶栏复用同一组三键 |
| `client-next/src/ui/titlebar.cj:1209-1216` | `toggleWindowMaximize`：按 `windowFlags().maximized` 切 maximize/restore |

### 1.2 命令链路（现状：业务 → lgui → lwindow → LWP → 壳）

```
WinControlButton.onClick
  ├─ minimize()/maximize()/restore()      packages/cangjie-gui/lgui/src/window_controls.cj:60-68
  │    └─ headlessWindowCommand 变量（lgui 层的注入口，window_controls.cj:8）
  │         └─ client-next/src/ui/lgpu_backend.cj:328 接到 lwindow.requestWindowCommand()
  ├─ close → ctx.requestClose()           packages/cangjie-gui/src/core/theme_state.cj:301-303
  │    └─ shouldClose → desktop_app.cj:235 主循环退出 → 引擎进程退出 → 壳 appExited() → terminateSelf
  ▼
lwindow.lwpWindowCommand()                packages/lwindow/src/input_source.cj:233-241
  ├─ "minimize"→ requestState(8)、"maximize"→requestState(2)、"restore"→requestState(1)
  ├─ "close"   → requestCloseWindow()     window_client.cj:219-223
  ▼
LWP 协议 lw_window.set_state / lw_window.close   packages/lwp/protocol/window.toml
  ▼
壳 native 泵                              packages/lplatform-ohos/shell/native/lwp_window.cpp:375-377
  └─ g_window_state / g_close_requested   :519-526 take 系列导出
  ▼
ArkTS 400ms 轮询消费                       packages/lplatform-ohos/shell/arkts/pages/Index.ets:592-613
  └─ st===2 → win.maximize(); st===1 → win.restore(); close → win.destroyWindow()
```

**发现一个现存 bug**（迁移时顺带修，见 P2）：
`Index.ets:596-600` 的消费分支写成了——只要 `st !== 0` 就先按 st 分派 max/restore，
然后**无条件**再执行一次 `win.minimize()`。即：引擎每请求一次 maximize/restore，
窗口最终都会被最小化。该分支必须改为互斥分派。

### 1.3 平台层现状

| 事实 | 证据 |
|---|---|
| 系统标题栏已被隐藏（`setWindowDecorVisible(false)`，普通窗口非全屏），R49 真机取证 `sysTop=0` | `lplatform-ohos/shell/arkts/pages/Index.ets:740-746`；`lpack-ohos/templates/entry/src/main/ets/entryability/EntryAbility.ets:13-20`（loadContent 后调用，否则 1300002） |
| 内容区 = 窗口区，鼠标局部坐标 = display − 窗口原点，**无 chrome 偏移** | `docs/l-layer.md` R49/R50 结论；`verify-window.sh` 断言过滤器原点 == 窗口矩形原点 |
| 能力位只宣告真实现：SERVER_SIDE_DECORATIONS / CURSOR_SHAPES / IME_PREEDIT / SOFT_KEYBOARD / FILE_DIALOG_SAVE / CLIPBOARD_READ_ASYNC / VSYNC | `lplatform-ohos/shell/native/lwp_client.cpp:85-95` |
| OHOS 壳忽略 `begin_move`（系统 WM 负责）；拖动区 `setDragRegions` 在 P5 后是空实现 | `lwp_window.cpp:408-411`；`lgui/src/window_controls.cj:111-124` |
| Wayland 壳只置 `CAP_SERVER_SIDE_DECORATIONS` | `lplatform-wayland/src/shell.rs:908` |
| 引擎对 `lw_window.close_request` 的处理：记录 → 下一轮返回 `UiEvent.Quit` → 主循环退出 | `client-next/src/ui/lgpu_backend.cj:430-434, 496-500`；`desktop_app.cj:388` |
| 设备 API level 26；真机可连（hdc 在 `.research-ohos/tools/clt-7.0/.../toolchains/hdc`，target `192.168.0.26:42113`） | `lwp_client.cpp:87`；hdc 实测 |

### 1.4 SDK（API 26，clt-7.0）与"三键"相关的能力清单

均见 `.research-ohos/.../ets/api/@ohos.window.d.ts`（行号为该文件）：

| API | since | 作用 |
|---|---|---|
| `setWindowDecorVisible(bool)` / `getWindowDecorVisible()` | 11 / 18 | 开关整条系统标题栏；隐藏后内容区接管原标题栏空间 |
| `setWindowTitleButtonVisible(max, min, close?)` | 14 | **单独**显示/隐藏三键（max 隐藏时 restore 键一并隐藏） |
| `getTitleButtonRect()` → `TitleButtonRect{right,top,width,height}`（vp，窗口右上角） | 11 | 读取三键区域矩形 |
| `on/off('windowTitleButtonRectChange')` | 26.0.0 | 三键矩形变化事件（最大化/还原、样式调整后触发） |
| `setDecorButtonStyle(DecorButtonStyle)` | 14 | 三键样式/位置：colorMode、buttonBackgroundSize 20–40vp、spacingBetweenButtons 8–24vp、closeButtonRightMargin 6–22vp、buttonIconSize 16–24vp、cornerRadius 4–8vp |
| `setWindowDecorHeight(h)` / `getWindowDecorHeight()` | 11 | 标题栏高度（37–112vp 区间，见 getWindowDecorHeight 注释） |
| `on('windowWillClose', cb→Promise<boolean>)` | 15 | **仅**系统标题栏关闭钮触发的拦截回调：resolve(true)=不关，resolve(false)=继续关 |
| `startMoving()` | — | 须在 onTouch Down 回调内调用（ArkTS 侧才拿得到上下文） |
| `setTouchableAreas(rects)` | 26.0.0 | 窗口可触区（本次大概率用不上，列为备选） |

> 注：d.ts 里**没有**"decor 隐藏后仍渲染三键"的直接开关。用户前提若成立，
> 只能是以下组合之一（或设备/PC 模式的非文档行为），必须真机验证：
> ① `setWindowDecorVisible(false)` + `setWindowTitleButtonVisible(true,true,true)`；
> ② decor 可见但 `setWindowDecorHeight` 压到最小 + 栏体融入自绘背景（视觉上"无标题栏只有键"）；
> ③ decor 可见 + 引擎标题栏不再画右侧控制区（双栏合一观感）。
> 若 ①②③ 都不成立 → 走分支 B（平台层自绘三键 overlay，见 §3.2）。

---

## 2. 目标架构

### 2.1 目标消息流（分支 A：系统三键）

```
┌─ 平台层（lplatform-ohos 壳）───────────────────────────────────────┐
│ EntryAbility/Index.ets：                                            │
│   setWindowDecorVisible(...)          ← 按 P0 结论选择组合          │
│   setWindowTitleButtonVisible(...)    ← 消费引擎的 title_buttons 配置│
│   setDecorButtonStyle(...)            ← 位置/尺寸/明暗               │
│   on('windowTitleButtonRectChange') + getTitleButtonRect()          │
│        → shell.lwpTitleButtonsRect(x,y,w,h,visible)  （新增 napi）   │
│   on('windowWillClose') → lwp 泵发 lw_window.close_request           │
│        → resolve(false)（保持"关闭钮=退出应用"的桌面语义）           │
│ lwp_window.cpp 泵：                                                  │
│   新增解析 lw_window.set_title_buttons → g_title_buttons_cfg         │
│   新增推送 lw_window.title_buttons_rect 事件（rect 变化时）           │
└──────────────────────────────────────────────────────────────────┘
            ▲ hello 能力位：+ LWP_CORE_CAPABILITIES_TITLE_BUTTONS
            │
┌─ 协议层（lwp，只追加）───────────────────────────────────────────┐
│ window.toml [interface.lw_window] 段**末尾**追加：                   │
│   request  set_title_buttons(cfg)                                    │
│   event    title_buttons_rect(x,y,w,h,visible)                       │
│ core.toml  [bitfield.core_capabilities] **末尾**追加：                │
│   ["title_buttons", 131072]                                          │
│ → python3 tools/lwp-gen.py 重新生成；--check-abi 必须 PASS          │
└──────────────────────────────────────────────────────────────────┘
            │
┌─ 引擎侧（lwindow / lgui / client-next）───────────────────────────┐
│ lwindow/window_client.cj：setTitleButtons(cfg) + rect 事件解码/快照   │
│ lgui/window_controls.cj：headlessWindowCommand 保留（Wayland 回退用）│
│ client-next：                                                        │
│   · 启动时查询能力位：有 title_buttons → 壳侧发默认配置一次；        │
│     titlebar.cj / reader_bar.cj **不再创建** WinControlButton×3/WinSep│
│   · rect 事件 → 逻辑坐标换算 → 作为右侧避让区注入标题栏布局           │
│     （titleBarDragExclusions 同款机制）+ 右内边距 = rect.right+margin │
│   · 无能力位（Wayland/无装饰平台）→ 现状自绘三键，行为零变化          │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 分支 B（P0 证伪系统三键时的降级形态）

保持 `setWindowDecorVisible(false)`（几何/输入零回归），由 **平台层**（ArkTS Stack 顶层或
native overlay）画三键并处理点击 → 直接调 `win.minimize()/maximize()/restore()` 与
`windowWillClose` 等价路径；协议消息与能力位**不变**（同一套 `set_title_buttons` /
`title_buttons_rect`，只是壳的实现从"调系统 API"换成"自绘 + 上报矩形"）。
业务层改动完全一致——这就是把三键放进平台层的意义：**分支切换不触碰业务代码**。

### 2.3 统一语义（两分支共用）

| 语义 | 决定 |
|---|---|
| 关闭键 | 系统关 → `lw_window.close_request` → 引擎现有 `UiEvent.Quit` → 退出。不做"阻止关闭"守卫（登录确认弹窗是应用内流程，与此无关；未来要拦截再加 `set_close_guard`，协议允许追加） |
| 最大化键 | 最大化态再点 = 还原（系统行为自带，引擎的 `toggleWindowMaximize` 仅保留给自绘回退路径） |
| 最小化键 | `set_state(8)` 语义保持不变（壳解释为 minimize） |
| 矩形单位 | 协议事件报**窗口局部物理 px**（与 `surface.available` 口径一致）；ArkTS 侧的 rect 是 **vp**，壳层 `ui.vp2px()` 换算后再发（官方示例 `px2vp` 反向同理；mihong OnCaptionButtonRectChange 同款做法）；引擎按 `window.created.scale` 转逻辑坐标 |
| 样式/位置参数 | `set_title_buttons` 载荷：visible 位掩码(u32: bit0=max bit1=min bit2=close)、side(u32: 0=右 1=左)、close_margin(u32 vp)、spacing(u32 vp)、button_size(u32 vp)、color_mode(u32: 0=跟随系统 1=light 2=dark)。壳按 SDK 支持范围 clamp 后逐项 best-effort 应用（`setDecorButtonStyle` 合法范围见 DecorButtonStyle 文档：margin 6–22 / spacing 8–24 / size 20–40vp）；**实际生效矩形以 rect 事件为准**（配置回执不另设消息）。非自由窗口设备调用返回 801 → try-catch 跳过 |
| 主题联动 | ✅ 已实现：`main.cj` 启动时按已保存主题设 colorMode、`themeChangeHandler` 里切换主题即重发 `set_title_buttons`；真机打点 `cfg sent=true colorMode=2` + 壳 `cfg applied mode=2` |

---

## 3. 里程碑

### P0 — 已完成：机制证实（引用既有实现，无需再测）

**结论：分支 A 成立。** 官方文档（devecocli docs，HarmonyOS 知识库）+ 参照实现双证：

1. **官方指南《应用适配自由窗口》§调整布局避让标题栏和窗口三键**（guides/harmonyos-guides/
   应用框架/ArkUI/窗口管理/窗口模式/自由窗口）：明确给出标准做法——
   "① 通过 `setWindowDecorVisible()` 隐藏标题栏；② 通过 `getTitleButtonRect()` 或
   `on('windowTitleButtonRectChange')` 获取三键位置尺寸，页面顶部布局时去除三键区域"，
   并附完整示例代码（`updateTitleButtonRect` 里 `topAreaWidth = px2vp(drawableRect.width) -
   titleButtonRect.width`，`topAreaHeight = titleButtonRect.height`）。
   即：**隐藏标题栏保留三键 + 业务顶部避让**就是华为推荐的形态，本计划分支 A 与之完全同构。
2. **官方 API 参考**：
   - `setWindowDecorVisible`（API 11）："设置窗口标题栏是否可见，对存在标题栏和三键区的
     窗口形态生效" —— 只去标题栏，不动三键；
   - `getTitleButtonRect`（API 11）返回 TitleButtonRect；`windowTitleButtonRectChange`
     事件随布局/最大化变化触发；
   - `setWindowTitleButtonVisible`（API 14）与 `setDecorButtonStyle`（API 14）：**设备行为
     差异注明"仅自由窗口状态设备可正常调用，否则 801"** —— 本设备为自由窗口形态可用；
   - `setWindowDecorHeight`（API 11）：自由窗口下窗口尺寸含标题栏高度，隐藏后内容区接管
     原标题栏空间（与 R49 `sysTop=0` 取证一致）；
   - 悬浮标题栏高度固定 37vp（全屏沉浸 hover 时出现，`setTitleAndDockHoverShown` 可关）。
3. **参照实现**（mihong，同设备）：`caption-avoid-1030.md` 实测 decor=false 后三键仍由系统
   绘制（native 收到 `OnCaptionButtonRectChange: 266×70 px` ≈ 140×37vp × 1.9 密度），
   `AppWindowBridge` 有完整的"事件注册 + vp2px + 建窗后补发 + `getTitleButtonRect` 兜底"链路。
4. **本仓探针交叉验证**（LANLU_BTN_PROBE=1）：decor=false 时事件回调 `w=140,h=37`(vp)，
   与文档、mihong 实测三方一致。

**实现口径（合并官方文档与 mihong 踩坑）**：
- `windowTitleButtonRectChange` 与 `getTitleButtonRect` 给 **vp**；`right/top` 本机为 0，
  **只有 width/height 可靠**，避让按 width 计算（mihong 实测，文档未承诺 right/top 非零）；
- 壳层下发引擎前必须 `ui.vp2px()` 换算（mihong OnCaptionButtonRectChange 同款）；
- 全屏/隐藏三键时事件给 0 尺寸 → 避让自动消失（官方指南注 + mihong 注一致）；
- `setDecorButtonStyle`/`setWindowTitleButtonVisible` 在非自由窗口设备返回 801 ——
  壳层调用要 try-catch 并按失败跳过（能力位仍可置：rect 事件链路不依赖这两个 API）。

一次性探针代码（`LANLU_BTN_PROBE`，Index.ets/EntryAbility.ets）在 P2 落地正式实现后删除。

### P1 — 协议追加（纯协议 PR，可独立合入）

1. `packages/lwp/protocol/window.toml`：lw_window 段**末尾**追加 `set_title_buttons`
   请求与 `title_buttons_rect` 事件（载荷见 §2.3）；
2. `packages/lwp/protocol/core.toml`：capabilities **末尾**追加 `title_buttons` 位；
3. `python3 tools/lwp-gen.py` 重新生成；`python3 tools/lwp-gen.py --check-abi` PASS；
4. `packages/lwp/src/lwp_encode.cj` 编解码 + `packages/lwp/test.sh` 全绿；
5. `docs/lwp-message-coverage.md` 决策表加两行（触发条件：壳置位才用）；
   `tools/check-docs-consistency.py` 基线数字更新（62 → 64 条）。

验收：所有协议守卫 PASS；无引擎/壳改动（本里程碑可独立回滚）。

### P2 — OHOS 壳实现（平台层主体）

文件清单（全部在 `packages/lplatform-ohos` 与模板）：

1. `shell/native/lwp_client.cpp`：P0 通过后在 hello 置 `LWP_CORE_CAPABILITIES_TITLE_BUTTONS`；
2. `shell/native/lwp_window.cpp`：
   - 泵解析 `lw_window.set_title_buttons` → `g_title_buttons_cfg` + take 导出；
   - 新增 `lwp_title_buttons_rect` 推送（rect 变化才发，防刷屏）；
3. `shell_napi.cpp` + `types`：新增 `lwpTakeTitleButtonsConfig()`、
   `lwpTitleButtonsRect(x,y,w,h,visible)` 导出；
4. `shell/arkts/pages/Index.ets`：
   - aboutToAppear 按 P0 组合设置 decor / 三键可见性 / DecorButtonStyle；
   - 订阅 `windowTitleButtonRectChange` + 初始 `getTitleButtonRect()` → napi 上报；
   - `on('windowWillClose')` → `shell.lwpCloseRequest()`（复用 close_request 泵路径）
     + resolve(false)；
   - **顺手修 §1.2 的 minimize bug**：`st` 分支互斥化（2→maximize，1→restore，8→minimize，
     其余忽略），去掉无条件 minimize；
5. `lpack-ohos/templates/entry/src/main/ets/entryability/EntryAbility.ets`：decor 设置与
   Index.ets 保持同一结论（或收敛为只在 Index.ets 设置，模板删重复调用——P0 后定）；
6. `selftest/run-tests.sh`：加配置载荷编码/Clamp 用例。

验收（真机）：
- 启动后三键可见、位置与 P0 结论一致；`getTitleButtonRect` ≈ 截图实测像素（±2px）；
- 点 max → 最大化且 rect 事件到达引擎（`--ps lanlu.env.LANLU_LWP_TRACE` 的 .lwtrace 可见
  `title_buttons_rect`）；还原后 rect 再变化；**max 之后窗口不再被最小化**（bug 修复判据）;
- 点系统关闭 → 引擎退出 → 应用 `terminateSelf`，无空窗残留；
- `bash packages/lplatform-ohos/selftest/run-tests.sh` PASS。

### P3 — 引擎侧接入（业务层去三键）

1. `packages/lwindow/src/window_client.cj`：`setTitleButtons(cfg)` 发送 +
   `title_buttons_rect` 解码 → 快照查询 API（`titleButtonsRect()` → 逻辑坐标）+
   能力查询 `titleButtonsSupported()`；单测进 `window_client_test.cj`（`cjpm test` 39→41+）；
2. `client-next/src/ui/lgpu_backend.cj`：rect 事件消费进快照；启动且能力位置位时发一次
   默认配置（三键全显、跟随系统主题）；
3. `client-next/src/ui/titlebar.cj`：
   - `titleBar()` 与 `readerBar()`（经 `reader_bar.cj`）在 `titleButtonsSupported()` 时
     **不创建** WinControlButton/WinSep，右内边距改为 `rect.right + 8vp` 避让；
   - `WinControlButton/WinGlyph/WinSep/toggleWindowMaximize` 保留（Wayland/无装饰回退 +
     宿主测试仍覆盖），代码注释标注"仅平台无三键能力时使用"；
4. `client-next/src/ui/titlebar_test.cj`：加"带避让区的布局"用例；
5. 宿主 headless 测试不置能力位 → 全部回退路径行为零变化（246 个测试不受影响）。

验收：
- `cd packages/lwindow && cjpm test` 全绿；client-next `cjpm test`（CI/装 ffmpeg 后）全绿；
- 真机目视：标题栏右侧三键只出现**一份**（系统的），引擎侧无重影、无空位错位；
- 搜索框/过滤按钮等右缘控件与系统键不重叠（截图 + uitest dumpLayout 双验证）。

### P4 — Wayland 壳对齐（不实现能力，只对齐语义）

- `lplatform-wayland` 不置 `title_buttons` 位（现状 caps 即满足）；引擎自动走自绘回退；
- `cargo test` 11 项不回归；协议文档标注"Wayland 侧预留，触发条件：未来做 CSD 装饰键"。

### P5 — 守卫、文档、清理

1. `tools/check-platform-isolation.py` 基线复核（新 SDK 调用只出现在 lplatform-ohos /
   lpack-ohos，业务层 0 新增平台标识）；
2. `tools/check-deps.py` / `check-layering.sh` / `check-no-file-bridge.sh`（必须仍为 2 处基线，
   **本计划全程禁止文件桥**）/ `check-no-sdl.sh` 全绿；
3. `docs/lwp-platform-api.md` 重新生成（新增 lwindow API 归类为"引擎实际使用"）；
4. `docs/lwp-known-limitations.md`：记录"三键位置仅右上角区域内可调（margin/spacing/size），
   不支持任意摆放（SDK 无对应 API）"与分支结论；
5. `docs/l-layer.md` R49 结论追加"P5T 三键平台化后的几何口径"（若走组合 2，
   补 chrome 补偿公式与实测值）；
6. 回归：`bash packages/lpack-ohos/tools/verify-window.sh`（若 sysTop ≠ 0，断言式改为
   过滤器原点 == 窗口原点 + chromeTop）。分支 A 保持 decor=false，断言应原样通过。

### P6 — 真机整体验收（ MOR 判据）

| # | 判据 | 方式 |
|---|---|---|
| 1 | 标题栏（引擎自绘部分）内容不回归：搜索/导航胶囊/主题钮/用户芯片正常 | 截图对照 R62 调色板 |
| 2 | 三键由系统渲染、点击行为正确（min/max/restore/close × maximized 态） | 人工 + hilog/trace |
| 3 | maximize ↔ restore 三键矩形事件全链路（.lwtrace verify PASS） | `tools/lwtrace.py verify` |
| 4 | 输入坐标无偏移：`ohos-input-probe.sh 690 21` 三条日志（cursor shape / ime cursor / frames=） | 既定流程 |
| 5 | 连续 resize / 最大化往返 20 次不崩（沿用 MOR-M1 #6） | 既定脚本 |
| 6 | 回退开关：能力位摘除后引擎自绘三键恢复（验证特性开关闭环） | 改 hello 位重装对比 |

---

## 4. 风险与回归面

| # | 风险 | 缓解 |
|---|---|---|
| R1 | decor 形态改变输入坐标口径（若误用组合 2/3 令 `sysTop>0`，局部坐标整体偏移） | **分支 A 保持 `decor=false` 不变**（sysTop=0 的 R50 结论继续成立，三键悬浮于 surface 上不占布局）；探针模式 2/3 已确认无必要，删除相关探针分支 |
| R2 | 引擎内容与系统键重叠（引擎按全窗布局，系统键浮在右上） | rect 事件 → 逻辑避让区，注入 titlebar 布局右内边距；P3 有专项验收 |
| R3 | rect 单位/坐标系口径错（SDK 报 vp、引擎吃 px） | §2.3 定死"事件=窗口局部 px"，换算只写在壳层一处；P2 验收用截图像素对账 |
| R4 | `windowWillClose` 回调里 resolve 遗漏导致关不掉/双关 | 壳侧封装成"先发 close_request 再 resolve(false)"，异常路径兜底 resolve |
| R5 | 平台差异：Wayland/宿主无此能力 | 能力位驱动，未置位 = 现状（自绘），宿主 246 测试零改动 |
| R6 | 协议追加破坏 ABI | 追加到接口段末尾 + `lwp-gen.py --check-abi` 门禁（P1 独立 PR，可单独回滚） |
| R7 | EntryAbility 与 Index 两处 decor 设置漂移 | P2 第 5 项收敛为单点；模板与壳同 PR |
| R8 | 深浅色切换后系统键颜色不随业务主题 | 若 P0 证明 colorMode 可调 → 主题切换时重发配置；否则记入 known-limitations |

## 5. 明确不做（Out of scope）

- 不做"关闭拦截守卫"（`set_close_guard`）：现有桌面语义 = 关闭即退出，业务确认弹窗（登出）
  是应用内流程；需要时协议允许追加，不在本期。
- 不做任意位置摆放（左下角、自由坐标）：SDK 只支持右上角区域内 margin/spacing/size 调整。
- 不做三键的引擎侧重绘主题化（贴图/自绘叠加系统键）：系统键样式归系统。
- 不动 `begin_move`/拖动：OHOS 仍由系统 WM 管理（分支 A 下系统栏自带拖动，
  顺带补上现状"引擎标题栏拖不动窗口"的体验缺口）。
- 不碰 `attach.serial`/dmabuf/子进程拆分（handoff 已另列）。

## 6. 每轮必跑守卫（沿用 handoff 清单）

```bash
python3 tools/check-deps.py && python3 tools/check-platform-isolation.py \
  && bash tools/check-no-file-bridge.sh && bash tools/check-layering.sh && bash tools/check-no-sdl.sh \
  && python3 tools/lwp-gen.py --check && python3 tools/lwp-gen.py --check-abi \
  && bash packages/lwp/test.sh && bash packages/lplatform-ohos/selftest/run-tests.sh \
  && (cd packages/lwindow && cjpm test) && (cd packages/lplatform-wayland && cargo test)
```

真机流程：`build-ohos.sh → sign-hap.sh → hdc install -r → aa start →
tools/ohos-input-probe.sh 690 21`（hdc 路径见 §1.3）。
