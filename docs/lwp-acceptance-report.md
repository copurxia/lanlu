# LWP 平台分离 —— 验收报告（2026-11-11）

本报告是"按计划推进"的可复核汇总：每条都附 command / 输出，不写"应该可以"。
逐轮过程见 [lwindow-plan-progress.md](lwindow-plan-progress.md)，计划正文见
[lwindow-platform-separation-plan.md](lwindow-platform-separation-plan.md)。

## 1. 自动化守卫与测试（本机可复现）

| 项 | 命令 | 结果 |
|---|---|---|
| 文件桥只减不增 | `bash tools/check-no-file-bridge.sh` | PASS（2 处，M6 前为 35） |
| 依赖白名单 | `python3 tools/check-deps.py` | PASS（10 条已知，未新增） |
| 平台隔离 | `python3 tools/check-platform-isolation.py` | PASS（73 处已知，未新增） |
| 业务层无平台代码 | `bash tools/check-layering.sh` | PASS |
| 去 SDL 进度尺 | `bash tools/check-no-sdl.sh` | PASS |
| 协议生成物最新 | `python3 tools/lwp-gen.py --check` | PASS（64 消息 / 13 接口） |
| 协议 ABI 兼容 | `python3 tools/lwp-gen.py --check-abi` | PASS（56 → 62，无破坏性变更） |
| 协议 + 通道 + 录制 | `bash packages/lwp/test.sh` | PASS |
| 引擎侧窗口客户端 | `cd packages/lwindow && cjpm test` | **40 / 40 通过** |
| OHOS 壳发送端 | `bash packages/lplatform-ohos/selftest/run-tests.sh` | PASS |
| Wayland 壳 | `cd packages/lplatform-wayland && cargo test` | **25 / 25 通过**（9 协议 + 15 假合成器 + 1 wire） |
| Linux 打包脚本 | `bash packages/lpack-linux/tools/build-deb.sh --self-test` | PASS（生成 .deb，10 个条目） |

## 2. OHOS 真机验收（HUAWEI MOR-M1，API 26）

| # | 判据 | 结果 |
|---|---|---|
| 1 | 指针/键盘输入经协议到达引擎 | ✅ 140 motion + 4 button + key 事件 |
| 2 | `lwp stats` 计数器 | ✅ `sent=653 recv=653`，dropped/bad/unknown/notHandshaked 全 0 |
| 3 | `lwp violations` | ✅ unackedConfigure/frameTimeout/attachOutOfOrder 全 0 |
| 4 | 文件桥停用 | ✅ 代码已删（守卫 2 处）；运行期无 bridge 日志 |
| 5 | 调试开关受控 | ✅ `lanlu_env.txt` 仅 debug 构建生效 |
| 6 | resize 不崩溃 | ⚠️ 系统**支持**拖边缩放（实测过一次 2090×1394 → 2413×1729），但脚本复现不稳定（起点差几像素就变成内容点击）；进程在多次拖动后均存活。第 54 轮的 54 次 resize 是通过「最大化/还原」路径验证的 |
| 7 | 协议取证 | ✅ 1299 条记录，`lwtrace verify` PASS |
| + | 光标形状 | ✅ `lw_seat.set_cursor` 上链并被系统应用（hilog `cursor shape 0/1`） |
| + | IME 候选框定位 | ✅ `lw_text_input.set_cursor_rect` ×29，hilog `ime cursor 1022,309`（含窗口偏移） |
| + | 帧闭环 | ✅ `frame.request` 281 / `frame.done` 142（vsync 合并回执，按水位记账不误报超时） |
| + | **帧提交（attach）** | ✅ 第 110 轮修复：引擎此前**从不发** `surface.attach`；现已每帧提交（trace 中 133 条），壳侧统计 `frames=90 lastAttachSerial=180 backwards=0` |
| + | **画面回归** | ✅ 启动快照 PNG sha256 `5a274b9e…`，与第 68/91 轮**逐字节相同** |

## 3. Wayland 侧（本机无合成器，用假合成器 + CI 冒烟）

假合成器是手写的 wire 级实现（`tests/mock_compositor.rs`），覆盖：

- 全局枚举；建窗 + configure/ack；`surface.changed`
- 指针/键盘转发（坐标按 `wl_fixed` 精确断言 12.5/34.5）
- `wl_shm` 上屏（含缓冲复用）、**SCM_RIGHTS fd 传递**
- 窗口状态（maximize/fullscreen/close）、DPI（单屏 + 多屏切换）
- 剪贴板 set / get / mime 协商 / **receive 的真实 fd 路径**
- 拖放（enter/motion/leave/drop + uri 解码）
- 拖动/缩放（`xdg_toplevel.move/resize`）

CI 侧另有 `tools/smoke-weston.sh`（真实合成器冒烟，本机缺 weston 时跳过、CI 用 `--require` 强制）。

## 4. 已知缺口（如实列出）

| 缺口 | 性质 | 说明 |
|---|---|---|
| ~~无边框窗口没有 resize 边缘~~ | **已澄清：不是缺口** | 第 101 轮我判断"拖边不能缩放"是**测错了**（拖动起点落在窗口外）。第 102 轮用窗口内坐标复验：系统原生支持无边框窗口拖边缩放，`surface.changed` 记录了尺寸变化。自绘热区的代码已撤掉，避免与系统重复处理 |
| 滚轮 | 待人工验证 | 已接线（ArkUI `onAxisEvent` → `pointer_axis`），`uitest` 无法注入滚轮 |
| 拖放的业务语义 | 待决策 | 壳与引擎侧都已接通并打点；"拖到书库=导入？"属产品决策 |
| xdg-desktop-portal | 需环境 | 文件对话框/Settings 需要 D-Bus 会话 |
| 真实合成器目视验证 | 需环境 | 本机无 weston/sway；CI 冒烟只验证握手 |
| 引擎渲染到 Wayland fd | 需引擎改动 | 壳侧 wl_shm 已通；lgpu 需要"渲染到内存"的导出 |
| OHOS 的 `attach.serial` 消费、dmabuf | 需设备复验 | 协议字段存在；OHOS 走直渲染，当前不需要 |

## 5. 结论

- **OHOS 主线（M0/M1/M2/M3/M6）**：完成并通过真机验收。
- **Wayland 线（M1W/M2W/M3W）**：本机可验证部分全部完成（25 项自动化测试）。
- **剩余全部需要**：产品决策、真实桌面环境、或设备人工操作。
