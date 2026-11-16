# 接口 `lw_text_input`（id 9，version 1）

> **opcode 在每个方向内独立编号**：同一接口里请求方向与事件方向都从 0 开始，因此「同名不同向」会有相同数字而语义相反。用常量前务必确认方向。

IME：preedit 与 surrounding text（text-input-v3 的子集）。

由 `tools/lwp-gen.py` 生成，勿手改；改协议请改 `packages/lwp/protocol/*.toml`。

## 请求（引擎 → 壳）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `enable` | 引擎→壳 | 1 | 12 | input_type:u32@4, enter_key:u32@8 |
| 1 | `disable` | 引擎→壳 | 1 | 4 |  |
| 2 | `set_surrounding` | 引擎→壳 | 1 | 16 | text:string@4, cursor:u32@8, anchor:u32@12 |
| 3 | `set_cursor_rect` | 引擎→壳 | 1 | 20 | x:i32@4, y:i32@8, w:i32@12, h:i32@16 |

- **enable**：引擎 -> 壳：开启输入法（输入框获得焦点时；失焦发 disable）。

since=2 追加两个字段：input_type / enter_key（见 LWP_IME_TEXT_INPUT_*、LWP_IME_ENTER_KEY_*）。
壳据此选择输入法模式（文本/数字/密码）与回车键形态；不认识的值按 TEXT/DONE 处理。
- **disable**：引擎 -> 壳：关闭输入法。
- **set_surrounding**：引擎 -> 壳：告知光标周围文本，便于输入法做联想（text-input-v3 set_surrounding_text）。
- **set_cursor_rect**：引擎 -> 壳：光标矩形（窗口坐标），输入法据此定位候选框。

## 事件（壳 → 引擎）

| opcode | 消息 | 方向 | since | 大小 | 字段 |
|---|---|---|---|---|---|
| 0 | `preedit` | 壳→引擎 | 1 | 12 | text:string@4, cursor:u32@8 |
| 1 | `commit_string` | 壳→引擎 | 2 | 8 | text:string@4 |
| 2 | `delete_surrounding` | 壳→引擎 | 2 | 12 | before:u32@4, after:u32@8 |

- **preedit**：壳 -> 引擎：组合中的文本（尚未上屏）与组合串内的光标字节偏移。

引擎在输入框里按"上屏文本 + 下划线组合串"渲染；cursor 是组合串内的字节偏移。
空 text 表示组合结束（随后通常会有一个 commit_string）。
- **commit_string**：壳 -> 引擎：上屏文本（text-input-v3 commit_string）。引擎插入到当前光标处并清空组合串。
- **delete_surrounding**：壳 -> 引擎：输入法要求删除光标前后文本（text-input-v3 delete_surrounding_text）。

before/after 单位是**字符**（UTF-8 码点），不是字节；引擎按码点删。
