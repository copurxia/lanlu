# 接口 `lw_text_input`（id 9，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

IME：preedit 与 surrounding text（text-input-v3 的子集）。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `enable` | 引擎→壳 | 1 | 4 |  |
| 1 | `disable` | 引擎→壳 | 1 | 4 |  |
| 2 | `set_surrounding` | 引擎→壳 | 1 | 16 | text:string@4, cursor:u32@8, anchor:u32@12 |
| 3 | `set_cursor_rect` | 引擎→壳 | 1 | 20 | x:i32@4, y:i32@8, w:i32@12, h:i32@16 |

- **enable**：引擎 -> 壳：开启输入法（获得焦点时）。
- **disable**：引擎 -> 壳：关闭输入法。
- **set_surrounding**：引擎 -> 壳：告知光标周围文本，便于输入法做联想（text-input-v3 set_surrounding_text）。
- **set_cursor_rect**：引擎 -> 壳：光标矩形（窗口坐标），输入法据此定位候选框。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `preedit` | 壳→引擎 | 1 | 12 | text:string@4, cursor:u32@8 |

- **preedit**：壳 -> 引擎：候选/preedit 文本与光标位置（用于在窗口内自绘候选条）。
