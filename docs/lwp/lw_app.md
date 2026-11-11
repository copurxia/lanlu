# 接口 `lw_app`（id 3，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

应用级：启动、退出、生命周期。壳 -> 引擎为主。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `quit` | 引擎→壳 | 1 | 8 | code:i32@4 |
| 1 | `exit` | 引擎→壳 | 1 | 8 | code:i32@4 |

- **quit**：引擎 -> 壳：请求退出应用。
- **exit**：引擎 -> 壳：请求退出应用（TerminateSelf）。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `started` | 壳→引擎 | 1 | 8 | app_id:u32@4 |
| 1 | `resumed` | 壳→引擎 | 1 | 4 |  |
| 2 | `paused` | 壳→引擎 | 1 | 4 |  |

- **started**：壳 -> 引擎：应用已就绪，可以创建窗口（对应 OHOS onForeground）。
- **resumed**：壳 -> 引擎：回到前台（OHOS onForeground / wayland focus）。
- **paused**：壳 -> 引擎：进入后台（OHOS onBackground）。引擎应停止渲染但保留状态。
