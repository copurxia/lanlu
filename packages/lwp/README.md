# lwp —— LWP 协议本体（壳 ↔ 引擎）

计划：[docs/lwindow-platform-separation-plan.md](../../docs/lwindow-platform-separation-plan.md) §5。
**零平台代码**：本包只有 IDL、生成物、手写辅助与测试；不含任何 OS API。

## 结构

```
protocol/*.toml        IDL（唯一真源；改协议只改这里）
src/lwp_gen_protocol.cj 生成物：常量 + 结构 + 逐字段解码（勿手改）
src/lwp.cj             re-export 说明（生成物已声明 package lwp）
src/lwp_test.cj        仓颉侧解码测试（手写字节 → 解码 → 断言字段）
include/lwp_protocol.h 生成物：C 结构体/opcode/枚举（packed，小端）
include/lwp_dispatch.inc 生成物：壳端分发桩（switch iface/opcode）
abi/lwp_abi.json       生成物：ABI 指纹（只允许追加）
native/test_protocol.c C 侧布局静态断言 + 运行时校验
```

`docs/lwp/*.md` 由生成器一并产出，作为协议参考文档。

## 线上格式（v1）

- 每条消息体：`uint32 size` 首字段（含自身，不含 `lwp_header`），接收方按 size 跳过未知消息。
- 字段按声明顺序紧密排列（packed，小端）。
- `string = { uint16 off; uint16 len; }`，`off` 相对消息体起点，UTF-8；越界视为空串（坏消息不致命）。
- opcode = 同接口、同方向（request / event）内的声明序号，从 0 开始。
- 字段只允许追加；删除或改类型 = `protocol_major + 1`。

## 仓颉侧绑定

`src/lwp_channel.cj`：`LwpChannel`（open/send/recv/wait/wake/close/enableChecker/traceOpen）、`LwpMessage`。
FFI 边界只传**标量与字节缓冲**（`lwp_send_parts` / `lwp_recv_parts`），不把 `lwp_header` 结构体带过边界。

注意两点工程细节（都踩过）：
- C 库名是 **`liblwp_native.so`**：本包自身产物是 `liblwp.a`，若 C 库也叫 `liblwp` 会被 `-llwp` 抢先解析；
- cjpm 直接调用 `ld`，所以 `link-option` 里 rpath 要写 `-rpath <dir>`（`-Wl,-rpath,...` 会报错）。

依赖 `liblwp_native.so` 的构建需要环境变量 `LWP_LIB_DIR`（默认见 `packages/lwp/test.sh`）。

## 命令

```bash
python3 tools/lwp-gen.py            # 改完 IDL 后重新生成
python3 tools/lwp-gen.py --check      # CI：生成物是否最新
python3 tools/lwp-gen.py --check-abi  # CI：相对 abi/lwp_abi.baseline.json 只允许追加
bash packages/lwp/test.sh           # 全部测试（生成物 + C 侧 + 仓颉侧 + lwtrace 工具）
bash packages/lwp/native/run-tests.sh   # 只跑 C 侧
bash packages/lwp/native/build.sh   # 构建 liblwp_native.so → lib/
```

## 通道（liblwp.so）

```
include/lwp.h        公开 C ABI（LWP_API 显式 default 可见性）
native/liblwp.c      实现：定长槽环形队列（Vyukov 有界 MPMC）+ blob 池 + eventfd
native/liblwp.map    导出白名单（只导出 11 个公开函数）
native/build.sh      构建 liblwp.so → packages/lwp/lib/（不入库）
native/test_*.c      C 侧测试
```

协议检查器与录制（计划 §16.3、§16.7）：

- `lwp_checker_enable(ch, strict)`：校验「非 core 消息必须在握手之后」与「core 未知 opcode」；
  `strict=1` 违规直接返回 `LWP_EPROTO`，否则只计数（`stats.unknown_opcode/not_handshaked`）。
- `lwp_trace_open/close`：把两个方向的每条消息写入 `.lwtrace`（文件头 `LWPT` +  packed 记录），
  每条 flush，崩溃后仍可取回最近记录。
- `lwp_trace_replay(ch, path, dir)`：把录制里「发送」的记录按原样重新入队——壳侧事件源可以被
  离线重放，不需要真壳（计划 §16.3）。
- `tools/lwtrace.py stats|dump|diff`：统计消息分布/在途深度、按时间顺序打印、**语义比较**
  （忽略时间戳与 serial，只比“谁在什么方向发了什么”；消息名从 `abi/lwp_abi.json` 反查）。

行为约定：

- `lwp_send` 非阻塞；队列满返回 `LWP_EAGAIN`，带 `LWP_F_DROPPABLE` 的消息计入 `dropped`。
  单条消息内联上限 `LWP_INLINE_MAX`(320B)，更大的走 `lwp_blob_put`。
- `lwp_recv` 校验 `hdr.size`：小于头部或超过“头部+内联上限”判为 `LWP_EBADMSG` 并计入 `bad`（坏消息不致命）。
- `lwp_wait` 真阻塞（poll eventfd），**不会被陈旧的 eventfd 计数虚假唤醒**；`lwp_wake` 用于打断正在等待的对端。
- `lwp_open` 是进程内单例（同名复用）；无构造函数，首次调用惰性初始化。
- 加载顺序（`docs/l-layer.md` M0-4 结论）：壳以 `RTLD_GLOBAL` 加载本库且**早于引擎**，
  否则引擎解析不到符号；且失败是静默的，所以链路是否可用只认 `core.hello_ack`。

## 协议面（v1）

| id | 接口 | 条数 | 说明 |
|---|---|---|---|
| 1 | `lw_core` | 6 | 握手、错误、日志、ping/pong |
| 2 | `lw_input` | 5 | 指针/滚轮/键盘/IME 文本 |
| 3 | `lw_app` | 4 | 生命周期（started/resumed/paused/quit） |
| 4 | `lw_window` | 8 | 创建/configure/ack/标题/最小最大/关闭/焦点 |
| 5 | `lw_surface` | 6 | attach + frame_done + available/changed/will_destroy/hidden |
| 6 | `lw_frame` | 2 | 帧请求与 vsync 回调 |
| 7 | `lw_display` | 1 | 显示参数（含缩放与安全区） |
| 8 | `lw_seat` | 3 | 能力位、光标形状、光标锁定 |
| 9 | `lw_text_input` | 5 | enable/disable/preedit/surrounding/cursor_rect |
| 10 | `lw_clipboard` | 3 | 异步读、文本事件、写 |
| 11 | `lw_dialog` | 3 | 打开/保存/结果 |
| 12 | `lw_system` | 2 | 系统信息、日志出口 |
| 13 | `lw_test` | 4 | 测试就绪/注入/抓帧（双向，见下表） |

共 56 条消息。

### opcode 按方向独立编号（重要）

同一个接口里，**请求方向和事件方向各自从 0 开始编号**。所以「同名不同向」的两条消息会有
相同的数字，但语义相反 —— 这种情况必须分别声明，不能复用常量：

| `lw_test` 消息 | 方向 | opcode | 含义 |
|---|---|---|---|
| `ready` | request（引擎→壳） | 0 | 引擎已就绪，可注入测试动作 |
| `request_capture` | request（引擎→壳） | 1 | 请**壳**抓一帧（ArkTS componentSnapshot） |
| `inject` | event（壳→引擎） | 0 | 壳注入一条测试动作 |
| `capture` | event（壳→引擎） | 1 | 壳要求**引擎**抓一帧（引擎自己写文件） |

> 第 34 轮踩过：把 `request_capture` 误用成 event 方向的 `capture` 常量（都是 1），
> 结果「请壳抓帧」发成了「引擎就绪」，壳收到后什么都不做 —— 表现为抓帧请求石沉大海。
> 生成器为每个方向分别产出 `LWP_<IFACE>_<MSG>_OPCODE`，**用常量时务必确认方向**。
`lwp_abi.json` 里的 id/opcode/size 由测试断言，改 ABI 会被 CI 拦住。

## 状态

- 2026-11-10：core 接口 v1（hello / hello_ack / error / log / ping / pong）+ 生成器 + 两侧测试。
- 2026-11-10：`liblwp.so` 通道实现 + C 测试（收发/满队列/4 线程多生产者/blob/wait-wake/非法头部）；
  导出符号白名单进 CI。
- 2026-11-10：协议检查器（握手 + 未知 opcode）+ `.lwtrace` 录制 + `tools/lwtrace.py stats/dump`。
- 2026-11-10：`abi/lwp_abi.baseline.json` + `--check-abi`（只允许追加：删字段/改类型必须
  `protocol_major + 1`），已进 CI。
- 2026-11-10：仓颉侧绑定 `LwpChannel`（标量 FFI 边界）+ 4 个仓颉测试（收发往返/检查器拦截/空收/超时）。
- 2026-11-10：协议面补全到 13 个接口 / 47 条消息；壳侧 hello + 引擎 hello_ack 握手；
  `lwp_stats_summary` 一行统计（引擎每 300 次轮询打一条）。
