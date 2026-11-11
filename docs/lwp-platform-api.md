# 平台包公开 API 清单（自动生成 + 人工分类）

用途：作为"平台包可独立使用"的收尾检查 —— 看清哪些 API 真被引擎用、哪些只是测试/诊断、哪些已无人使用。

生成方式：扫描 `packages/lwindow/src/*.cj` 的 `public func/class/struct/enum`，
再统计 `client-next/src` 与各平台包里的引用次数（排除定义文件自身）。


## 汇总

- **引擎实际使用**：40 个
- **仅测试/诊断使用**：55 个
- **当前无引用**：8 个

## 1. 引擎实际使用

- `LWindowEvent`（struct）— `events.cj`
- `LWindowEventType`（enum）— `events.cj`
- `LWindowLifecycleEvent`（enum）— `window_client.cj`
- `captureTo`（func）— `window_client.cj`
- `clipboardGetText`（func）— `clipboard.cj`
- `clipboardHasText`（func）— `clipboard.cj`
- `clipboardSetText`（func）— `clipboard.cj`
- `create`（func）— `window_client.cj`
- `initLwpInput`（func）— `input_source.cj`
- `initialize`（func）— `lwindow.cj`
- `key`（func）— `backend_headless.cj`
- `log`（func）— `window_client.cj`
- `lwpAwaitSurface`（func）— `input_source.cj`
- `lwpAwaitSystemInfo`（func）— `input_source.cj`
- `lwpBeginResize`（func）— `input_source.cj`
- `lwpCheckConfigureTimeout`（func）— `input_source.cj`
- `lwpCursorShapeForPoint`（func）— `input_source.cj`
- `lwpCursorShapeSent`（func）— `input_source.cj`
- `lwpDrainLifecycle`（func）— `input_source.cj`
- `lwpFrameTick`（func）— `input_source.cj`
- `lwpImeSetCursorRect`（func）— `input_source.cj`
- `lwpInputEnabled`（func）— `input_source.cj`
- `lwpLastPointer`（func）— `input_source.cj`
- `lwpLog`（func）— `input_source.cj`
- `lwpNoteFrameDone`（func）— `input_source.cj`
- `lwpReplayTrace`（func）— `input_source.cj`
- `lwpRequestCapture`（func）— `input_source.cj`
- `lwpSendTestReady`（func）— `input_source.cj`
- `lwpSetCursorShape`（func）— `input_source.cj`
- `lwpStatsLine`（func）— `input_source.cj`
- `lwpSystemInfo`（func）— `input_source.cj`
- `lwpViolations`（func）— `input_source.cj`
- `nextLwpEvent`（func）— `input_source.cj`
- `preferredWindowGeometry`（func）— `window_policy.cj`
- `prepareDesktopIntegration`（func）— `window_policy.cj`
- `prepareRendererHints`（func）— `window_policy.cj`
- `requestFrame`（func）— `window_client.cj`
- `requestWindowCommand`（func）— `window_command.cj`
- `systemSansFontPath`（func）— `window_policy.cj`
- `toString`（func）— `events.cj`

## 2. 仅测试 / 诊断使用

这些在引擎里没有调用，但测试夹具（`backend_headless.cj`）或诊断用得上，保留。

- `HeadlessShell`（class）— `backend_headless.cj`，外部引用 43 次
- `LWindowPlatform`（enum）— `lwindow.cj`，外部引用 2 次
- `LwpWindowClient`（class）— `window_client.cj`，外部引用 30 次
- `ackConfigure`（func）— `window_client.cj`，外部引用 1 次
- `attach`（func）— `window_client.cj`，外部引用 31 次
- `awaitConfigure`（func）— `window_client.cj`，外部引用 3 次
- `beginMove`（func）— `window_client.cj`，外部引用 1 次
- `beginResize`（func）— `window_client.cj`，外部引用 1 次
- `canPresent`（func）— `window_client.cj`，外部引用 4 次
- `channel`（func）— `backend_headless.cj`，外部引用 136 次
- `checkConfigureTimeout`（func）— `window_client.cj`，外部引用 5 次
- `checkFrameTimeout`（func）— `window_client.cj`，外部引用 6 次
- `clipboardGet`（func）— `window_client.cj`，外部引用 2 次
- `clipboardSet`（func）— `window_client.cj`，外部引用 2 次
- `decodeLwpEvent`（func）— `backend_lwp.cj`，外部引用 2 次
- `dialogOpenFile`（func）— `window_client.cj`，外部引用 1 次
- `dialogSaveFile`（func）— `window_client.cj`，外部引用 1 次
- `handshake`（func）— `backend_headless.cj`，外部引用 35 次
- `hasCapability`（func）— `window_client.cj`，外部引用 3 次
- `hasPendingConfigure`（func）— `window_client.cj`，外部引用 6 次
- `hasPendingFrame`（func）— `window_client.cj`，外部引用 3 次
- `imeEnable`（func）— `window_client.cj`，外部引用 2 次
- `imeSetCursorRect`（func）— `window_client.cj`，外部引用 2 次
- `imeSetSurrounding`（func）— `window_client.cj`，外部引用 1 次
- `lwpAwaitInitialConfigure`（func）— `input_source.cj`，外部引用 1 次
- `lwpClipboardGetText`（func）— `input_source.cj`，外部引用 4 次
- `lwpClipboardSetText`（func）— `input_source.cj`，外部引用 1 次
- `lwpNotePointer`（func）— `input_source.cj`，外部引用 1 次
- `lwpResetForTest`（func）— `input_source.cj`，外部引用 9 次
- `lwpShellProvidesVsync`（func）— `input_source.cj`，外部引用 1 次
- `lwpWindowCommand`（func）— `input_source.cj`，外部引用 1 次
- `noteFrameDone`（func）— `window_client.cj`，外部引用 2 次
- `pointerAxis`（func）— `backend_headless.cj`，外部引用 1 次
- `pointerButton`（func）— `backend_headless.cj`，外部引用 6 次
- `pointerMotion`（func）— `backend_headless.cj`，外部引用 5 次
- `poll`（func）— `window_client.cj`，外部引用 10 次
- `pollAll`（func）— `window_client.cj`，外部引用 23 次
- `pollLwpEvents`（func）— `backend_lwp.cj`，外部引用 9 次
- `pushBackLwpMessage`（func）— `backend_lwp.cj`，外部引用 2 次
- `recvRequest`（func）— `backend_headless.cj`，外部引用 23 次
- `requestCloseWindow`（func）— `window_client.cj`，外部引用 2 次
- `requestExit`（func）— `window_client.cj`，外部引用 2 次
- `requestState`（func）— `window_client.cj`，外部引用 5 次
- `setTitleButtons`（func）— `window_client.cj`（三键平台化，P3 业务层接入后会转为"引擎实际使用"）
- `titleBtnWidth`/`titleBtnHeight`/`titleBtnVisible`（var）— `window_client.cj`（三键矩形快照）
- `sendConfigure`（func）— `backend_headless.cj`，外部引用 4 次
- `sendFrameDone`（func）— `backend_headless.cj`，外部引用 2 次
- `sendSurfaceAvailable`（func）— `backend_headless.cj`，外部引用 5 次
- `sendSurfaceChanged`（func）— `backend_headless.cj`，外部引用 2 次
- `sendSurfaceWillDestroy`（func）— `backend_headless.cj`，外部引用 3 次
- `sendSystemInfo`（func）— `backend_headless.cj`，外部引用 2 次
- `sendTestReady`（func）— `window_client.cj`，外部引用 2 次
- `sendWindowCreated`（func）— `backend_headless.cj`，外部引用 1 次
- `setCursorShape`（func）— `window_client.cj`，外部引用 1 次
- `shellProvidesVsync`（func）— `window_client.cj`，外部引用 3 次
- `takeBacklogLwpMessage`（func）— `backend_lwp.cj`，外部引用 2 次
- `textInput`（func）— `backend_headless.cj`，外部引用 3 次

## 3. 当前无外部引用

> `WindowGeometry`（`window_policy.cj`）与 `lwpNowNs`（`input_source.cj`）在**本文件内部**被使用，
> 属模块内部实现，不算孤儿，已从本表移出。

真正没有外部引用的是下面 6 个：

- `currentWindowId`（func）— `window_client.cj`
- `lwpBacklogSize`（func）— `input_source.cj`
- `lwpBeginMove`（func）— `input_source.cj`
- `lwpInputChannel`（func）— `input_source.cj`
- `sendAppStarted`（func）— `backend_headless.cj`
- `setTitle`（func）— `window_client.cj`

### 处置建议（2026-11-11 审计）

| API | 建议 | 理由 |
|---|---|---|
| `lwpBeginMove` | **保留** | `lw_window.begin_move` 协议已存在、Wayland 壳已实现；OHOS 侧无等价 API，但引擎一旦做自绘标题栏拖动就会用到 |
| `setTitle` / `currentWindowId` | **保留** | 窗口客户端的对称 API（`create` 带标题），删了会让 API 面不一致 |
| `lwpInputChannel` / `lwpBacklogSize` | **保留** | 联调诊断入口（排查"事件被吞"这类问题时直接用得上，第 90 轮就靠它） |
| `sendAppStarted` | **可删** | 测试夹具里的空壳方法，从未被调用；删除无风险，但留着也不碍事 |

**结论**：没有需要立刻删除的死代码；真正值得记录的是
**`lwpBeginMove` 已就绪但引擎未调用** —— 这是"自绘标题栏拖动"功能的入口，
等产品决定要不要支持（OHOS 系统本身支持拖标题栏移窗，所以当前不需要）。

