# 空闲渲染（零帧）排查与改造

真机：MOR-M1 2in1，窗口 2090×1394（scale 1.9）。基线见
`docs/client-next-performance-plan.md` 附录 C：**空闲 0 fps**。

## 1. 症状

改造前空闲无交互时仍以 ~60fps 重绘（两种独立口径一致：引擎 `cursor frame` 计数、
`lgpu stats frames`），而附录 C 记录的空闲基线是 0。

判据：对同一静止画面取相邻两帧 surface 抓图（f120 与 f160），**像素差为 0** ——
说明不是动画在烧帧，是"空转渲染"。

## 2. 定位手段（都留在仓库里可复用）

| 工具 | 作用 |
|---|---|
| `cui.desktop.lastRenderDiag` | 每 120 帧输出 `continuous/timed/events/stateGen/viewport/snapshot/profiler` 各位标志 |
| `cui.core.State.debugName` | 状态名（`localState`/`rememberState`/`StateStore.remember` 自动盖章） |
| `lastStateWriteName` / `recentStateWriteIds` / `stateWriteCount` | 谁在写状态、写入频率、最近 4 次写入的实例 id |
| `client-next/app/model_state_ids.cj` | 模型 `State` 实例 id 与字段名的映射（不改 `model.cj`） |
| `packages/lplatform-ohos/shell/native/input_filter.cpp` 的 `input_trace.txt` | 输入是否真的到过壳（native hilog 在真机不可见，只能落盘） |
| `probe_trace.txt` | 引擎侧诊断（`LANLU_PROBE_LGPU=1`） |

## 3. 根因

`client-next/src/ui/titlebar.cj` 的 `SearchKeys`：

```cangjie
case UiEvent.Frame(_) => slashPending.value = false   // 每帧无条件写
```

`State.set` **即使赋相同值也会**推进 `stateWriteGeneration`（脏帧判据），
于是 `stateGen != lastRenderedGen` 每帧成立 → `mustRender` 恒真 → 满帧重绘。

## 4. 修复

| 提交 | 内容 |
|---|---|
| `6d4183db` | 只在真的挂着"斜杠待转发"时才写（根因） |
| `891fc7de` | 壳每次发消息后 `lwp_wake`（空闲真阻塞的必要配套，否则输入叫不醒引擎） |
| `70317cd` | `State` 写入后唤醒空闲等待（16ms 限频），覆盖后台线程写状态 |
| `fd257e2` | 空闲等待加 **1s 兜底上限**，漏唤醒最多晚 1s，不会永久卡死 |
| `3cf44ead` | `tools/check-state-writes.py` 守卫 + 接入 `verify-ohos.sh` |

## 5. 结果

| 场景 | 修前 | 修后 | 基线 |
|---|---|---|---|
| 空闲（15s 无交互） | 58–65 fps | **0 fps** | 0 |
| 一次交互 | — | 按需出帧（约 32 帧） | — |

## 6. 空闲 CPU（帧数之外的第二个指标）

零渲染之后，空闲时整机 CPU 仍有 **3.7%**（`top -H` 显示热点是主线程，即 ArkTS UI 线程）。
试过两种降频，**都没能把 CPU 降下来**，已回滚（避免为 0 收益引入交互延迟）：

| 尝试 | 结果 |
|---|---|
| `displaySync` 期望帧率 60Hz → 空闲 10Hz（连续 60 帧无 frame.request 降频，有请求立刻升回） | 日志确认生效，CPU 仍 3.7% |
| 泵定时器 16ms → 空闲 33ms（连续 60 拍无引擎请求降频） | 日志确认生效，CPU 仍 3.7% |

结论：这 3.7% 不是我们的定时器循环花掉的，更可能是 ArkUI 对 XComponent surface 的
每帧合成开销（OS 侧，应用无法直接关掉）。后续若要继续压，方向是"离屏/遮挡时停止 surface 更新"
或与系统侧确认驻留合成行为，而不是继续调我们的轮询频率。

## 7. 仍需人工确认

- 点击/按键能否唤醒空闲循环：设备上 Lanlu 窗口拿不到输入焦点（另一应用抢前台），
  注入点击到不了窗口过滤器（`input_trace.txt` 为空），因此没能远程验证。
  判定方法：点主题图标 → 若主题切换且 `input_trace.txt` 有新行即链路正常。
- 中途做过一次 `bm uninstall`（排除旧包干扰），清掉了应用本地数据（服务器配置需重配）。
