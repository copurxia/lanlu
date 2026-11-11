# 接口 `lw_seat`（id 8，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

输入设备能力与光标。能力位见 capabilities 位域。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `set_cursor` | 引擎→壳 | 1 | 8 | shape:u32@4 |
| 1 | `lock_cursor` | 引擎→壳 | 1 | 5 | locked:bool@4 |

- **set_cursor**：引擎 -> 壳：设置光标形状（对应 wl_pointer.set_cursor 的形状子集）。
- **lock_cursor**：引擎 -> 壳：锁定光标到窗口内（游戏/拖拽用）。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `capabilities` | 壳→引擎 | 1 | 12 | bits:u64@4 |

- **capabilities**：壳 -> 引擎：设备能力（键盘/指针/触摸/软键盘），位定义见 core_capabilities。
