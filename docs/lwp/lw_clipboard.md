# 接口 `lw_clipboard`（id 10，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

剪贴板：异步读写，带 MIME。取代原来的 clip_*.txt 文件桥。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `get` | 引擎→壳 | 1 | 8 | serial:u32@4 |
| 1 | `set` | 引擎→壳 | 1 | 12 | mime:string@4, text:string@8 |

- **get**：引擎 -> 壳：读剪贴板（异步，结果走 event text）。
- **set**：引擎 -> 壳：写剪贴板。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `text` | 壳→引擎 | 1 | 16 | serial:u32@4, mime:string@8, text:string@12 |

- **text**：壳 -> 引擎：剪贴板文本（对应 get 的 serial）。
