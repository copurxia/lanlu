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
| 3 | `key` | 壳→引擎 | 1 | 15 | keycode:u32@4, down:bool@8, utf8:string@9, modifiers:u16@13 |
| 4 | `text_input` | 壳→引擎 | 1 | 8 | text:string@4 |

- **pointer_motion**：指针移动。x/y 为 surface 逻辑坐标（物理像素 / 缩放比）。
- **pointer_button**：按键按下/释放。button 取值对齐 winit：0=左 1=右 2=中。
- **pointer_axis**：滚轮/触摸板滚动。dx/dy 为逻辑行数；wayland 轴向取反后传入（计划 §6.3）。
- **key**：键盘原始事件。keycode 为壳侧单表键码（计划 §6.1：evdev 布局，OHOS keyCode 由壳映射）；
down 区分按下/释放。

since=2 追加两个字段（只追加，不改老字段布局）：
  utf8      —— 该键在当前键盘布局/修饰键下产生的文本（可为空）。输入法不消费的可打印键
               （数字、符号、以及没有输入法时的字母）靠它进入输入框，不再由引擎猜字符。
  modifiers —— 修饰键位掩码，见 LWP_KEY_MOD_*（位定义与主流 GUI 框架的 KMOD 常量同值，
  引擎 KeyModifiers 可直接复用，零转换）。

去重约定：壳不得把输入法已消费的按键再发到这里；引擎在输入框聚焦且 utf8 非空、
且没有 Ctrl/Alt/Meta 时插入该文本（见 docs/lwindow-ime-plan.md §3）。
- **text_input**：IME 提交的文本（对应 wayland text-input-v3 commit）。
