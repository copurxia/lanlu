# 接口 `lw_display`（id 7，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

显示信息：尺寸、缩放、刷新率、安全区。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `info` | 壳→引擎 | 1 | 28 | width:u32@4, height:u32@8, scale:f32@12, refresh_mhz:u32@16, inset_top:u32@20, inset_bottom:u32@24 |

- **info**：壳 -> 引擎：显示器参数（含非整数缩放与 inset 安全区）。
