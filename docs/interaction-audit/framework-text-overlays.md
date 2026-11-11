# cui 框架：文本输入族 + 浮层控件 交互缺口审计

> 审计员：audit-text-overlays　任务：task-1　基线：/workspace/lanlu/lanlu（只读，未编译、未真机复跑）
> 范围：`packages/cangjie-gui/src/text/*`（TextField / TextArea / ComboBox / RichText / text_edit_state /
> text_input_cursor / text_history）与浮层类控件（modal / drawer / context_menu / menu_bar / dropdown /
> date_picker / time_picker / toast / core/tooltip）。
> 根因（`docs/interaction-audit/00-root-cause.md`）已查明，本报告直接引用、不重复调查：
> `core/theme_state.cj:435` `showFocusRing`＝键盘焦点才画；`:441` `focus(id, viaKeyboard!)` 指针聚焦置假；
> `theme_state.cj:178-199` `fieldSurface(active)` 的 accent 边只由 active 决定。

## 范围

- 覆盖：上列 9 个浮层/菜单控件 + 文本族 4 个控件 + 3 个共享文本模型（text_edit_state / text_input_cursor / text_history）。
- 不覆盖：framework-controls 报告里的 Button/Table/Tree/Slider 等；应用层（client-next）自绘控件只在
  「第 17 项」处**引用**一行对照证据，详情归 app-layer 报告。
- 判定方法：逐控件读 `handle`/`draw`/`registerFocusable`，并用全仓 grep 反证「确实没有」：
  `isHovered|hoverId`（仅 basic_widgets:617 / icon_widgets:219 / accordion:217 / split_view:171 命中）、
  `ctx.press(|isPressed(`（仅 basic_widgets / icon_widgets / common_controls:428 / selection_widgets:79 命中）、
  `Key.(Home|End|PageUp|PageDown|Escape|Tab|Space|Enter)`、`claimHover`、`registerFocusable`、`fieldSurface`、`drawFocusRing`。

## 结论速览

| 组件 | 缺失交互 | 等级 | 成本 | 证据 |
|---|---|---|---|---|
| TextField | 点击聚焦无任何描边/底色变化（唯一反馈是光标闪烁） | 高 | S | text_field.cj:120 → text_area.cj:400-401；theme_state.cj:435/441/178 |
| TextField | 悬停无视觉反馈（无 isHovered、fieldSurface 无 hover 分支） | 中 | S | text_field.cj:218-249；theme_state.cj:178-199 |
| TextField | 只读态语义矛盾：不在 Tab 环、无 I-beam，但点击仍聚焦并画光标、可拖选 | 中 | S | text_field.cj:80-82、221、275；text_input_cursor.cj:112 |
| TextField | 双击选中词对中文退化：CJK 与标点同属 class 2，双击选中整段连续汉字 | 中 | S | text_edit_utf8.cj:15-27；text_edit_state.cj:70-99 |
| TextField | 无 Esc 取消/失焦；无按词删除（Ctrl+Backspace/Delete） | 低 | M | text_field.cj:224-247（无 Escape 分支）；lgui/src/events.cj:6-22（Key 枚举无 PageUp/词删） |
| TextArea | 点击聚焦无描边（同 TextField 链路） | 高 | S | text_area.cj:145、388、401 |
| TextArea | 无悬停反馈 | 中 | S | text_area.cj:149-153（只有 claimHoverIfInside，无 isHovered 绘制） |
| TextArea | 无 PageUp/PageDown 翻页、无 Ctrl+Home/End 文档首尾 | 中 | M | text_area.cj:176-188；lgui/src/events.cj:6-22 无 PageUp/Down |
| TextArea | 只读态同样「点击可得焦点但不在 Tab 环」 | 中 | S | text_area.cj:91-93、205-212、275 |
| ComboBox | 弹层打开时折叠字段不显示 accent（与 Dropdown/Picker 三个同类不一致） | 中 | S | combo_box.cj:56、78-79（走 TextField chrome，无 `|| open`）；对比 dropdown.cj:77 |
| ComboBox | 整个控件 hover 给 I-beam（含右侧 chevron 热区） | 中 | S | text_field.cj:221（整框 claim Text）＋ combo_box.cj:245-247 |
| ComboBox | 弹层内无 Home/End、无 PageUp/Down | 中 | S | combo_box.cj:185-193（只有 Down/Up） |
| ComboBox | 折叠态无悬停/按下反馈 | 中 | S | combo_box.cj:89-105 |
| RichText | 无任何交互：不能选中、复制、点击链接 | 低 | M | rich_text.cj:163-165（handle 恒 false） |
| Modal | 打开时无初始焦点（不聚焦首个可交互项），也无 autofocus 接口 | 高 | S | modal.cj:114-116、147-167（无 ctx.focus）；对比 text_field.cj:242-245 |
| Modal | 关闭后不恢复打开前的焦点 | 中 | S | modal.cj:242-254（dismiss 无 focus 处理） |
| Modal | 无默认按钮（Enter 不激活主操作） | 中 | M | modal.cj:151-165（无 Key.Enter 分支） |
| Modal | 内容超高不滚动，直接按 maxContentH 裁切布局 | 中 | M | modal.cj:100-107 |
| Drawer | 无焦点边界：Tab 会从抽屉内跑到遮罩下内容（Modal 有 focus trap，Drawer 没有） | 中 | M | drawer.cj:36-148 无 focusableIds 覆盖；对比 modal.cj:143-145 |
| Drawer | 打开时无初始焦点、关闭后不恢复焦点 | 中 | S | drawer.cj:125-148 |
| ContextMenu | 键盘完全无法唤起（只认右键；Key 枚举无 Menu 键/Shift+F10） | 高 | M | context_menu.cj:60-75；lgui/src/events.cj:6-22 |
| ContextMenu | 菜单内无 Home/End；无子菜单模型 | 低 | M | context_menu.cj:130-135；menu_popup.cj:19-51 |
| MenuBar | 无 Alt/F10 全局唤起、无字母记忆键（mnemonic） | 低 | M | menu_bar.cj:81-101、150-215；events.cj:6-22 |
| Dropdown | 折叠字段无悬停反馈；无按下态 | 中 | S | dropdown.cj:76-84、99-114 |
| Dropdown | 弹层内无 Home/End/PageUp/Down；无 type-ahead（输字母跳项） | 中 | M | dropdown.cj:189-194、99-114 |
| DatePicker | 不能直接键入日期（只能点选/方向键） | 中 | M | date_picker.cj:119-133（无 TextInput 分支） |
| DatePicker | 折叠字段无悬停反馈；无 PageUp/Down 翻月 | 低 | S | date_picker.cj:102-110、214-219 |
| TimePicker | 只能键入分钟，小时必须点选 | 中 | M | time_picker.cj:228-230（只 Digit→分钟）、125-139 |
| TimePicker | 折叠字段无悬停反馈；小时网格无键盘游标 | 低 | S | time_picker.cj:108-116、260-275 |
| Toast | 不可关闭、不可暂停：无 hover 暂停、无关闭按钮、无 Esc/点击 | 高 | M | toast.cj:91-146（无 MouseDown/Key 分支） |
| Toast | 点击穿透：toast 区域不消费事件，点到的是下层控件 | 中 | S | toast.cj:135-146（恒 return false）；desktop_app.cj:429-432 |
| Tooltip | 仅指针 hover 触发，键盘聚焦不显示 tooltip（键盘用户永远看不到） | 高 | S | tooltip.cj:41-58（只看 ctx.mouseX/mouseY） |
| Tooltip | 无 Esc/点击关闭；无最大宽度换行；单槽位互相覆盖 | 低 | S | tooltip.cj:55-57、100；theme_state.cj:532-535 |
| 全部字段族 | 键盘焦点只有 accent 边、没有按钮族那圈 drawFocusRing 外环（两套视觉语言） | 中 | S | text_area.cj:400-401 vs basic_widgets.cj:568、surface_draw.cj:52 |
| TextField(`chrome:false`) | 自绘外壳模式连焦点边都没有（当前仓库无调用点，应用层一用即踩） | 中 | S | text_field.cj:50、119-121 |
| 全部 | 禁用态蒙版是方块填色，不随控件圆角（圆角输入框会被切成方角） | 低 | S | widget_modifiers.cj:118-122 |

**计数：高 6 项、中 22 项、低 8 项，共 36 项。**
（高 6 项＝TextField 点击无描边、TextArea 点击无描边、Modal 无初始焦点、ContextMenu 键盘不可达、
Toast 不可关闭、Tooltip 键盘不可达。「字段族 Tab 焦点视觉与按钮族不统一」计为中。）

**待查（不删、但不作为结论）**：IME 组词中间态在真机的实际表现（框架层只有 `UiEvent.TextInput`，
无 composition 事件，见 text_input_cursor.cj:127/204 只报候选窗锚点）；`.enabled(false)` 的方块蒙版在圆角
输入框上的实际观感；MenuBar 打开菜单后焦点是否应迁入菜单（当前仍留在 bar 上，仅在 overlay 内处理按键）。

## 逐控件明细

### TextField（text/text_field.cj，405 行）

已有：点击聚焦＋光标落位、双击选词/三击选行（:277-284）、拖选（:226-230）、Shift+方向扩选（:316-327）、
Home/End（:236-237）、Ctrl+A/C/X/V/Z/Y（:329-357）、撤销重做与合并（text_history.cj:36-56）、
掩码模式（:167-191）、横向跟随滚动（:199-216）、IME 候选窗锚点（text_input_cursor.cj:127）、
悬停 I-beam（:221，但仅 editable）、autofocus（:87-90、242-245）、Tab 可达（:80-82 注册）。

缺失：
1. **点击聚焦无描边（高/S）**：`draw` 只调 `drawTextBoxChrome`（:119-121）→ `fieldSurface(showFocusRing(id))`
   （text_area.cj:401）；指针聚焦时 `focusRingVisible=false`（theme_state.cj:441），故边框仍是常态 `panelEdge`。
   用户可感知：点进输入框，框线颜色/粗细**一点都没变**，只有光标在闪，和「没点中」无法区分。
2. **悬停无反馈（中/S）**：`handle` 里只有 `claimHoverIfInside(..., CursorShape.Text)`（:221），
   `draw` 无 `ctx.isHovered(id)` 分支，`fieldSurface` 也没有 hover 参数（theme_state.cj:178-199）。
3. **只读态自相矛盾（中/S）**：`editable=false` 时不注册焦点（:79-82）、不给 I-beam（:220-222），
   但 `pressAt` 无条件 `ctx.focus(id)`（:275），于是能点出光标（text_input_cursor.cj:112 只看 hasFocus）、
   能拖选，却不能 Tab 到达。用户可感知：只读字段点一下出现闪烁光标，键盘按 Tab 永远跳不到它。
4. **双击选词对中文退化（中/S）**：`charClassAt` 把 ASCII 词=0、空白=1、**其余（含 CJK 与标点）=2**
   （text_edit_utf8.cj:15-27），`selectWordAt` 按同类扩展（text_edit_state.cj:70-99）→ 双击中文选中
   整段连续汉字（含标点），不是词。
5. **键盘编辑细节（低/M）**：无 Esc（:224-247 无分支）、无 Ctrl+Backspace/Delete 按词删
   （Key 枚举只有 Letter/Digit/RawScancode，lgui/src/events.cj:6-22）。

### TextArea（text/text_area.cj，420 行）

已有：点击聚焦＋光标、双击选词/三击选行（:277-284）、拖选、Shift+方向、上下行（:181-183）、
行首/行尾（:184-187）、Enter 换行（:176）、Ctrl+A/C/X/V/Z/Y（:307-348）、撤销重做、光标行跟随滚动（:249-266）、
滚轮平滑（:170-174）、可拖滚动条（:157-160、163-165）、IME 锚点（text_input_cursor.cj:204）、autofocus（:98-101、192-195）。

缺失：
1. **点击聚焦无描边（高/S）**：`draw`（:132-147）→ `drawTextAreaBox`（:388）→ 同一个 `drawTextBoxChrome`
   （:400-401）。注意 `ctx.hasFocus(id)` 只用于**选区**（:145），chrome 走 `showFocusRing` → 点击后无描边。
2. **悬停无反馈（中/S）**：:151-153 只有 claimHoverIfInside。
3. **翻页/文档首尾（中/M）**：`handle` 无 PageUp/PageDown（:176-188），Ctrl+Home/End 也只走
   `moveToLineStart/moveToLineEnd`（:184-187）；Key 枚举无 PageUp/PageDown（lgui/src/events.cj:6-22），
   要补需走 `RawScancode(Int32)`（events.cj:21），故成本 M。
4. **只读态**：与 TextField 同构（:91-93、205-212、275）。

### ComboBox（text/combo_box.cj，358 行）

已有：内嵌 TextField 的全部编辑能力（:56）、chevron 点击开关（:91-95）、Down 键打开（:96-100）、
Esc 关闭（:178-180）、Enter 提交（:181-184）、Up/Down 移动高亮并保可见（:185-201）、
弹层 hover 高亮行（:316-318）、滚轮＋可拖滚动条（:158-175、326）、空结果占位（:296-301）、
弹层自动翻上/下并内部滚动（:264-280）。

缺失：
1. **展开态不亮边（中/S）**：字段 chrome 完全由 TextField 负责，`ComboBox.draw` 只 `field.draw`＋chevron
   （:78-80），没有 `|| open.value`；而 Dropdown（:77）、DatePicker（:103）、TimePicker（:109）都把
   open 并进 active。用户可感知：点开下拉建议后，同款控件的「选中框」在 ComboBox 上不出现。
2. **chevron 热区是 I-beam（中/S）**：TextField 对整个 frame claim `CursorShape.Text`（text_field.cj:221），
   ComboBox 未在 chevron 上覆盖形状（:245-247 只有命中矩形）。用户可感知：鼠标移到下箭头变文本光标，
   不像可点的按钮。
3. **弹层键盘（中/M）**：只有 Down/Up（:185-193），无 Home/End、无 PageUp/Down。
4. **折叠态 hover/按下**：无（:89-105 无 isHovered/press）。

### RichText（controls/rich_text.cj，305 行）

已有：多 span 富文本换行布局（:214-269）、单行 hug / 多行 fill（:126-136）、布局缓存（:187-199）。
缺失：**完全无交互（低/M）**：`handle` 恒返回 false（:163-165），不能选中/复制，Span 也没有点击/链接语义。
用户可感知：正文里的「富文本」区域无法像 TextArea 那样拖选复制（常被误报为「选不中」）。

### text_edit_state / text_input_cursor / text_history（共享模型）

已有：光标归一化（:35-41）、选区 API（:44-61）、选词/选行（:70-112）、插入/退格/前删（:120-166）、
方向/行内/跨行移动与扩选（:168-283）、光标闪烁与 IME 锚点上报（text_input_cursor.cj:110-132、178-209）、
撤销合并与上限（text_history.cj:36-47，上限 300）。
缺失：无「按词移动/删除」原语（整文件无 word 级移动）；选词粒度问题见 TextField 第 4 条。

### Modal（controls/modal.cj，288 行）

已有：Esc 关闭（:152）、遮罩点击关闭（:158-163）、Tab/Shift+Tab 在弹窗内循环（focus trap，:153-157、172-194）、
所有事件被弹层吞掉（:166）、打开/关闭动画（:96-113）、模糊遮罩（:208-234）、
弹窗内可再开 popup 且压在其上（:118-129）。
缺失：
1. **无初始焦点（高/S）**：`layout/draw/handle` 全文没有 `ctx.focus(...)`；首个可交互项要等用户按 Tab
   （:172-194 的「从无焦点进入第 0 个」）才可见。用户可感知：打开对话框后直接打字／按 Enter 什么都不会发生。
2. **不恢复焦点（中/S）**：`dismiss`（:242-254）只改 presented 并回调，不把焦点还给触发按钮。
3. **无默认按钮（中/M）**：`handleModal` 没有 Key.Enter 分支（:151-165）。
4. **内容超高不滚动（中/M）**：`layout` 用 `maxContentH` 量体后直接 `body.layout(dialogRect.inset)`
   （:100-107），没有滚动容器/裁切，长表单会溢出面板。

### Drawer（controls/drawer.cj，231 行）

已有：Esc 关闭（:152-158）、scrim 点击关闭（:159-165）、面板内指针/滚轮路由到内容（:166-186）、
非面板事件回落给树（:187-190）、滑入滑出弹簧（:102-123）。
缺失：
1. **无焦点边界（中/M）**：Drawer 不覆写 `focusableIds()`（整类 :36-148），抽屉体内的
   `registerFocusable` 是构建期全局登记（ui_build.cj:195-200），所以 Tab 会从抽屉内直接走到遮罩下的控件。
   对比：Modal 用 `contentFocusables` 做 trap（modal.cj:39、71-77、143-145）。用户可感知：抽屉里 Tab 几下，
   焦点跑到被遮住的背景内容上，看起来像「焦点丢了」。
2. **无初始焦点/不恢复焦点（中/S）**：:125-148 无 `ctx.focus`。

### ContextMenu（controls/context_menu.cj，168 行）

已有：右键打开（:62-73）、左键点选执行/空白关闭（:103-109）、其它键关闭（:110-112）、
hover 移动高亮（:113-122，且 popup 内 claim Default 光标 :117）、Esc（:124-126）、Enter（:127-129）、Up/Down
跳过分隔符与禁用项（:130-135、menu_popup.cj:90-109）、视口内夹取（:155-167）、禁用/分隔符/快捷键提示（menu_popup.cj:125-153）。
缺失：
1. **键盘无法唤起（高/M）**：`handle` 只认 `MouseDown(MouseButton.Right)`（:60-75）。
   Key 枚举无 Menu 键 / 无 Shift+F10 表达（lgui/src/events.cj:6-22），要补需解 `RawScancode`。
   用户可感知：纯键盘用户永远打不开这个菜单，单元格/列表项的「右键功能」对他们不存在。
2. **无 Home/End（低/S）**：:130-135 只有 Down/Up。
3. **无子菜单（低/M）**：`MenuItem` 无 children 字段（menu_popup.cj:19-51）。

### MenuBar（controls/menu_bar.cj，298 行）

已有：点击标题展开（:86-92）、悬停切换菜单（:181-185）、Esc/点外关闭（:187-189、158-166）、
Enter/Space 激活（:190-197）、Up/Down 高亮（:198-203）、Left/Right 换菜单（:204-209）、
关闭态 Left/Right/Enter/Space/Down（:93-97）、Tab 关闭并让行（:210-212）、
标题 hover 底色（:275-277）、键盘焦点外环（:272、278-280）、整条 hand 光标（:82）、
空标题可聚焦（focusableControlIdentity，:53）。
缺失：**无 Alt/F10 全局唤起、无字母记忆键（低/M）**（:81-101、:150-215 无 RawScancode/Letter 分支）；
无按下态（无 `ctx.press`）。这是范围内**完成度最高**的控件。

### Dropdown（controls/dropdown.cj，465 行）

已有：点击/Enter/Space/Down 打开（:102-126）、Esc/选中/点外关闭（:156-208）、
展开态与键盘焦点都亮边（:77 `showFocusRing(id) || open.value`，morphSurface :400）、
Up/Down 移动选择并保可见（:189-194、223-249）、滚轮＋可拖滚动条（:158-179、340）、
弹层 morph 动画（:285-350）、hover 行底色（:330-332）、hand 光标（:100）。
缺失：
1. **折叠态无 hover（中/S）**：`draw`（:76-84）无 `isHovered` 分支，只有 hand 光标。
2. **无 Home/End/PageUp/Down（中/S）**：:189-194。
3. **无 type-ahead（中/M）**：`handle` 无 `Key.Letter` 分支（:99-114），桌面下拉的「打首字母跳项」缺失。
4. 无按下态（全文件无 `ctx.press`）。

### DatePicker（controls/date_picker.cj，421 行）

已有：点击/Enter/Space/Down 打开（:122-133）、Esc/点外关闭（:181-184）、Enter/Space 提交（:186-194）、
方向键按天移动并跨月翻页（:202-213、239-244）、Home/End 翻月（:214-219）、Tab 关闭让行（:220-222）、
头部箭头 hover 变色（:329-335）、网格 hover 底色＋今日底色（:383-387）、键盘高亮描边（:388-390）、
展开态亮边（:103）、hand 光标（:120）、可本地化（:20-54）。
缺失：
1. **不能键入日期（中/M）**：`handle` 无 `TextInput`/Digit 分支（:119-133），只能点选或方向键。
   用户可感知：点开日期框后直接敲 2026-11-11 无效，必须先翻月再点日子。
2. **折叠态无 hover（低/S）**：:102-110。
3. **无 PageUp/Down 翻月（低/S）**：:214-219 只把 Home/End 用掉了（与常见日历语义不同）。
4. 打开弹层后网格高亮描边**不区分键盘/指针**（:388-390），和全框架 `:focus-visible` 约定不一致（轻微）。

### TimePicker（controls/time_picker.cj，572 行）

已有：点击/Enter/Space/Down 打开（:128-139）、Esc 两段语义（先撤输入再关，:237-243）、Enter/Space 提交/关闭（:244-259）、
方向键微调（±1 分 / ±1 小时并跨午夜，:260-275）、Tab 提交并让行（:276-279）、
小时网格点击（:172-176）、分钟 −/+（:177-184）、分钟直接键入（:228-230、295-314）、
滑杆拖动含越界跟随（:194-198、204-210、331-334）、区域化光标形状（:214-219）、
展开态亮边（:109）、各子区域 hover 底色（:439-441、471-473）、编辑态字段边（:456）、本地化（:33-49）。
缺失：
1. **小时不能键入（中/M）**：`typeDigit` 只进分钟（:228-230 → :295-314），小时必须点或方向键。
2. **折叠态无 hover（低/S）**：:108-116。
3. **小时网格无键盘游标（低/S）**：方向键是「改值」不是「移高亮」（:260-275），无 Home/End。

### Toast（controls/toast.cj，170 行）

已有：入场上滑淡入/退场淡出（:120-132）、按 age 驱动时钟并续帧（:137-142）、四类配色与 accent 条（:148-160、163-170）、
堆叠（:114-132）、文本裁切（:157-159）。
缺失：
1. **不可关闭/不可暂停（高/M）**：`ToastLayer.handle` 只处理 `Frame`（:135-146），无 MouseDown/Key、
   无 `ctx.isHovered`（`handle` 里没有 claimHover）。用户可感知：报错信息 3.2 秒后自己消失，想复制文字
   或提前关掉都做不到；读屏/慢读用户尤其吃亏。
2. **点击穿透（中/S）**：`handle` 恒 `false`（:135-146），且 toast 直接画在树内（:109-133）而非 overlay，
   于是点到 toast 的文字区时，press 落到下层控件上（desktop_app.cj:429-432 未消费即下发树）。
   这在小窗口/移动端是误触来源。
3. **无操作按钮 / 无 live region（低/L）**：数据模型 `ActiveToast` 只有 message/kind/duration（:24-38）。

### Tooltip（core/tooltip.cj，112 行）

已有：500ms 悬停延迟（:5、47）、到点前用 `requestFrameAfter` 精确续帧（:53）、
移开即重置（:55-57）、气泡自动翻上/夹在视口内（:103-107）、主题反色（:110-111）、
转发子控件全部 measure/layout/draw/handle/focusableIds（:32-86）、弹层打开时让位（desktop_app.cj:464-468）。
缺失：
1. **键盘聚焦不显示 tooltip（高/S）**：只有 `frame.contains(ctx.mouseX, ctx.mouseY)`（:44），
   没有 `ctx.hasFocus(child.focusableId())` 分支。用户可感知：Tab 到图标按钮时永远看不到它的说明文字，
   这是无障碍硬伤（WCAG 3.3.2/4.1.2 的等价诉求）。
2. **不能主动关闭（低/S）**：无 Esc/点击，只能移开指针（:55-57）。
3. **无最大宽度/不换行（低/S）**：`width = textWidth(text) + pad`（:100），长文案会超出窗口宽度。
4. **单槽位覆盖（低/S）**：`showTooltip` 直接写 `tooltipText`（theme_state.cj:532-535），
   同一帧多次注册只有最后一个生效（嵌套 Tooltip 会互相盖）。

## 最该先补的 5 项

### 1. 字段族「点击聚焦也画边，键盘再叠环」（高，S）——直接对应本次用户反馈

- 为什么：这是用户报告的原始现象，且是范围内唯一「点下去完全没有视觉变化」的路径。
- 影响界面：登录（login_view.cj:262/268/285/289）、顶栏搜索（titlebar.cj:1261）、
  批量改名/加标签（detail_view.cj:804-808）、元数据编辑（metadata_edit_view.cj:486/519）、
  设置搜索（settings_content_view.cj:27/169）、所有对话框表单（add_to_tank_dialog.cj:67/124 等）——
  即 client-next 里**全部 TextField/TextArea**。
- 建议改法：改一处共享函数即可覆盖 TextField/TextArea（ComboBox 复用同一路径）：
  `packages/cangjie-gui/src/text/text_area.cj:400-402`
  ```cangjie
  internal func drawTextBoxChrome(ctx: UiContext, frame: Rect, id: String): Unit {
      drawSurface(ctx, frame, ctx.theme.fieldSurface(ctx.hasFocus(id)))  // 点击→accent 1px 边
      if (ctx.showFocusRing(id)) {
          drawFocusRing(ctx, frame, ctx.theme.controlRadius)            // Tab→再叠 1.6px 外环
      }
  }
  ```
  `fieldSurface(active)` 已是现成激活样式（theme_state.cj:178-199），`drawFocusRing` 可直接复用
  （surface_draw.cj:52）。附带收益：字段族与按钮族（basic_widgets.cj:568）视觉语言统一。

### 2. ComboBox 展开态与同类对齐（中，S）

- 为什么：同一屏里 Dropdown/DatePicker/TimePicker 展开会亮边、ComboBox 不亮，属「同类控件行为不一致」，
  用户会当成 bug。
- 影响界面：所有带建议列表的输入（如 settings/token 名称、标签补全类输入。
  `combo_box.cj` 的调用点见 client-next 中 `ComboBox(` 使用处）。
- 建议改法：给 TextField 增加一个「外部激活」入口，或让 ComboBox 自绘一层边：
  `packages/cangjie-gui/src/text/combo_box.cj:78-80` → draw 前若 `open.value` 则
  `drawSurface(ctx, frame, ctx.theme.fieldSurface(true))`，并把内嵌 TextField 用 `chrome: false`
  （text_field.cj:50）构建（:56），避免双层框；对照 dropdown.cj:77 的 `|| open.value`。

### 3. 字段族与选择控件的悬停反馈统一（中，S）

- 为什么：`fieldSurface` 没有 hover 参数，字段族是范围内唯一「悬停零反馈」的一大类；
  而应用层自绘搜索框已经有 hover（titlebar.cj:291-300），对比之下更像坏了。
- 影响界面：全部 TextField/TextArea/Dropdown/DatePicker/TimePicker/ComboBox 折叠态。
- 建议改法：`packages/cangjie-gui/src/core/theme_state.cj:178` 增加
  `fieldSurface(active, hover!: Bool = false)`（hover 时 border = panelEdge.lerp(accent, 0.4)）；
  各控件 `handle` 里补 `claimHoverIfInside`（已有多数已有），`draw` 里读 `ctx.isHovered(id)`。
  现状无 hover 的证据：`isHovered` 全仓仅 4 个控件使用（basic_widgets:617、icon_widgets:219、
  accordion:217、split_view:171）。

### 4. Modal/Drawer 打开时的初始焦点 + 关闭后的焦点恢复（高，S）

- 为什么：对话框打开后直接打字/回车无效，是「弹窗看起来没反应」的典型来源；关闭后焦点丢在空处，
  键盘用户要重新 Tab 一整圈。Modal 有 focus trap 却没有入口焦点，等于 trap 的一半没实现。
- 影响界面：client-next 所有对话框（add_to_tank_dialog、advanced_filter_dialog、detail_dialogs、
  settings 的各类弹窗）与抽屉（reader 侧栏等 Drawer 用法）。
- 建议改法：`packages/cangjie-gui/src/controls/modal.cj`
  - 打开时（presented 由 false→true 的那次 build，或 layout 首帧）：
    `if (ctx.focusId.isEmpty() || !contentFocusables.contains(ctx.focusId)) { ctx.focus(contentFocusables[0], viaKeyboard: true) }`
    —— 或更可控地新增 `Modal(...).initialFocus(id)`，复用 :172-194 的索引逻辑。
  - `dismiss`（:242-254）记录「打开前 focusId」并在关闭动画结束后 `ctx.focus(prev, viaKeyboard: true)`。
  - Drawer 同法（drawer.cj:125-148），并补 `focusableIds()` 把抽屉体做成焦点边界（参考 modal.cj:143-145）。

### 5. Toast 可关闭 + 不穿透（高，S/M）

- 为什么：报错 toast 3.2 秒自动消失、无法复制/提前关闭，还会把点击透给下层控件（:135-146 恒 false，
  且画在树内 :109-133）。这是唯二「用户想交互却完全无入口」的控件（另一个是 Tooltip 的键盘可达性）。
- 影响界面：client-next 所有 `Toaster.show` 提示（保存失败、网络错误、导入结果等）。
- 建议改法：`packages/cangjie-gui/src/controls/toast.cj`
  - 在 `ToastLayer.handle` 里对 `MouseMove` 用 `ctx.claimHover("ToastLayer", CursorShape.Interactive)`
    并把命中 toast 的 `MouseDown` 消费掉（返回 true）→ 消除穿透；
  - 悬停期间不递减 `remainingMs`（`tick` :63-75 增加 paused 参数或按 hover 跳过），
    点击该 toast 即 `items.remove`（需给 `ActiveToast` 一个 dismiss 入口）；
  - 长文案保留：点击只在「关闭按钮热区」时关闭，其余区域点击仅暂停计时。
  - 若要最小改动：只做「不穿透 + 悬停暂停」两项（S），关闭按钮留待下一轮。

> 准第 6 项（高、但成本 M，本轮不列入 5 项）：ContextMenu 键盘唤起
> （`context_menu.cj:60-75` 只认右键；需在 Key 枚举补 `RawScancode` 的 Shift+F10 解析，
> `lgui/src/events.cj:21`），以及 Tooltip 键盘聚焦可见（`tooltip.cj:44` 加 hasFocus 判断，成本只用 S，
> 可与第 3 项同一轮做掉）。

## 附录 A：文本族「点击聚焦无描边」链路一致性（必答）

| 控件 | 边框/底色判据 | 行号 | 光标/选区判据 | 行号 | 点击后是否有描边 |
|---|---|---|---|---|---|
| TextField | `showFocusRing(id)` | text_field.cj:120 → text_area.cj:400-401 | `hasFocus(id)`（选区）、`hasFocus(id)`（光标） | text_field.cj:144；text_input_cursor.cj:112 | 否 |
| TextArea | `showFocusRing(id)` | text_area.cj:145→388→401 | `hasFocus(id)`（选区）、`hasFocus(id)`（光标） | text_area.cj:145；text_input_cursor.cj:184 | 否 |
| ComboBox | 复用内嵌 TextField → `showFocusRing`（**且未并入 open**） | combo_box.cj:56、78-79 → text_field.cj:120 | `hasFocus(fieldId)` 仅用于 Down 键开列表 | combo_box.cj:97、127 | 否（展开也不亮） |
| Dropdown | `showFocusRing(id) \|\| open.value` | dropdown.cj:77、400 | 无光标/选区概念 | — | 否（但展开时亮） |
| DatePicker | `showFocusRing(id) \|\| open.value` | date_picker.cj:103 | 无光标/选区 | — | 否（但展开时亮） |
| TimePicker | `showFocusRing(id) \|\| open.value` | time_picker.cj:109 | 分钟编辑框用 `fieldSurface(editing.value)` | time_picker.cj:456 | 否（但展开时亮） |

**结论**：点击无描边这条链路在文本族**一致**——6 个控件全部把「描边」绑在 `showFocusRing`
（即 `focusRingVisible`，指针聚焦时为假，theme_state.cj:435/441），只有 caret/选区用 `hasFocus`。
分布上的**不一致只有一处**：Dropdown/DatePicker/TimePicker 额外并入了 `open.value`，ComboBox 没有
（combo_box.cj:78-79 对比 dropdown.cj:77）。另外 6 个控件**都没有** `drawFocusRing` 外环
（对比按钮 basic_widgets.cj:568、MenuBar menu_bar.cj:278-280），所以字段族的键盘焦点视觉比按钮族弱一档。
唯一「点击也亮边」的实现不在框架里，而在应用层：client-next 顶栏搜索框
`titlebar.cj:291-300` 用 `ctx.hasFocus(SEARCH_FIELD_ID)` + `ctx.isHovered(hoverId)` 画 accent 40% 边
——这正是用户产生「别的框点了有边、这个没有」落差的来源。

## 附录 B：点击后连光标/选区都没有的控件（必答）

| 控件 | 点击后实际发生什么 | 有无光标 | 有无选区 | 证据 |
|---|---|---|---|---|
| Dropdown | 只 `ctx.focus(id)` + 开 popup | 无 | 无 | dropdown.cj:102-107 |
| DatePicker | 只 `ctx.focus(id)` + 开日历 | 无 | 无 | date_picker.cj:119-133（无 TextInput 分支） |
| TimePicker | 只 `ctx.focus(id)` + 开弹层 | 无（仅弹层内分钟框可编辑） | 无 | time_picker.cj:125-139、456 |
| ComboBox（chevron 区） | 直接 toggle popup，不进字段 | 无（字段本身有点击才有） | 无 | combo_box.cj:91-95、245-247 |
| RichText | 什么也不发生 | 无 | 无 | rich_text.cj:163-165 |
| Toast | 事件穿透到下层 | 无 | 无 | toast.cj:135-146 |
| Tooltip 包裹体 | 转发给子控件，自身无聚焦 | 无 | 无 | tooltip.cj:60-62 |
| ContextMenu / MenuBar 菜单行 | 执行动作并关闭 | 无 | 无 | context_menu.cj:143-148；menu_bar.cj:218-224 |
| TextField / TextArea（只读，`editable:false`） | `ctx.focus` 成功、画光标、可拖选，但 Tab 到不了 | **有** | 有 | text_field.cj:275、144；text_area.cj:275、145；注册在 :79-82 / :91-93 被跳过 |

注：Modal / Drawer 的正文由真实控件子树构成（modal.cj:196-201、drawer.cj:193-198），
焦点与光标表现取决于放进去的控件，本体没有可视角焦点。
