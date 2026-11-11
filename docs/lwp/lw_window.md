# 接口 `lw_window`（id 4，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

顶层窗口：状态、尺寸、装饰、最小/最大尺寸。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `create` | 引擎→壳 | 1 | 20 | title:string@4, width:u32@8, height:u32@12, flags:u32@16 |
| 1 | `ack_configure` | 引擎→壳 | 1 | 8 | serial:u32@4 |
| 2 | `set_title` | 引擎→壳 | 1 | 8 | title:string@4 |
| 3 | `set_min_max` | 引擎→壳 | 1 | 20 | min_w:u32@4, min_h:u32@8, max_w:u32@12, max_h:u32@16 |
| 4 | `set_state` | 引擎→壳 | 1 | 8 | state:u32@4 |
| 5 | `close` | 引擎→壳 | 1 | 4 |  |
| 6 | `begin_move` | 引擎→壳 | 1 | 4 |  |
| 7 | `begin_resize` | 引擎→壳 | 1 | 8 | edges:u32@4 |
| 8 | `set_title_buttons` | 引擎→壳 | 1 | 28 | visible:u32@4, side:u32@8, close_margin:u32@12, spacing:u32@16, button_size:u32@20, color_mode:u32@24 |

- **create**：引擎 -> 壳：创建窗口。返回 id 通过事件 window.created 回来。
- **ack_configure**：引擎 -> 壳：接受 configure。
- **set_title**：引擎 -> 壳：改标题。
- **set_min_max**：引擎 -> 壳：最小/最大尺寸（0 表示不限）。
- **set_state**：引擎 -> 壳：请求窗口状态变化（最小化/最大化/还原/全屏）。state 位与 configure 一致。
- **close**：引擎 -> 壳：请求关闭窗口（与 quit 不同：只关窗口，应用可继续）。
- **begin_move**：引擎 -> 壳：开始交互式移动窗口（标题栏按下时）。壳用最近一次输入 serial 发起。
- **begin_resize**：引擎 -> 壳：开始交互式缩放。edges 位：1=上 2=下 4=左 8=右（与 xdg-shell 一致）。
- **set_title_buttons**：引擎 -> 壳：配置平台侧三键（可见性/位置/尺寸/明暗）。壳按平台能力 best-effort 应用并 clamp；实际生效矩形以 title_buttons_rect 事件为准，不另设配置回执。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `created` | 壳→引擎 | 1 | 13 | window_id:u32@4, scale:f32@8, server_side_decorations:bool@12 |
| 1 | `configure` | 壳→引擎 | 1 | 16 | width:u32@4, height:u32@8, state:u32@12 |
| 2 | `close_request` | 壳→引擎 | 1 | 4 |  |
| 3 | `focus` | 壳→引擎 | 1 | 5 | focused:bool@4 |
| 4 | `drag_enter` | 壳→引擎 | 1 | 16 | x:u32@4, y:u32@8, uris:string@12 |
| 5 | `drag_motion` | 壳→引擎 | 1 | 12 | x:u32@4, y:u32@8 |
| 6 | `drag_leave` | 壳→引擎 | 1 | 4 |  |
| 7 | `drop` | 壳→引擎 | 1 | 16 | x:u32@4, y:u32@8, uris:string@12 |
| 8 | `title_buttons_rect` | 壳→引擎 | 1 | 21 | right:i32@4, top:i32@8, width:u32@12, height:u32@16, visible:bool@20 |

- **created**：壳 -> 引擎：窗口已创建，带壳分配的 id 与初始缩放。
- **configure**：壳 -> 引擎：建议尺寸/状态变化。引擎必须回 ack（或 apply），否则壳按超时回退。
- **close_request**：壳 -> 引擎：用户点了关闭（对应 xdg_toplevel.close）。引擎可拒绝并继续运行。
- **focus**：壳 -> 引擎：焦点变化。
- **drag_enter**：壳 -> 引擎：拖放进入窗口。uris 以 \n 分隔（可能为空，等 drop 时才有）。
- **drag_motion**：壳 -> 引擎：拖放在窗口内移动。
- **drag_leave**：壳 -> 引擎：拖放离开窗口（未落下）。
- **drop**：壳 -> 引擎：拖放落下。uris 以 \n 分隔（file:// URI 已解码为本地路径）。
- **title_buttons_rect**：壳 -> 引擎：平台三键当前矩形（窗口局部**物理 px**，壳已从 vp 换算）+ 可见性。语义对齐 OHOS TitleButtonRect（right/top 是右/上边界）；right==0 表示平台未给出可靠左边界，引擎只按 width/height 做右侧/顶部避让。全屏或三键隐藏时 width=height=0、visible=false。
