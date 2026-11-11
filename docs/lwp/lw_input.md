# 接口 `lw_input`（id 2，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

输入事件：指针、滚轮、键盘、文本输入。全部由壳 -> 引擎（event 方向）。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `pointer_motion` | 壳→引擎 | 1 | 12 | x:f32@4, y:f32@8 |
| 1 | `pointer_button` | 壳→引擎 | 1 | 14 | x:f32@4, y:f32@8, button:u8@12, down:bool@13 |
| 2 | `pointer_axis` | 壳→引擎 | 1 | 12 | dx:f32@4, dy:f32@8 |
| 3 | `key` | 壳→引擎 | 1 | 9 | keycode:u32@4, down:bool@8 |
| 4 | `text_input` | 壳→引擎 | 1 | 8 | text:string@4 |

- **pointer_motion**：指针移动。x/y 为 surface 逻辑坐标（物理像素 / 缩放比）。
- **pointer_button**：按键按下/释放。button 取值对齐 winit：0=左 1=右 2=中。
- **pointer_axis**：滚轮/触摸板滚动。dx/dy 为逻辑行数；wayland 轴向取反后传入（计划 §6.3）。
- **key**：键盘原始事件。keycode 为壳侧单表键码（计划 §6.1：Linux xkb+OHOS 统一映射）；down 区分按下/释放。
- **text_input**：IME 提交的文本（对应 wayland text-input-v3 commit）。
