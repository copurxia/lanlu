# 协议消息覆盖表（2026-11-11）

**问题背景**：第 110 轮发现 `surface.attach` 虽然定义完整、两端 API 都在，
但**引擎从来没调用过** —— 属于"看着实现了"。本表把所有消息的**方向与实现状态**摊开。

**方法**：解析 `packages/lwp/protocol/*.toml`（64 条消息；2026-11-11 新增三键 2 条，见 §C），
对每条在源码里检索"发送侧/接收侧"是否出现对应 opcode 常量或编码函数（排除测试文件），
再**逐条人工复核**。启发式扫描会有漏判（例如 Wayland 侧用自己的常量名），所以下表以人工结论为准。

## 结论：64 条中 52 条双向实现；剩下 12 条已逐条定性（8 条预留 + 4 条已实现但扫描漏判），另有 2 条新增（§C，壳侧待实现）

### A. 决策表：剩下 12 条怎么处理（2026-11-11 定）

对每条给出**明确决策**，不再停留在"未实现"这种模糊状态。

| 消息 | 方向 | 决策 | 理由 / 触发条件 |
|---|---|---|---|
| `lw_seat.capabilities` | 壳 → 引擎 | **保留（预留）** | 能力已由 `hello.capabilities` 一次性告知；此事件专用于**运行期热插拔**（插拔鼠标/键盘）。触发条件：支持热插拔时实现 |
| `lw_seat.lock_cursor` | 引擎 → 壳 | **保留（预留）** | 游戏/拖拽锁定光标用；当前阅读器无此场景。触发条件：做全屏阅读/游戏时实现 |
| `lw_app.quit` | 引擎 → 壳 | **保留（预留）** | 与 `lw_app.exit` 语义区分：`exit`=引擎主动退出进程，`quit`=请壳走自己的退出流程（如先存盘）。当前只用 exit |
| `lw_text_input.set_surrounding` | 引擎 → 壳 | **保留（预留）** | 输入法联想/纠错需要上下文；`lgui` 侧有文本状态但未上报。触发条件：接入需要上下文的输入法 |
| `lw_text_input.preedit` | 壳 → 引擎 | **保留（预留）** | 当前预编辑由 ArkTS 输入法面板自绘，引擎不需要；若将来要自绘候选/预编辑则启用 |
| `lw_core.ping` / `pong` | 双向 | **保留（预留）** | 保活/测延迟；当前 eventfd 唤醒足够。触发条件：发现壳/引擎卡死需探活时 |
| `lw_core.error` | 壳 → 引擎 | **保留（预留）** | 协议级错误回报；现在用 `lwp_stats` 计数替代。触发条件：需要把错误原文给用户看时 |
| `lw_window.set_title` | 引擎 → 壳 | ✅ 已实现（第 112 轮） | Wayland `xdg_toplevel.set_title`；OHOS `setWindowTitle`（真机 `window title -> Lanlu`） |
| `lw_window.set_min_max` | 引擎 → 壳 | ✅ 已实现（第 112 轮） | Wayland `set_min_size/max_size`；OHOS `setWindowLimits`（真机 `window limits applied`） |
| `lw_text_input.enable` / `disable` | 引擎 → 壳 | ✅ 已实现（第 113 轮） | 焦点变化时引擎通知壳，壳 attach/detach 输入法（真机 `ime want=on`） |
| `lw_frame.done` | 壳 → 引擎 | ✅ 已实现（启发式漏判） | OHOS 每秒 ~60 条，Wayland 合并回执 |
| `lw_core.hello_ack` | 引擎 → 壳 | ✅ 已实现（启发式漏判） | 握手时引擎回，liblwp 内部消费 |

**结论**：**没有需要立刻删除的消息**。8 条是"协议预留"，每条都写清了触发条件；
4 条是已实现但启发式扫描漏判的（人工确认正常）。

### C. 2026-11-11 新增：三键平台化 2 条（docs/lwindow-title-buttons-plan.md）

| 消息 | 方向 | 现状 | 触发条件 / 说明 |
|---|---|---|---|
| `lw_window.set_title_buttons` | 引擎 → 壳 | **协议已定，编码已实现；壳侧待实现（P2）** | 引擎配置平台三键（可见性/位置/尺寸/明暗）。OHOS 壳映射 `setDecorButtonStyle`/`setWindowTitleButtonVisible`（801 时跳过）；Wayland 壳不置能力位、忽略 |
| `lw_window.title_buttons_rect` | 壳 → 引擎 | **协议已定；壳侧待实现（P2）** | 平台三键矩形（窗口局部 px）+ 可见性，触发源：`getTitleButtonRect()` 初值 + `windowTitleButtonRectChange`。引擎据此做右侧/顶部避让；width=0 表示无三键 |

能力位：`core_capabilities.title_buttons`（bit17 = 131072）。**只有壳真的能上报矩形才置位**，
否则引擎走自绘回退（Wayland 当前不置位）。

### B. 为什么保留预留消息而不是删掉

协议一旦发布，删消息要改 `protocol_major`；而这条通道的设计目标之一就是
"把平台差异提前建模"（计划 §5）。**预留 + 写明触发条件**比删掉再重新加更便宜。

代价是覆盖表需要**定期复核**（本轮就是一次），避免"预留"变成"永远没人管"。

## 与"必须发"的规则配套

`docs/lwp-verification-discipline.md` 第 10 条：**文档里写了"必须发"的消息，
必须有测试或打点证明它真的在发**。已兑现的例子：

- `surface.attach`：第 110 轮修复后，壳侧 `frames=` 日志 + trace 双重证明；
- `lw_seat.set_cursor`：hilog `cursor shape`；
- `lw_text_input.set_cursor_rect`：hilog `ime cursor`；
- `lw_frame.request/done`：trace 成对计数。

**未兑现的**（即上表 A/B 中"壳不处理"的项）在实现前不应写进"已完成"清单。
