# 接口 `lw_test`（id 13，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

测试专用接口（计划 §16）：只在 debug 构建注册，release 不导出。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `ready` | 引擎→壳 | 1 | 8 | engine_version:u32@4 |
| 1 | `request_capture` | 引擎→壳 | 1 | 8 | path:string@4 |

- **ready**：引擎 -> 壳：引擎启动完成，可以注入测试动作。
- **request_capture**：引擎 -> 壳：请壳抓一帧（ArkTS componentSnapshot）并写到 path。与 event 方向的 capture 相反。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `inject` | 壳→引擎 | 1 | 16 | kind:u32@4, a:i32@8, b:i32@12 |
| 1 | `replay` | 壳→引擎 | 1 | 8 | path:string@4 |
| 2 | `capture` | 壳→引擎 | 1 | 8 | path:string@4 |

- **inject**：壳 -> 引擎：注入一条输入（通道句柄见 test.capture 的前置配置）。
- **replay**：壳 -> 引擎：把一份 .lwtrace 录制重放进通道（复现真机问题用，计划 §16.3）。path 在设备沙箱内。
- **capture**：壳 -> 引擎：抓一帧并存到 path（真机无 ADB 时用）。
