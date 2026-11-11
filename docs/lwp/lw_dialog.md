# 接口 `lw_dialog`（id 11，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

文件对话框（对应 portal：避免引擎直接碰沙箱路径）。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `open_file` | 引擎→壳 | 1 | 12 | serial:u32@4, filters:string@8 |
| 1 | `save_file` | 引擎→壳 | 1 | 12 | serial:u32@4, suggested:string@8 |

- **open_file**：引擎 -> 壳：打开文件选择器。结果走 event result。
- **save_file**：引擎 -> 壳：保存对话框。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `result` | 壳→引擎 | 1 | 12 | serial:u32@4, path:string@8 |

- **result**：壳 -> 引擎：选择结果；path 为空表示取消。
