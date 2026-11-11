# 接口 `lw_system`（id 12，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

系统信息：时区、语言、字体目录等（取代散落的环境变量探测）。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `log` | 引擎→壳 | 1 | 9 | level:u8@4, text:string@5 |

- **log**：引擎 -> 壳：把日志交给壳输出（hilog），不再各写各的文件。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `info` | 壳→引擎 | 1 | 24 | timezone:string@4, language:string@8, font_dir:string@12, home_dir:string@16, api_level:u32@20 |

- **info**：壳 -> 引擎：启动时同步一次的系统信息。
