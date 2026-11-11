# M6 删除清单（文件桥退役）—— 执行手册

> **执行状态（2026-11-11）：第 1~4 步已完成，基线 35 → 2 处。**
> - 第 1 步输入（`input_events`/`key_events`/`text_input`）✅ 第 55 轮
> - 第 2 步剪贴板（`clip_*.txt`，含原生 pasteboard 线程）✅ 第 56 轮
> - 第 3 步对话框（`filedlg_*`）✅ 第 57 轮
> - 第 4 步窗口命令与抓帧（`window_cmd.txt`/`snapshot_req.txt`）✅ 第 57 轮
> - 第 5 步（`appExited` 轮询）与第 6 步（联调开关）**未执行**：
>   前者已由 `lw_app.exit` 覆盖但旧静态标志仍在；后者定案保留。
> 每步的真机复验记录见 `docs/lwindow-plan-progress.md` 对应轮次。

计划：[lwindow-platform-separation-plan.md](lwindow-platform-separation-plan.md) §11。
基线：`tools/file-bridge-baseline.toml`（**35 处**，`bash tools/check-no-file-bridge.sh --report`）。

本文件是 **M6 真正动手时的操作手册**。现在（M2/M3 阶段）所有回落分支都在运行时停用但代码保留，
原因见文末「为什么现在不删」。

## 删除顺序与判据

每一步都必须满足：① `LANLU_LWP=1` 真机验收通过；② `file-bridge-baseline` 计数下降；
③ 全量测试绿。**顺序不可颠倒**——先删引擎读侧、再删壳写侧，反过来会让壳白写一段时间的文件。

### 第 1 步：输入（`input_events` / `key_events` / `text_input`，基线 7 处）

| 删除对象 | 位置 | 调用方（需同步改） |
|---|---|---|
| `readInputEvents()` | `packages/lwindow/src/events.cj` | `client-next/src/ui/lgpu_backend.cj:161,277` |
| `readTextInputs()` | 同上 | `lgpu_backend.cj:265` |
| `readKeyEvents()` | 同上 | `lgpu_backend.cj:270` |
| `lanlu_bridge_append("input_events.txt" ...)` 写点 | `packages/lplatform-ohos/shell/native/shell_napi.cpp`（`lanlu_push_input` 的回落分支） | — |
| `push_key_name2` 的文件回落 | `shell_napi.cpp` | — |
| `lanlu_send_text` / `SendText` 的文件回落 | `shell_napi.cpp` | — |

判据：`lgpu_backend.cj` 里三处 `readXxx` 调用全部消失，`inputSource` 只剩 LWP 分支。

### 第 2 步：剪贴板（`clip_*.txt`，基线 9 处）

| 删除对象 | 位置 | 调用方 |
|---|---|---|
| `clipboardSetText` / `clipboardGetText` 的文件分支 | `packages/lwindow/src/clipboard.cj` | `lgpu_backend.cj:327,331`（`LWindowClipboard`） |
| `pollClipboard()` 整个函数 | `Index.ets` | `watchExit` 里的 tick |
| `lanlu_clip_flush_pending` / 剪贴板 NDK 轮询 | `shell_napi.cpp`、`input_filter.cpp` | — |
| `clip_in.txt` 后台同步（`readPasteboardToFile`） | `Index.ets` | — |

判据：剪贴板只经 `lw_clipboard.set/get/text` 一条路；`pollClipboard` 名字从代码里消失。

### 第 3 步：对话框（`filedlg_*.txt`，基线 4 处）

| 删除对象 | 位置 |
|---|---|
| `readBridgeFile` / `writeBridgeFile` 的 filedlg 分支 | `Index.ets` |
| `bridgeDialogId` 相关状态与 `finishDialog` 的文件分支 | `Index.ets` |
| `takeFileDialogRequest` / `completeFileDialog` | `shell_napi.cpp` |

判据：`finishDialog` 只剩 LWP 分支。

### 第 4 步：窗口命令与抓帧（`window_cmd.txt` / `snapshot_req.txt`，基线 6 处）

| 删除对象 | 位置 |
|---|---|
| `requestWindowCommand` 的文件写入 | `packages/lwindow/src/window_command.cj` |
| `startWindowCmdPoller` 整个函数 | `Index.ets` |
| `pollSnapshot` 与 `snapshot_req.txt` 读取 | `Index.ets` |
| `takeMinimizeRequest` / `g_lanlu_minimize_requested` | `shell_napi.cpp` |
| `writeTo(snapshot_req.txt)` | `client-next/src/main.cj` |

判据：`window_cmd.txt` / `snapshot_req.txt` 从代码与基线中同时消失。

### 第 5 步：应用退出（`g_lanlu_app_exited` / `appExited`）

| 删除对象 | 位置 |
|---|---|
| `appExited` napi + 静态标志 | `shell_napi.cpp` |
| `watchExit` 里 `shell.appExited()` 分支 | `Index.ets` |

判据：引擎退出只经 `lw_app.exit` / `lw_app.quit`；ArkTS 不再轮询静态标志。

### 第 6 步（可能永远保留）：联调开关

`CN_WINDOW` / `CN_UI_BACKEND` / `LANLU_PROBE_*` / `lanlu_env.txt`。
**结论：不属于协议能力，保留。** 它们是开发期开关（换后端、注环境变量、开探针），
走协议只会让调试链路更长、更依赖壳。§11 表里标记为「不替代」。
唯一要做的：确保它们在 `LANLU_LWP=1` 下不干扰协议路径（已满足：都是读环境变量）。

## 为什么现在不删

1. 回落分支在 `LANLU_LWP=0` 时是**唯一可用路径**；而 `LANLU_LWP=1` 从未在真机验证过。
2. 「协议未验证 + 无回落」= 项目进入不可运行状态，且无法在无设备环境下发现。
3. 删掉后 `cjpm build` 仍会通过（编译期只能证明没有悬空引用），**正确性只有真机能证明**。

所以本阶段的产物是：运行时停用（`lwpActive()` 判据）+ 基线计数 + 本手册。
真机验收一过，按上面 6 步执行即可。
