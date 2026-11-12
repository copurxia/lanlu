# 20 类缺口 · 最终状态总表

> 逐条标注本轮工作的结果（最后更新 2026-11-12 00:45）。分支：`p0-focus-visible`
> （**96 个提交**，测试 **521 例 / 514 通过 / 7 条豁免**；96 个补丁对主仓最新 WIP 零冲突全量演练全绿）。
> 应用层交付：`patches-app/` 3 个补丁（已 `git apply --check` 通过；与分支
> `app-focus-wiring` 一致性已核对）。

图例：✅ 框架内完成并测试；🟡 框架完成、应用接线已备（补丁）；🔵 框架完成、应用接线待做；🔶 部分。

**审计收敛声明（2026-11-12）**：原 20 类缺口全部 ✅/🟡。其后 9 个维度的系统审计
（键盘缺失、悬停缺失、焦点环契约、浮层关闭三路、方向键边界、光标形状、滚动交互、
浮层栈次序、指针细节/激活）共补 6 个真实缺口、其余判定为刻意设计并写入契约文档——
详见下方"审计之外的补充发现"。交互面已饱和；后续仅随真实用例增补。

| # | 缺口 | 最终状态 | 落点（提交 / 文件 / 测试） |
|---|---|---|---|
| 1 | 字段族点击聚焦无可见变化 | ✅ | `9fe49b3`：`drawTextBoxChrome` 激活边 + 键盘外环；`pointerFocusPaintsActiveFieldChrome` 等 4 例 |
| 2 | 自绘件不在 Tab 焦点环 | 🟡 | 框架：`bd05059` FocusTarget + `c62b524` `registerFocusStop` + `e5ee7f9` `drawFocusRing`；应用：补丁 0002（ClickArea 40+ 处 + GhostIconButton）|
| 3 | 全应用 0 autofocus + 弹窗不恢复焦点 | 🟡 | 框架：`3426fb5`（Modal 初始聚焦+恢复、Drawer 恢复）；应用：补丁 0001（登录/TOTP/服务器弹窗）|
| 4 | 表单 Enter 不提交 | 🟡 | 框架：`a3bb419` `TextField(onSubmit:)`；应用：补丁 0001（登录、建合集、搜索、服务器编辑）|
| 5 | Slider 键盘聚焦不可见 | ✅ | `cdd5924`：焦点环 + Up/Down/Home/End；`sliderKeyboard*` 3 例 |
| 6 | Pagination/StepIndicator/Breadcrumb/WordCloud 不可聚焦 | ✅ | `9fe49b3` + `1db7709`；`pagination*`/`breadcrumb*`/`stepIndicator*`/`wordCloud*` 10 例 |
| 7 | 无键盘滚动 / PageUp·PageDown | ✅ | `37573de` Key 枚举 + ScrollView；`54c5092` TextArea 翻页；`8671b44` LazyRow；`scrollView*`/`textAreaPageKeys*` 5 例 |
| 8 | 焦点不滚入视野 | ✅ | `d509011` + `7b20493` + `8671b44`：矩形上报 + ScrollView/LazyColumn/LazyRow 最小滚动；6 例 |
| 9 | 行无 hover 高亮（含 Shift 区间选择） | ✅ | `16d164b` 行 hover（ListView/Table）；`9327573` ListView 区间选择；`5e308c7` **Table 区间选择**（同一锚点模式，`selectionRange()` 返回按显示序展开的原始行索引）。TreeView 需要时照搬（同一模式） |
| 10 | 悬停视觉普遍缺失 | ✅ | `8b1c3c6` 字段族三态、`bba0ef6` 开关/单选/复选/滑块、`16d164b` 行 hover；带悬停视觉的控件文件 4→11 |
| 11 | 按下态缺失 + 长按不连发 | ✅ | `8f44d11` 实心按钮按下/悬停；`ebf79bd` `KeyRepeat` 连发（无需改 L 层协议）；5 例 |
| 12 | 焦点视觉语言不统一 | ✅ | 全部走 `showFocusRing`+`drawFocusRing`（并已公开给应用）；PR §六核对无旁路 |
| 13 | 右键/上下文菜单不可用（含键盘唤起） | ✅ | `3a143fd` ContextMenu Menu/Shift+F10；`808332e` MenuBar Menu/F10；4 例 |
| 14 | Toast 不可关闭且穿透 | ✅ | `670d77f`：点击关闭/不穿透/悬停暂停；4 例 |
| 15 | Tooltip 只认鼠标 | ✅ | `38299bd` 键盘聚焦即显；`tooltipShowsOnKeyboardFocusImmediately` |
| 16 | Radio 组内方向键 / 连发 | ✅ | `81fe548` `groupRange`（opt-in）；连发见 #11 `KeyRepeat`；3 例 |
| 17 | 只读字段语义矛盾 | ✅ | `1db7709` 只读不进焦点环、不抢焦；`editableTextAreaJoinsFocusRingButReadOnlyDoesNot` 等 2 例 |
| 18 | 中文双击选词退化 | ✅ | `9fdc0b4` 按 Unicode 脚本分组（8 类字符分类）；`c117d4b` Ctrl+方向键跳词 / Ctrl+Backspace·Delete 删词（同一套脚本分类，汉字连续串整串算一词） |
| 19 | RichText 完全无交互 | ✅ | `3dfae21` `RichSpan.link`（accent+下划线+手型+点击）；2 例。应用暂无使用点，API 已备 |
| 20 | 禁用态等打磨 | ✅ | `8b1c3c6` 禁用蒙版随圆角；`7e7de10` Picker/Stepper Home/End + Table 键盘排序；ComboBox 展开亮边经核对**已由** `closedSurface(active=open)` 覆盖；Drawer 焦点陷阱经核对与文档化设计相悖（非模态、刻意无陷阱）**不应实现** |

## 汇总

- ✅ 完成并测试：**16**
- 🟡 框架完成、应用补丁已备：**3**（#2 #3 #4）
- 🔶 部分：**0**
- 未动：**0**

> **20 类缺口全部落地。** 其中两项经核实判为「不应做」（ComboBox 展开亮边已有、Drawer 焦点陷阱与设计相悖）；
> #9 的多选集合语义留给应用层按需在 `selectionRange()` 之上展开。`Table`/`TreeView` 的区间选择可复用
> ListView 的锚点模式（`localState` 锚点 + `applySelection(keepAnchor)`），按需照搬即可。

### 设计取舍说明（#9）

### 浮层关闭路径一致性核查（第 57 轮）

对 8 类浮层（Modal/Drawer/Dropdown/ContextMenu/MenuBar/ComboBox/DatePicker/TimePicker）逐条核对
三种关闭方式：

| 关闭方式 | 结果 |
|---|---|
| `Esc` | 8/8 齐备 |
| 点击外部 | 8/8 齐备 |
| `Tab`（焦点离开） | **7/8 —— ContextMenu 缺失**：Tab 落到 `case _ => false`，外壳遍历把焦点移到菜单背后而菜单仍留在屏幕上 → 已补 `bf2ad42`（Tab 关闭且不消费事件，与 Dropdown 一致，带 1 个用例） |

### 审计之外的补充发现（第 47–48 轮）

- **RichText 链接只有鼠标可用**（第 48 轮）：上一批做的 `RichSpan.link` 可点但焦点不可达。已补
  `92680c2`：含链接时登记停靠点，Left/Right 切换链接、Enter/Space 触发、焦点环画在选中链接上。
- **扫描方法修正**：第 47 轮用 `grep 'KeyDown(Key.'` 判断键盘支持，漏掉了
  `case UiEvent.KeyDown(key, _)` 这种先解构键的写法，误判 SplitView 无键盘并做了重复实现
  （已回退——既有测试 `splitViewKeyboardNudgesFocusedDivider` 证明它对）。改用 `grep 'KeyDown'`
  重扫后，真正"只有鼠标"的只剩 RichText（本轮已补）与 Toast（Esc 关闭会与全局 Esc 语义冲突，
  刻意不做）。

- **ReorderableList 只能拖拽重排**：handle 里只有鼠标事件，键盘用户完全无法调整顺序——
  审计时未覆盖到此控件。已补 `daeef09`：Alt+Up/Down 移动持焦行，走与拖拽同一条 `onMove`。
- 同批核对 `Accordion`/`Rating`/`TreeView`/`SplitView` 的键盘覆盖：Accordion 头是 Button
  （键盘天然可用）、Rating 与 TreeView 键位齐全、SplitView 分隔条可聚焦——均无缺口。

### #20 中两项"核对后不应做"的说明

- **ComboBox 展开态不亮边**：审计时看漏了——`dropdown.cj` 的 `closedSurface` 本就把
  `open.value` 当 active 传入（:78），展开即 accent 边，无需改。
- **Drawer 焦点陷阱**：与 Drawer 的文档化设计直接相悖（"非模态、无焦点陷阱、阅读器
  翻页键需要穿透"是刻意行为，见 `drawer.cj` 头注）。加陷阱会破坏阅读器侧栏场景。
