# 接口 `lw_surface`（id 5，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

绘制表面：buffer 提交与帧回调。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `attach` | 引擎→壳 | 1 | 24 | buffer:u64@4, width:u32@12, height:u32@16, serial:u32@20 |

- **attach**：引擎 -> 壳：提交一帧。buffer 句柄由 lgpu 分配（VkImage/共享内存），这里只传句柄。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `frame_done` | 壳→引擎 | 1 | 16 | serial:u32@4, time_ns:u64@8 |
| 1 | `available` | 壳→引擎 | 1 | 20 | handle:u64@4, width:u32@12, height:u32@16 |
| 2 | `changed` | 壳→引擎 | 1 | 12 | width:u32@4, height:u32@8 |
| 3 | `will_destroy` | 壳→引擎 | 1 | 4 |  |
| 4 | `hidden` | 壳→引擎 | 1 | 4 |  |

- **frame_done**：壳 -> 引擎：上一帧已显示（对应 wl_callback.done），引擎可提交下一帧。
- **available**：壳 -> 引擎：surface 可用（含 native window 句柄与像素尺寸）。对应 OH_ArkUI_SurfaceCallback_SetSurfaceCreatedEvent。
- **changed**：壳 -> 引擎：尺寸变化（优先 reconfigure 现有 swapchain，不要销毁重建——Maleoon 第三次重建必崩，见 §7.1）。
- **will_destroy**：壳 -> 引擎：surface 即将销毁。引擎必须**同步**停止渲染并释放 surface（回调返回后旧 window 立即失效）。
- **hidden**：壳 -> 引擎：切后台/息屏（只触发 hidden，不触发 destroyed）。引擎停帧但保留 surface。
