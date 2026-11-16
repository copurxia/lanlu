# 输入法（IME）方案：按键与文本分离，规划到 lwindow

状态（2026-11-15）：
- M0 应急（ArkTS 兜底）——已被 M1/M2 取代，代码已删。
- **M1 协议 v2 + 按键自带文本 + 引擎去重 + evdev 单表**：完成，OHOS 交叉编译通过。
- **M2 OHOS 原生输入法（C API）+ 按焦点挂载**：完成，编译/链接通过。
- **M3 组合态显示 + surrounding + delete_surrounding**：完成（`textSurroundingSink` 每帧上报，
  引擎侧按"文本/光标没变就不发"去抖）。
- **M4 Wayland**：完成（xkb 算键文本 + text-input-v3 会话），`cargo build --offline` 通过。
- **真机验证与装机：已完成**（2026-11-16，MOR-M1 2in1，build 含全部 M1~M4）。
  真机自动化验证（uitest keyEvent 注入）：
  - ✅ 数字键入输入框（原"数字打不出来"已修复）
  - ✅ Tab 焦点导航 / Enter 激活按钮打开对话框
  - ✅ 拼音 n i h a o → 输入法候选栏 → 空格上屏 "你好" 进输入框，**无重复**
  - ✅ 退格正确删除（含 CJK）；方向键不崩
  - ✅ 全程无崩溃、无 draw_error、LWP 无违规（unackedConfigure=0 frameTimeout=0）
  遗留（与 mihong/Chromium 同款已知限制，非阻塞）：
  - 组合中的拼音只显示在输入法候选栏，不内联画进输入框（小艺对非 ArkUI 编辑器不下发 preview）
  - 候选栏浮动位置未跟随光标（NotifyCursorUpdate 的坐标口径待核）
  - uitest 注入的数字有一次 off-by-one 现象，需物理键盘人工复核

### 候选框跟手 + 焦点描边（2026-11-16 晚追加修复）
1. **TextEditorProxy 必需回调缺失** -> Attach 被 ImsaKit 判 invalid parameter（handleSetSelectionFunc
   is nullptr）。补齐 HandleSetSelection/Get(Left|Right)TextOfCursor/GetTextIndexAtCursor/
   ReceivePrivateCommand（空实现+登记），IME 才真正挂上。
2. **光标矩形单位错**：引擎给逻辑 vp，CursorInfo 要屏幕绝对物理像素 -> 乘 UI 密度再叠窗口原点。
3. **窗口原点过期**：windowRect 是启动快照，窗口拖动后所有点击/候选框整体偏移。改为每秒+
   onAreaChange+windowRectChange 用 getRectangleById 的组件屏幕坐标自愈（**px，不可再乘密度**）。
4. **指针焦点无描边**：cui 只在 viaKeyboard 时画焦点环（focus-visible 语义），输入框被鼠标点中
   也该有描边 -> TextField/TextArea 的 pressAt 改为 ctx.focus(id, viaKeyboard: true)。
5. 诊断设施：native IME 桥日志落盘 $HOME/ime_trace.txt（本构建 LOG_APP 不可见）；
   LANLU_PROBE_MODAL=1 打印弹窗布局矩形；像素级验证渲染与布局一致（保存按钮误差<20px）。
6. ArkUI 组件鼠标事件在该 XComponent 上收不到（代码原有注释已验证两次），指针仍走窗口过滤器；
   组件内坐标通路（sendPointerLocal + 50ms 去重）已就绪，组件事件可用时可无缝切换。

## 0. 问题

输入框里打不出数字。三条通道之间的缝隙：

1. 壳在**启动时**就 attach 输入法，且一直挂着 → `setImeActive(true)` 让窗口键盘过滤器
   整段停发键码；
2. 键盘过滤器本来就只认 12 个功能键（Esc/退格/方向…），字母数字从来不经过它；
3. 文本只剩 `insertText` 一条路。PC 上的华为输入法不处理数字/符号，把它们放行给
   "获得焦点的组件"——而 XComponent 没挂 `onKeyEvent`，这些键直接消失。

附带问题：`lwp_client.cpp` 的字母键码表把 a–z 映射成 `16+偏移`（evdev 不是连续布局），
引擎 `keyFromCode` 同样的错，且字母用小写 ASCII 而 lgui 约定 65。

## 1. 设计原则（对照 horizon-ohos 与 mihong/Chromium）

**按键与文本分离**：

- 按键事件**始终**送到引擎，用于快捷键、导航；没有输入法时也能打字。
- 输入法只负责"组合中文本"与"上屏文本"。
- 去重不靠"输入法在就停发按键"这种全局开关，靠单条按键的语义：壳只转发输入法
  **没有消费**的键，且键事件自带该键产生的文本。

| | lanlu（本方案） | horizon（winit-ohos） | mihong（Chromium ozone/ohos） |
|---|---|---|---|
| IME 接入 | 原生 C API（TextEditorProxy） | ArkTS 控制器 | 原生 C API |
| 挂载时机 | 输入框获焦时 enable / 失焦 disable | 游戏请求时 | 输入框获焦时 |
| 物理键来源 | 组件 onKeyEvent（输入法之后） | 窗口过滤器 | 应用事件流 |
| 文本来源 | 键自带 utf8 + commit_string | 键推导 + insertText | InsertChar + InsertText |
| 组合串 | preedit 事件 + 输入框自绘下划线 | 无 | 有回调入口（未实现） |

## 2. 协议 v2（LWP，`packages/lwp/protocol/`）

只追加、不删改（`lwp-gen.py --check-abi` 通过）。

```
lw_input.key        += utf8:string, modifiers:u16      # since=2
lw_text_input.enable += input_type:u32, enter_key:u32  # since=2
lw_text_input.event  += commit_string(text)            # since=2
                     += delete_surrounding(before, after)  # 单位：字符（码点）
```

新增 `[bitfield.key_modifiers]`（与 SDL_KMOD_* 同值）与 `[enum.ime_text_input_type]`、
`[enum.ime_enter_key]`。

## 3. 去重规则（引擎侧，`client-next/src/ui/lgpu_backend.cj`）

1. 键事件带 utf8 且按下、且没有 Ctrl/Alt/Meta → 先投递 `UiEvent.TextInput(utf8)`，
   再投递 `UiEvent.KeyDown(键)`（控件快捷键照常收到键）。
2. 壳不得把输入法已消费的键发过来（OHOS 用 `OH_TextConfig_SetConsumeKeyEvents(true)`）。
3. `commit_string` → `UiEvent.TextInput`（清掉组合态后插入）。
4. `preedit` → `UiEvent.TextEditing(text, caret)`：只影响显示，不进撤销栈、不改值。
5. `delete_surrounding` → `UiEvent.DeleteSurrounding(before, after)`。

## 4. 分层落点

| 层 | 文件 | 职责 |
|---|---|---|
| 协议 | `packages/lwp/protocol/{input,system}.toml` | 消息定义（生成器产出头/绑定/文档） |
| 引擎平台层 | `packages/lwindow/src/{events,backend_lwp,window_client,input_source}.cj` | 解码为 LWindowEvent；enable/disable 请求带输入类型 |
| UI 框架 | `lgui/src/events.cj`（UiEvent.TextEditing/DeleteSurrounding）、`cui/text/{text_field,text_area,text_edit_state,ime_preedit}.cj` | 组合态显示（下划线）、提交、按字符删除 |
| 桌面壳（OHOS） | `lplatform-ohos/shell/native/text_input.cpp`（新） | 原生 IME 挂载、TextEditorProxy 回调 → LWP 事件 |
| 壳公共 | `lwp_client.cpp`（新增 4 个发送函数）、`lwp_window.cpp`（泵分发 enable/disable/cursor_rect）、`shell_napi.cpp`（sendKeyEvent：OHOS keyCode→evdev + unicode + 修饰键） | |
| ArkTS | `Index.ets` | 删掉 ArkTS 输入法控制器；onKeyEvent 发 sendKeyEvent；焦点变化通知壳 |

## 5. 验证清单（真机）

1. 未挂输入法的菜单/设置页：字母、数字、符号都能打进搜索框。
2. 搜索框聚焦 → 输入法挂载；输入拼音 → 组合串带下划线显示在输入框里；
   选词 → 上屏且组合串消失，**不重复**。
3. PC 上直接按数字键 → 数字进输入框（原来打不出来的那一类）。
4. 退格/Delete/方向键/Enter 正常；Ctrl+A/C/V/Z 仍走快捷键。
5. 失焦 → 输入法卸载（hilog `[LANLU-IME] detached`）。
6. 手机（非 2in1）聚焦输入框 → 弹软键盘；2in1/平板不弹。

## 6. 实现细节补充（M3/M4）

- **surrounding 去抖**：cui 在 `UiEvent.Frame` 且已聚焦时上报（`reportSurrounding`，
  >512 字节只带光标前后各 256 字节）；`lwindow.lwpImeSetSurrounding` 缓存上一次成功发送的
  (text, cursor, anchor)，没变就不发。
- **Wayland 键文本**：`wl_keyboard.keymap` → `xkb_keymap_new_from_string`；`Modifiers` 事件同步进
  `xkb_state_update_mask`；按键时用 `xkb_state_key_get_utf8(keycode+8)` 算 utf8。
  libxkbcommon 缺失时回落内置 US 布局表（`us_layout_text`），不会因缺库而丢字符。
- **Wayland text-input-v3**：`get_text_input(seat)` 绑定会话，`enter` 事件之后才 `enable+commit`
  （v3 语义）；`commit_string`/`preedit_string`/`delete_surrounding_text` 直接转 LWP 事件；
  `set_cursor_rect`/`set_surrounding` 走 `set_cursor_rectangle`/`set_surrounding_text` + commit。
- **顺带修的协议 bug**：Wayland 壳的 `iface::CLIPBOARD` 常量一直是 9，而生成头里 clipboard=10、
  text_input=9 —— 剪贴板消息此前发到了错误的接口号上。已改正。

## 7. 本轮补充（round 2）

- **组合态期间键不再落字**：引擎在收到 preedit 后置 `g_preeditActive`，期间按键的 utf8 不再合成
  `TextInput`，文本一律由 `commit_string` 提供 —— 否则拼音期间按的字母会直接插进输入框。
- **失焦清组合态**：cui 在 `UiEvent.Frame` 且未聚焦时清空 preedit（输入法失焦时可能不发
  finish_preview）。
- **软键盘控制**：OHOS enable 时 `OH_InputMethodProxy_ShowKeyboard`，disable 时先
  `HideKeyboard` 再 `Detach`（手机上键盘才不会残留）。
- **组合串光标精确换算**：`SetPreviewText` 的 start/end 是**码点**索引，按字节偏移精确换算后上报
  （代理对/中文不再偏一位）。

## 8. 未完成

- **M4 Wayland**：`wl_keyboard` 按键用 xkb 算 utf8；接 `zwp_text_input_v3`
  （commit_string / preedit / delete_surrounding 与协议一一对应）。
- 组合串内光标按码点精确换算（当前 OHOS 侧按组合串末尾上报）。
- `set_surrounding`（联想）尚未从 cui 侧主动发送。
