# 框架基础控件交互审计（cui / lgui.cui）

> 审计范围：`packages/cangjie-gui/src/core/*` 与 `src/controls/*`（除文本编辑外，文本控件归 task-1/3 口径）。
> 方法：只读源码审计，每条结论附 文件:行号 证据；"用户可感知表现"描述缺失项落地后的症状。
> 框架既有约定（引用，不再展开调查）：焦点描边只随键盘焦点绘制 —— core/theme_state.cj:435-437 `showFocusRing(id) = focusId==id && focusRingVisible`；core/theme_state.cj:441-445 `focus(id, viaKeyboard!=false)` 指针点击置假；packages/cangjie-gui/docs/api-reference.md:127-129 有明确记载。**这是刻意模仿 web :focus-visible，不是缺陷**，下文凡涉及"点击聚焦无描边"均按此口径判为"符合约定"。

## 范围

- core：basic_widgets.cj（Button/Label/Spacer）、icon_widgets.cj（Icon/IconButton/Divider）、advanced_layouts.cj（ZStack/Grid/FlowRow/ScrollView）、scrolling.cj（SmoothScroll/ScrollBar/HScrollBar）、overlay.cj、event_handler.cj、theme_state.cj（焦点/悬停/按压管线）、widget.cj / widget_modifiers.cj（enabled 修饰器）、ui_build.cj / state.cj（焦点环登记）、desktop/desktop_app.cj（事件分发，作为管线佐证）。
- controls：common_controls.cj（Switch/RadioButton/Picker/Stepper）、selection_widgets.cj（Checkbox/ListView）、value_widgets.cj（ProgressBar/Slider）、navigation_widgets.cj（SegmentedControl/TabView）、tree_view.cj、table.cj、pagination.cj、rating.cj、chip.cj、accordion.cj、split_view.cj、step_indicator.cj、breadcrumb.cj、badge.cj、progress_ring.cj、word_cloud.cj、reorderable_list.cj。
- 应用对照：client-next/src/ui 实际用到 Button(90)、IconButton(27)、Switch(14)、ScrollView(11)、SegmentedControl(9)、LazyList(5)、Stepper(2)、LazyRow(2)、Slider(1)、LazyColumn(1)、Breadcrumb(1)、WordCloud(1)、Badge(1)（grep 统计）；Pagination/Table/TreeView/Accordion/Checkbox/RadioButton/TabView/Rating/Chip/SplitView/StepIndicator/ProgressRing/ReorderableList 目前 client-next 0 处使用。

## 结论速览

等级：高=多数用户每天会撞上；中=特定场景明显；低=打磨项。成本：S=单文件小改；M=单控件内新增状态/绘制分支；L=跨控件或需管线新能力。

| 组件 | 缺失交互 | 等级 | 成本 | 证据 |
|---|---|---|---|---|
| Button/IconButton/Switch/Checkbox/RadioButton/Chip（点击后） | 点击聚焦后无任何可见变化（描边被 :focus-visible 约定关闭、按下态在松手即清）。用户点完看不到"焦点在这" | 中 | M | theme_state.cj:435-437、:441-445（点击置假）；basic_widgets.cj:615-616（pressed 只在按住时着色）、desktop_app.cj:636-642（MouseUp 即 clearPress） |
| 全部 KeyDown 处理（126 处） | 键盘重复（长按连发）未利用 `KeyDown(Key, Bool)` 的 repeat 位，长按方向键/Stepper 只走一步 | 低 | S | lgui/src/events.cj:45（KeyDown 携带 repeat）；src 全部 126 处 handler 匹配 `KeyDown(x, _)` 丢弃该位（grep 统计，0 处使用） |
| Pagination | 无焦点环登记（不可 Tab）、无键盘（Left/Right 翻页）、无按下态、箭头禁用态仅变色不阻断点击之外的键路 | 中 | M | pagination.cj:69-97（handle 只处理 MouseMove/MouseDown，无 KeyDown、无 ctx.focus）；全文件无 registerFocusable/focusableId（grep 0 命中） |
| StepIndicator | 有 onSelect 时仅指针可点；不可聚焦、无键盘、无悬停预览高亮（仅光标形状） | 低 | M | step_indicator.cj:67-82（handle 仅 MouseMove/MouseDown）；无 registerFocusable（grep 0） |
| Breadcrumb | 同上：不可聚焦、无键盘激活（Enter 打开面包屑层级）、无按下态 | 低 | M | breadcrumb.cj:82-100（handle 仅 MouseMove/MouseDown）；无 registerFocusable（grep 0） |
| WordCloud | 词项不可聚焦（整个控件一个 Tab 停都不注册）、无键盘选择；悬停无视觉反馈（只有光标） | 中 | M | word_cloud.cj:147-162（仅 claimHover+MouseDown）；文件头 import 无 focus 系列（word_cloud.cj:7） |
| Slider | 点击聚焦后无描边/无轨道高亮（draw 不读 isHovered/hasFocus，value_widgets.cj:132-151）；无 Home/End/Up/Down/PageUp/PageDown；Space/Enter 无语义 | 中 | M | value_widgets.cj:173-183（仅 Left/Right）；:132-151（draw 无任何焦点/悬停分支） |
| ListView/TreeView/Table | 选中行高亮为唯一反馈；悬停行无 hover 底色；Tab 进入后若焦点在列表上但用户不知当前行（描边只包整框）——中低；无多选/区间选择（Shift+Up/Down） | 中 | L | selection_widgets.cj:300-307（drawRow 仅 selected 分支，无 hovered）；table.cj:330-335（同）；无 Shift 修饰处理（grep `Keyboard.modifiers` 仅 menu_bar/modal/desktop_app 命中） |
| Table | 表头排序仅指针点击（table.cj:203-209）；无键盘列导航（Left/Right 被行选择占用）、无列宽拖拽、无右键菜单；行悬停无反馈 | 中 | L | table.cj:193-237（handle 全集）；:193-195 注释自认"keeps the plain arrow cursor" |
| 全框架（除 context_menu.cj:62） | 右键/上下文菜单：仅 ContextMenu 一处处理 MouseButton.Right，其余控件（Table 行、TreeView 节点、Tab 页签、WordCloud 词）均无右键入口 | 中 | L | grep `MouseButton.Right` 仅 controls/context_menu.cj:62 一处命中 |
| ScrollView | 无键盘滚动（PageUp/PageDown/Space/方向键均不处理）、聚焦无意义（不注册 focusable）；纯键用户无法滚内容 | 中 | M | advanced_layouts.cj:403-442（handle 仅 MouseWheel/MouseDown/MouseMove/MouseUp）；:448-450（focusableIds 仅转发 child） |
| Divider/Badge/ProgressRing/Label | 纯展示，无交互需求 —— 判"符合预期"，不计缺失 | — | — | icon_widgets.cj:283-285、badge.cj:55-57、progress_ring.cj:63、basic_widgets.cj:150-152（handle 返回 false） |
| 全局：焦点初始位置 | Modal 打开时不自动聚焦对话框首个控件（仅 Esc/Tab 已实现，Tab 首次按下才进入环）；抽屉 drawer.cj 同样无初始聚焦 | 中 | M | modal.cj:147-167（handleModal 无 present 边沿的 focus 调用）、:172-193（仅 Tab 循环时 focus）；drawer.cj 全文件无 focus 调用（grep 0） |
| 全局：焦点滚动跟随 | Tab 把焦点移出视口（长表单/ScrollView/LazyList）时容器不会滚到聚焦控件（无 reveal-on-focus 逻辑） | 中 | L | grep `revealFocused\|scrollToFocus\|scrollIntoView` 0 命中；theme_state.cj:405-424 moveFocus 只改 focusId |
| disabled 一致性 | `.enabled(false)` 统一：遮罩变灰（widget_modifiers.cj:118-122）、拦事件（:143-149）、摘除 Tab 停（widget.cj:202-209）——**框架侧已统一，判"有"**；但 Pagination/StepIndicator/Breadcrumb 的内部"禁用箭头/未到达步骤"只有变色，点击路径也无键路可言（见各自行） | 有(修饰器) / 内部禁用不一致 | — | widget_modifiers.cj:118-149、widget.cj:202-209 |

## 逐控件明细

判定口径：光标形状 / 悬停反馈 / 按下态 / 点击聚焦可见性 / Tab 可见 / Enter/Space / 方向键导航 / Esc / 禁用态 / 右键 / 滚轮+滚动条 / 二次交互 / 初始焦点 / registerFocusable。

### core/basic_widgets.cj — Button
- 已有：悬停光标 Interactive（:573 claimHoverIfInside）；悬停变底 fieldActive（:617-621）；按下态 accentSoft（:615-616，press 于 :578、MouseUp 后 shell 清除 desktop_app.cj:641）；键盘聚焦描边（:567-569 showFocusRing→drawFocusRing）；Enter 激活（:588-592）；Space 激活（:593-597）；Tab 登记（:512 focusableControlIdentity→ui_build.cj:203-207）。
- 缺失：点击聚焦后无任何可见变化——描边被约定关闭（theme_state.cj:441-445），Normal 角色按下色只在按住瞬间存在，松手即消失（desktop_app.cj:636-642）。用户感知：点完按钮屏幕毫无"刚才点了它"的痕迹，键盘用户 Tab 一圈也分不清哪个是"刚点过的"。Primary/Danger 角色连按下变色都没有（basic_widgets.cj:612-626 仅 Normal 分支改样式）。无长按/双击语义（合理，不计）。无右键。
- 证据行：basic_widgets.cj:560-628。

### core/basic_widgets.cj — Label / Spacer
- 纯展示：handle 返回 false（:150-152、:480-482），无任何交互，符合预期。缺失不计。

### core/icon_widgets.cj — IconButton
- 已有：光标（:156）、悬停/按下变色（:217-223）、键盘描边（:150-152）、Enter/Space（:171-180）、Tab（:91）。
- 缺失：同 Button——点击聚焦零反馈；Primary/Danger 无按下/悬停变体（:209-231）。带 label 时无 tooltip 机制自身的文本提示（tooltip 属画布层，IconButton 未接 showTooltip，grep IconButton 无 showTooltip 命中）。用户感知：纯图标按钮（client-next 27 处）在禁用语义缺失下不可发现、点完无痕迹。
- 证据行：icon_widgets.cj:138-231。

### core/icon_widgets.cj — Icon / Divider
- Icon 纯绘制（:56-58 handle false）、Divider 纯绘制（:283-285）。符合预期。

### core/advanced_layouts.cj — ScrollView
- 已有：滚轮滚动（:405-417，含嵌套滚动边缘交接）；滚动条拖拽+轨道翻页（:418-421 press→scrolling.cj:222-251；:425-428 drag）；滚动条拖拽时的高亮（:400 active:）。
- 缺失：**键盘滚动全无**——PageUp/PageDown/Space/方向键都不处理（:403-442 无 KeyDown 分支），控件也不注册 focusable（:448-450 仅转发 child），键盘用户面对长内容只有 Tab 穿过全部子控件一条路。用户感知：纯键盘无法翻页浏览；触控板用户正常。无水平滚动变体（LazyRow 有 HScrollBar，scrolling.cj:397-461，ScrollView 只有竖向）。
- (d) 现状结论：滚轮 ✅（SmoothScroll 缓动 scrolling.cj:60-95）；滚动条拖拽 ✅（含轨道点击翻页 0.9 视口步进 scrolling.cj:238-247）；滚动条**无悬停渐显**（reveal 参数只有 LazyRow 的横条用了，lazy_row.cj:156-166；竖向 ScrollView/LazyList/LazyColumn 恒显，advanced_layouts.cj:400、lazy_list.cj:156、lazy_column.cj:158）。键盘滚动 ❌。

### core/scrolling.cj — SmoothScroll / ScrollBar / HScrollBar
- 已有：缓动滚轮（:36-127）、thumb 拖拽（:222-269）、轨道翻页（:238-247）、横向全套（:309-461）。滚动条几何与拖拽映射完备，无缺失（键盘滚动归容器）。

### core/overlay.cj / event_handler.cj
- Overlay 是注册-分发-绘制三件套（overlay.cj:18-36，theme_state.cj:568-654 栈管理），Esc/Tab 语义由各浮层控件自担（modal/dropdown/menu_bar/context_menu/combo_box/date_picker/time_picker/drawer 均 grep 到 Key.Escape）。event_handler.cj 是透传壳（:27-39），无缺失。

### core/theme_state.cj — 焦点/悬停/按压管线
- 已有：Tab 遍历+环（:385-424）、:focus-visible 描边门控（:430-445）、hover 单胜者（:500-529）、press 单槽（:673-686）、多击计数 clickCount（:295、:464-483）、IME 锚点（:546-561）、overlay 栈（:568-654）、blur-on-press（:485-493）。
- 缺失：(a) 管线本身区分 hasFocus（行为）与 showFocusRing（描边）——记录见 api-reference.md:127-129，管线无缺陷；但**没有"指针聚焦后仍给弱反馈"的第三态**，各控件只能二选一（描边关掉后无兜底），这是本轮多项"点击后无反馈"的管线级根因。修复建议见"最该先补"。

### desktop/desktop_app.cj（佐证）
- Tab 外壳消费（:417-428）、按下括号协议 beginPointerPress/settleFocusAfterPress（:405-416）、MouseUp 清 press/drag（:636-642）、hover 括号（:396-404）。

### controls/common_controls.cj — Switch
- 已有：光标+Enter/Space 走公共 toggleInteraction（:77-79 → :416-451，Enter :438-442、Space :443-447）；键盘描边（:72-74）；Tab（:24）；动画 knob（:60-69）。
- 缺失：无悬停反馈（draw :54-75 不读 isHovered——track 色只随 checked）；无按下态（press :428 记了但 draw 不读 isPressed）；点击聚焦后无任何可见变化。用户感知：鼠标划过开关毫无反应，点完也没有"已切换焦点到此"的迹象，只剩 knob 位置本身表达状态。
- (a) 答：Switch 点击聚焦后**无任何可见变化**；描边判据是 showFocusRing（:72），不是 hasFocus。
- 证据行：common_controls.cj:14-84、:416-451。

### controls/common_controls.cj — RadioButton
- 已有：光标/Enter/Space（:150-152 → toggleInteraction）、键盘描边（:145-147）、Tab（:99）、dot 动画。
- 缺失：同 Switch——无悬停、无按下态、点击后无反馈。且**方向键不迁移组内选项**（桌面惯例 Radio 组 Up/Down/Left 在选项间移动；这里 focus 停在单个 RadioButton 上，组间移动只靠 Tab 逐个走），用户感知：键盘选 radio 要按 N 次 Tab。
- (a) 答：点击聚焦后无可见变化；描边判据 showFocusRing（:145）。
- 证据行：common_controls.cj:87-161。

### controls/common_controls.cj — Picker
- 已有：光标（:211）、点击左右箭头（:213-222）、Left/Right 键（:223-232）、Tab（:174 registerFocusable）、聚焦描边以 fieldSurface(active) 呈现（:194 showFocusRing→accent 描边，theme_state.cj:178-199）。
- 缺失：Up/Down 不换值（仅 Left/Right）；Home/End 不跳首尾；无悬停箭头高亮（draw :206-207 固定 mutedText）；点击后描边同样关闭（:194 用 showFocusRing）——点击聚焦后只有文字变化可见。
- 证据行：common_controls.cj:164-260。

### controls/common_controls.cj — Stepper
- 已有：光标（:336）、点击 +/-（:338-347）、Left/Down/Right/Up 四向（:348-367）、Tab（:286）、fieldSurface(showFocusRing) 描边（:329）。
- 缺失：Home/End 跳边界没有；长按连发没有（repeat 位丢弃，见速览行）；+/- 分区无悬停高亮、无按下态；点击聚焦后描边关闭（:329）。用户感知：点完 stepper 外观纹丝不动（除了数字）。
- 证据行：common_controls.cj:262-414。

### controls/selection_widgets.cj — Checkbox
- 已有：光标（:74）、按下→MouseUp 切换（:76-88）、Enter（:89-93）/Space（:94-98）、键盘描边（:68-70）、Tab（:18）、勾选动画（:55-65）。
- 缺失：无悬停反馈（draw :49-71 无 isHovered）；无按下态视觉（press 记账 :79 但 draw 不读）；点击聚焦后无可见变化。
- (a) 答：点击聚焦后**无任何可见变化**；描边判据 showFocusRing（:68）。
- 证据行：selection_widgets.cj:8-107。

### controls/selection_widgets.cj — ListView
- 已有：光标（:203）、点选行（:207-223）、滚轮（:228-231）、滚动条拖拽/翻页（:208、:224-227）、Up/Down/Home/End（:232-235）、选中行滚入视野 revealRow（:181-184、:287-298）、Tab（:139）、整框 fieldSurface(showFocusRing) 描边（:186）。
- 缺失：**行悬停无高亮**（drawRow :300-307 只有 selected 分支）——用户感知：鼠标在列表上移动没有任何行反馈，不知道会点到哪行；Shift+Up/Down 区间多选无（无 modifiers 读取）；PageUp/PageDown 翻页无；左右键无语义（合理）；点击聚焦后整框描边关闭（:186 用 showFocusRing），选中高亮是唯一反馈——若无选中变化则点击后零反馈。
- 证据行：selection_widgets.cj:109-313。

### controls/value_widgets.cj — ProgressBar
- 纯展示（:54-56 handle false），符合预期。有动画（:47）。不计缺失。

### controls/value_widgets.cj — Slider
- 已有：光标（:154）、点击+拖拽（:156-172）、Left/Right 步进（:173-182，连续模式 1/100 步 :199-204）、Tab（:90 registerFocusable）、buffered 次轨道（:139-144）。
- 缺失：**聚焦无描边、无任何焦点可见性**（draw :132-151 完全没有 showFocusRing/hasFocus 分支；Tab 移到 Slider 上用户完全看不出焦点在哪）——这是范围内唯一"键盘聚焦也不可见"的控件；Up/Down 不调值（:173-183 仅 Left/Right）；Home/End、PageUp/PageDown 无；Space/Enter 无语义；knob 悬停无放大/高亮。用户感知：Tab 到滑块后按方向键其实有效（:173），但用户看不到焦点已到位，误以为键盘坏了。
- (a) 答：Slider 点击/键盘聚焦后均无可见变化（无描边分支）；连 hasFocus 都不读。
- 证据行：value_widgets.cj:59-225。

### controls/navigation_widgets.cj — SegmentedControl
- 已有：光标（:58）、点选段（:60-66）、Left/Right 切段（:67-68、:78-84）、键盘描边（:52-54）、Tab（:29）、pill 滑动动画。
- 缺失：无悬停段高亮（draw :45-55 只有 pill 与文字色）；无按下态；点击聚焦后描边关闭（:52）。Home/End 跳首末段无。
- 证据行：navigation_widgets.cj:9-85。

### controls/navigation_widgets.cj — TabView
- 已有：页签光标（:195-197）、点选页签（:315-322）、Left/Right 切页（:323-324、:330-336）、键盘描边（:308-310）、Tab（strip :113/:159，页内控件次序 :116-128 注册/摘除）、懒加载页 keyed 状态（:148-173）。
- 缺失：页签无悬停高亮、无按下态（drawTabs :300-311 仅有 pill）；点击聚焦后描边关闭；Home/End 跳首末页无；无页签中键关闭语义（可辩，不计）。用户感知：点页签除页面切换外无任何反馈痕迹。
- 证据行：navigation_widgets.cj:87-337。

### controls/tree_view.cj — TreeView
- 已有：光标（:174）、点选行/点 chevron 展开（:178-192、:222-231）、滚轮（:197-200）、滚动条（:179、:193-196）、Up/Down/Home/End（:201-204）、Right 展开/下钻、Left 收起/回父（:205-206、:259-294）、Enter/Space 切换展开（:207-208、:296-305）、选中滚入视野（:152-157、:338+）、Tab（:110）、整框描边（:159）。
- 缺失：行悬停无反馈（drawRow 同 ListView 模式）；无 Shift 多选；无右键菜单（树节点典型需求）；点击聚焦后描边关闭。
- 证据行：tree_view.cj:144-336。

### controls/table.cj — Table
- 已有：点行选择（:211-220）、点表头排序（:203-210）、滚轮（:226-229）、滚动条（:200、:222-225）、Up/Down/Home/End（:230-233）、选中滚入视野（:180-186）、排序箭头绘制（:298-316）、Tab（:121 registerFocusable）、整框描边（:170）。
- 缺失：**行/单元格悬停零反馈**（drawRow :330-344 只有 selected 与斑马纹；:193-195 注释明确"claims no hover cursor"——表格连光标都保持箭头，属设计决定，但行悬停底色缺失是交互缺口）；列头无键盘到达（Tab 只到整表，Left/Right 被行选择占用，无法只键盘改排序列）；无 PageUp/PageDown；无右键行菜单；无列宽调整。用户感知：鼠标扫过表格毫无反馈，键盘用户无法操作排序。
- 证据行：table.cj:156-250、:330-344。

### controls/pagination.cj — Pagination
- 已有：悬停光标 Interactive（:71-73，仅可点目标 :101-115）；页格悬停变色 fieldActive（:117-125）；箭头悬停变色（:139-146）；禁用箭头淡化（:147-151）。
- 缺失：**不注册 focusable（全文件 0 命中）→ Tab 永远到不了，键盘用户无法翻页**；无 KeyDown（Left/Right/PageUp 应是标配，:69-97 只有鼠标）；无按下态；disabled 箭头仍会吃掉 MouseDown 并返回 true（:76-81 page>0 为假时也 return true——点击无效果但事件被吞，行为正确，无碍）。用户感知：纯键盘用户面对分页束手无策。
- 证据行：pagination.cj:30-160。

### controls/rating.cj — Rating
- 已有：光标（:85）；悬停预览打分（:58-66、:122-128）；点击设值/再点清零（:87-94、:150-158）；Left/Down/Right/Up/Home/End（:95-100）；readonly 不注册焦点不吃事件（:32-34、:50-55、:81-84）；键盘描边（:76-78）；Tab。
- 缺失：Space/Enter 不能"确认/清零"（桌面上 Space 常清零）；点击聚焦后描边关闭（:76）；无按下态。整体最完整的控件之一。
- 证据行：rating.cj:20-129。

### controls/chip.cj — Chip
- 已有：光标（:73）、点击切换（:75-79）、Space/Enter（:80-81、:91-97）、键盘描边（:59-61）、Tab（:25）、悬停变色（:51-56，直接读 mouseX/mouseY）。
- 缺失：无按下态；选中态(on)时无悬停反馈（:48-49 on 分支直接 accent，不判 hovered）；点击聚焦后描边关闭。
- 证据行：chip.cj:40-98。

### controls/accordion.cj — Accordion
- 已有：悬停光标+header 悬停变色（:121-127、:217-222）；点击切换（:139-145）；Enter/Space 切换聚焦 header（:146-151、:182-190）；键盘描边（:224-226）；Tab 逐 header（:68、:168-180）。
- 缺失：无按下态；点击聚焦后描边关闭；方向键在 header 间移动无（只能 Tab）；body 内控件 Tab 次序正确（:168-180）。整体良好。
- 证据行：accordion.cj:111-231。

### controls/split_view.cj — SplitView
- 已有：divider 光标随轴（:116-117 resizeShape）；拖拽（:126-139）；键盘描边（:193-195）；方向键 nudge（:140-142、:254-259）；Tab 到 divider（:79，次序 first→divider→second :157-167）；悬停/拖拽时线与 grip 变 accent（:171-183）。
- 缺失：Home/End 无（跳最小/最大比例）；无双击复位默认比例（桌面常见）。属打磨。
- 证据行：split_view.cj:104-259。

### controls/step_indicator.cj — StepIndicator
- 已有：可点已达步骤（:73-78）；hover 光标（:70-72，仅当有回调）。
- 缺失：不注册 focusable（0 命中）、无键盘（Enter 应回跳步骤）、无悬停视觉（只有光标）、无按下态。onSelect=None 时整控件纯展示（合理）。
- 证据行：step_indicator.cj:67-97。

### controls/breadcrumb.cj — Breadcrumb
- 已有：hover 光标（:84-86，仅可点段）；点击回调（:87-96）；可点段悬停变色 fieldActive（:120-122）；当前段/不可点段正确弱化（:123-129）。
- 缺失：不注册 focusable（0 命中）、无键盘（Left/Right+Enter 导航）、无按下态。用户感知：键盘用户无法沿面包屑回跳。
- 证据行：breadcrumb.cj:65-131。

### controls/badge.cj — Badge / controls/progress_ring.cj — ProgressRing
- 纯展示（badge.cj:55-57、progress_ring.cj:63 handle false）。符合预期，不计缺失。

### controls/word_cloud.cj — WordCloud
- 已有：词项 hover 光标（:147-152）；点击词回调（:154-159）。
- 缺失：**整个控件零焦点登记**（import 无 registerFocusable，word_cloud.cj:7；focusableId 未覆写→Widget 默认 None，widget.cj:43-45），Tab 完全绕过；词悬停无变色/放大（draw :138-145 固定 wordColor）；无键盘选择。用户感知：词云对键盘与读屏完全不可达。
- 证据行：word_cloud.cj:138-162。

### controls/reorderable_list.cj — ReorderableList
- 已有：grip 拖拽排序全套（:128-153 抓取/移动/落定；:269-299 提起态阴影+grip 高亮）；拖拽中悬停光标保持（:139-144）；行内容事件路由（:156-165）；focusableIds 转发行内容（:169-177）。
- 缺失：**键盘重排无**（无 KeyDown——grip 自身不注册焦点，Ctrl+Up/Down 惯例缺失）；行悬停无反馈。用户感知：键盘用户无法排序。client-next 未用（0 命中），优先级降。
- 证据行：reorderable_list.cj:120-177。

## 专项问答（任务要求的 a–d）

**(a) Button/IconButton/Checkbox/RadioButton/Switch 点击聚焦后有没有任何可见变化？**
- Button：无。描边走 showFocusRing（basic_widgets.cj:567），点击使 focusRingVisible=false（theme_state.cj:441-445）；按下变色仅按住期间（:615-616，MouseUp 后 desktop_app.cj:641 清除）。点击结束后零痕迹。
- IconButton：无。同构（icon_widgets.cj:150、:217-223）。
- Checkbox：无。showFocusRing（selection_widgets.cj:68），无悬停/按下绘制分支（:49-71）。唯一反馈是勾选状态本身的动画。
- RadioButton：无。showFocusRing（common_controls.cj:145），无悬停/按下分支（:127-148）。
- Switch：无。showFocusRing（common_controls.cj:72），无悬停/按下分支（:54-75）。唯一反馈是 knob 滑动。
- 补充：**Slider 更彻底**——连描边代码都没有（value_widgets.cj:132-151 无任何焦点分支），键盘聚焦也不可见。
- 各控件统一用 showFocusRing 而非 hasFocus 决定描边（grep 32 处一致），与 api-reference.md:127-129 记载的约定相符。

**(b) 键盘 Enter/Space 激活（逐控件行号）**
| 控件 | Enter | Space |
|---|---|---|
| Button | ✅ basic_widgets.cj:588-592 | ✅ :593-597 |
| IconButton | ✅ icon_widgets.cj:171-175 | ✅ :176-180 |
| Checkbox | ✅ selection_widgets.cj:89-93 | ✅ :94-98 |
| Switch | ✅ common_controls.cj:438-442（toggleInteraction） | ✅ :443-447 |
| RadioButton | ✅ 同上（经 :150-152） | ✅ 同上 |
| Chip | ✅ chip.cj:81 | ✅ chip.cj:80 |
| Accordion | ✅ accordion.cj:146-148 | ✅ :149-151 |
| TreeView | ✅ tree_view.cj:207（切换展开） | ✅ :208 |
| ListView/TreeView/Table/Slider/SegmentedControl/TabView/Picker/Stepper/Rating | Enter 无（列表/表/滑块/分段/页签 Enter 无语义属常见，Rating 的 Space 清零惯例缺失） | Space 仅 Chip/Accordion/TreeView/Button 系有；Slider/ListView/Table/TabView/SegmentedControl 无（列表类 Space 常作翻页/选择，缺失） |
| Pagination/StepIndicator/Breadcrumb/WordCloud/SplitView(divider) | ❌（前四者无 KeyDown；SplitView 仅方向键 split_view.cj:140-142） | ❌ |

**(c) 是否所有可交互控件都 registerFocusable？漏登记清单**
已登记（构造期，grep registerFocusable/focusableControlIdentity 42 处）：Button（basic_widgets.cj:512）、IconButton（icon_widgets.cj:91）、Switch/RadioButton（common_controls.cj:24、:99）、Picker/Stepper（:174、:286）、Checkbox/ListView（selection_widgets.cj:18、:139）、Slider（value_widgets.cj:90）、SegmentedControl/TabView（navigation_widgets.cj:29、:113、:159）、TreeView（tree_view.cj:110）、Table（table.cj:121）、Rating（rating.cj:33，readonly 豁免 :32-34 合理）、Chip（chip.cj:25）、Accordion 每 header（accordion.cj:68）、SplitView divider（split_view.cj:79）、文本系（text_field/text_area/combo_box，范围外）。
**漏登记（可交互却无 Tab 停）**：
1. Pagination（pagination.cj 全文件 0 命中）；
2. StepIndicator（有 onSelect 时可点却不可聚焦）；
3. Breadcrumb（有 onSelect 时同上）;
4. WordCloud（整个控件，word_cloud.cj:7 import 即无）；
5. ScrollView（不注册自身合理——它是容器，但作为"滚动手柄"无键盘入口见 (d)）。
注：ReorderableList 的 grip 不注册（reorderable_list.cj:169-177 仅转发行内容），键盘排序因此缺失。

**(d) ScrollView/列表滚轮与滚动条拖拽现状**
- 滚轮：ScrollView（advanced_layouts.cj:405-417）、ListView（selection_widgets.cj:228-231）、TreeView（tree_view.cj:197-200）、Table（table.cj:226-229）、LazyList/LazyColumn/LazyRow（lazy_list.cj:169-174、lazy_column.cj:171-176、lazy_row.cj:179-190 含横向 delta 重映射）全部经 SmoothScroll 缓动（scrolling.cj:60-95，180ms easeOutCubic :9），嵌套滚动边缘交接（advanced_layouts.cj:408-411 注释）。✅ 完整。
- 滚动条拖拽：统一 ScrollBar/HScrollBar 控制器（scrolling.cj:222-269、:414-461）：thumb 抓拖（记录 grabDy 不跳变 :233-236）、轨道点击按 0.9 视口翻页（:238-247）、拖拽中 accent 高亮（drawVerticalScrollBar active 分支 :291-299）。ScrollView/ListView/TreeView/Table/LazyList/LazyColumn/LazyRow 全接入。✅ 完整。
- 缺口：竖向滚动条无悬停渐显（reveal 仅 LazyRow 横条用，lazy_row.cj:160-166；其余恒显，可接受）；键盘滚动无（PageUp/PageDown/Space 全缺，见 ScrollView 行）；滚动条 thumb 无 hover 放大热区。

## 最该先补的 5 项

1. **Slider 补焦点可见性 + Up/Down/Home/End**（value_widgets.cj）
   为什么：范围内唯一"键盘聚焦也完全不可见"的控件，Tab 到了却看不见，键盘可操作性形同虚设。影响：client-next reader_panels.cj 的自动播放间隔滑块（1 处在用，但它是框架完整性短板）。
   改法：draw 末尾加 `if (ctx.showFocusRing(id)) { drawFocusRing(ctx, track.inset(-4.0), 6.0) }`（仿 rating.cj:76-78）；handle 加 `case UiEvent.KeyDown(Key.Up/Down/Home/End)`，复用 :173-182 的 normalize(keyboardStep())（仿 rating.cj:99-100 的 Home/End）。成本 M。

2. **Pagination/StepIndicator/Breadcrumb/WordCloud 补 registerFocusable + Enter/Space（或方向键）激活**（四个文件各自构造器 + handle）
   为什么：可交互却从 Tab 环消失，键盘/读屏用户完全够不到；且都是 S 级改动——构造器加一行 focusableControlIdentity/registerFocusable，handle 加 hasFocus 分支。影响：client-next 当前 Pagination/Table/TreeView 未用，但 Breadcrumb（metadata_edit_view.cj 1 处）与 WordCloud（settings_admin_view.cj 1 处）已在用；Breadcrumb 键盘回跳、WordCloud 键盘可达直接受益。
   改法：照 chip.cj:25+80-81 的最小模板抄（resolveControlKey+registerFocusable；KeyDown Space/Enter → toggleIfFocused 同款）。成本 S/M。

3. **指针聚焦的"弱焦点"兜底**（管线级：theme_state.cj + 各 toggle 控件 draw）
   为什么：本次用户反馈"点击输入框没有描边"暴露的观感问题在按钮/开关一族同样存在——描边被 :focus-visible 约定关掉后没有任何兜底，点击后零痕迹。不必推翻约定，给 pointer-focus 一个弱态即可。影响：所有 90 处 Button、27 处 IconButton、14 处 Switch 等。
   改法：UiContext 增加 `focusViaKeyboard` 读取或在 focus(id) 时记 lastPointerType；Normal 角色控件在 `ctx.hasFocus(id) && !ctx.showFocusRing(id)` 时画细描边/半透明 accentSoft 底（Button draw :560-569 与 buttonStyle :607-628 一处分支即可，Switch/Checkbox/RadioButton/Slider 各加同款）。成本 M。
   （替代方案：仅给 Primary/Danger 补按下/悬停变体，basic_widgets.cj:612-626 的 match 加两分支，成本 S。）

4. **ScrollView/PageUp/PageDown/方向键滚动 + 焦点滚入视野**（advanced_layouts.cj、theme_state.cj:moveFocus）
   为什么：长页面纯键盘不可滚；Tab 移到视口外控件后焦点"消失"（无任何 reveal 逻辑，grep 0 命中），键盘用户迷失。影响：client-next 11 处 ScrollView + 全部长表单。
   改法：ScrollView.handle 加 KeyDown 分支（需 ctx.hasFocus 或子控件聚焦时放行 PageUp/PageDown/Space，复用 SmoothScroll.scrollBy scrolling.cj:71-95，步长=frame.h*0.9 对齐轨道翻页 scrolling.cj:244）；moveFocus（theme_state.cj:405-424）后广播一个 focus-moved 钩子，ScrollView/LazyList 监听并 revealRow（ListView 已有现成 revealRow 模式 selection_widgets.cj:287-298）。成本 M/L。

5. **列表/表格行悬停高亮 + Table 键盘排序列**（selection_widgets.cj:drawRow、tree_view.cj:drawRow、table.cj）
   为什么：悬停反馈是鼠标用户最基本的"我指到哪行"信号，三个数据控件全缺（drawRow 仅 selected 分支）；Table 的排序只有鼠标路径，键盘不可达。影响：ListView/TreeView/Table（client-next 未直接用 Table，但 LazyList 行悬停同样适用）。
   改法：drawRow 开头 `if (ctx.isHovered(controlId) && rowRect.contains(ctx.mouseX, ctx.mouseY))` 需行级命中——把 claimHover 粒度降到行（handle 的 MouseMove 分支逐行 claimHover，id 用 `\${cid}:row:\${i}`），draw 按 hovered 行填 fieldActive（半透明：withAlpha(90)），仿 pagination.cj:117-125 现成写法；Table 排序列键盘化可后置（需 Left/Right 列导航模态，成本 L，建议单独排期）。
   成本 M。

---
*待查项（未在本次时间盒内核实，不进入计数）：(1) 抽屉 drawer.cj 打开时是否聚焦首个控件——grep 未见 focus 调用，倾向"无"，未逐行确认；(2) 悬停 reveal 竖向滚动条是否在别的宿主（dropdown/combo_box）已实现 reveal 补间——dropdown.cj:340 有 reveal 参数传入，宿主补间逻辑未读。*

*计数口径：上表"结论速览"与逐控件"缺失"去重后的缺失项：高 0 / 中 10 / 低 5（其中"中"含 Pagination 键盘缺失、Slider 焦点不可见、列表行悬停缺失、右键菜单全局缺失、ScrollView 键盘滚动、焦点初始位置、焦点滚入视野、WordCloud 可达性、Table 键盘排序、点击聚焦弱反馈管线缺口；"低"含 repeat 位、StepIndicator/Breadcrumb 键盘、Rating Space、SplitView Home/End 双击复位）。*
