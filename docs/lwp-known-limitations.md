# 已知限制与"故意留白"清单（2026-11-11）

本文件记录**代码里真实存在、但可能被误认为 bug 或遗漏**的行为。
分两类：① 协议/平台能力上的已知限制；② 代码里刻意保留的空实现（ABI 或分层需要）。

> 代码里没有 `TODO`/`FIXME`（全仓仅 6 处注释级标记，均为说明性文字）。
> 这不代表"没有缺口"—— 缺口都在下面列着，只是没有以 TODO 形式散落在代码里。

## 1. 协议与平台能力限制

| 限制 | 位置 | 影响 | 现状/原因 |
|---|---|---|---|
| `clipboard.set` 忽略 mime，恒按 `text/plain` 处理 | `lplatform-ohos/shell/native/lwp_window.cpp:367` | 写入富文本/图片时只带纯文本 | OHOS pasteboard 侧只做纯文本；Wayland 侧已支持 mime 协商 |
| ~~OHOS 不消费 `attach.serial`~~ | — | **已修复（第 110 轮）** | 壳现在统计帧数/最近 serial/倒退次数，ArkTS 每 ~5s 打一条 `frames=…` 日志 |
| 运行期改标题/尺寸约束需壳侧窗口 API 支持 | 两平台壳 | 桌面环境若无 `xdg_toplevel` 权限可能被合成器忽略 | 已实现（第 112 轮） |
| OHOS 无 dmabuf 路径 | — | 无法零拷贝共享 GPU 缓冲 | 直渲染方案不需要；Wayland 侧走 wl_shm |
| Wayland 壳未实现的能力位不置位 | `lplatform-wayland/src/shell.rs:26` | 引擎据此走降级路径（设计如此） | 约定见计划 §5.3 |
| 拖放只传 uri 列表，未传 mime/动作 | `lw_window.drag_*` | 无法区分"复制/移动"意图 | 需要产品语义后才能定协议字段 |
| 滚轮单位是"逻辑刻度"（÷45） | ArkTS `onAxisEvent` | 与系统设置的回滚速度可能不完全一致 | 沿用了文件桥时期的换算 |
| 引擎只在有绘制需求时提交帧 | `lwpFrameTick` | 静止时 `frames` 计数不增长（这是正常的按需渲染，不是丢帧） | vsync 每帧仍回 `frame.done` |

## 2. 刻意保留的空实现

| 空实现 | 位置 | 为什么保留 |
|---|---|---|
| `lanlu_clipboard_*` 系列遗留函数 | `shell_napi.cpp:963` | M6 第 2 步已改走协议；保留空壳避免 napi 导出表变化（ETS 侧仍引用） |
| `lanlu_input_calibrate_*` 占位 | `input_filter.cpp:108` | 保留 ABI；实际校准已内联到过滤器里 |
| `Cursor.system()` 返回空光标对象 | `lgui/input/cursor.cj` | 无 SDL 光标；形状请求通过 `cursorSink` 交给平台层 |
| `Window.setTextInputArea` 默认空实现 | `lgui/window.cj` | 平台层通过 `textInputAreaSink` 接管；未注册时静默无操作 |
| `window.set_state` 在 Wayland 映射为 xdg 请求，在 OHOS 由系统处理 | 两平台壳 | 平台差异，不是缺失 |
| `begin_move` 在 OHOS 被忽略 | `lwp_window.cpp` | 系统窗口管理器负责拖标题栏移窗 |

## 2.6 浅色模式"过曝"测量结论（第 117 轮，待用户复核）

**测量**（截屏 PNG，同一物理屏）：
- 窗口内平均灰度 **254/255**（设计 bg F8F8FA=248、面板 FFFFFF=255 → 平均应 ~250）
- 桌面壁纸同屏区域 **230/255**
- 截图色彩空间 sRGB、gamma 0.4545，无 HDR 标记；RenderService dump 无 HDR/gamut 字段

**分析**：系统截屏是 sRGB 直出，窗口像素 254 比设计值 ~250 高 4/255（1.6%）。
在 sRGB 上 250→254 视觉差极小，但大面积纯白 + 白色卡片(255) 与 bg(248) 只差 7 级，
**没有层次** —— 与"糊成一片的过曝感"一致。

**已调整**（第 117 轮构建）：`LANLU_L_BG` F8F8FA→EFF1F5、面板 FFFFFF→FBFCFE、
Theme.light 同步。**待装机后请你再看一眼**：如果还是刺眼，下一步查 swapchain
（wgpu 选了 sRGB 格式，理论正确；需 dump 实际 surface format）。

## 2.5 DPI 缩放（第 116 轮修复）

| 项 | 状态 |
|---|---|
| 系统密度上报（`window.created.scale`） | ✅ ArkTS 从 `display.densityPixels` 上报 |
| 逻辑尺寸 = 物理 ÷ scale | ✅ `preferredWindowGeometry` |
| 渲染放大（`canvas.scale`） | ✅ protocol 路径已修（曾硬编码 1.0） |
| **拖边缩放** | ❌ **未接通**：边缘判定用逻辑坐标但 `g_win_w` 是物理尺寸，永不命中 |

## 3. 需要外部条件才能关闭的缺口

见 [lwp-acceptance-report.md](lwp-acceptance-report.md) §4，摘要：

1. 拖放业务语义（**需产品决策**）；
2. 滚轮人工验证（需人工滚一次）；
3. xdg-desktop-portal（需 D-Bus）；
4. 真实合成器目视验证（需桌面环境）；
5. 引擎渲染到 Wayland fd（需 `lgpu` 改动 + 验证环境）。

## 4. UI 层的"暂未实现"

`client-next/src/ui/settings_view.cj` 等处会弹「设置暂未实现 / 功能暂未实现」的 toast ——
这是**产品未完工**的显式提示（点击有反馈、不假装成功），不是壳或协议的问题。
