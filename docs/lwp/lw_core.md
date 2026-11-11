# 接口 `lw_core`（id 1，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

握手、错误与日志。所有连接的第一条消息必须是 hello_ack / hello 之一。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `hello_ack` | 引擎→壳 | 1 | 16 | protocol_major:u16@4, protocol_minor:u16@6, engine_version:u32@8, engine_name:string@12 |
| 1 | `ping` | 引擎→壳 | 1 | 8 | seq:u32@4 |

- **hello_ack**：引擎 -> 壳：确认握手。收到它之前壳不得发送其他消息；它是链路可用的唯一判据（见 docs/l-layer.md M0-4）。
- **ping**：引擎 -> 壳：存活探测，壳回 pong（同一 seq）。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `hello` | 壳→引擎 | 1 | 28 | protocol_major:u16@4, protocol_minor:u16@6, shell_name:string@8, os_name:string@12, os_api_level:u32@16, capabilities:u64@20 |
| 1 | `error` | 壳→引擎 | 1 | 12 | code:i32@4, message:string@8 |
| 2 | `log` | 壳→引擎 | 1 | 13 | level:u8@4, module:string@5, text:string@9 |
| 3 | `pong` | 壳→引擎 | 1 | 8 | seq:u32@4 |

- **hello**：壳 -> 引擎：协议版本、壳身份、OS API 级别、能力位。
- **error**：壳 -> 引擎：协议层错误（解码失败、未知 opcode、版本不兼容等）。
- **log**：壳 -> 引擎：统一日志（取代 hilog 丢失与散落的探针文件）。
- **pong**：壳 -> 引擎：ping 的回复。
