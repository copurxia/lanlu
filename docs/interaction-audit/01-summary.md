# 基础交互审计 · 总账与修复优先级

> 审计口径：只读静态取证（本机无 cjc/cjpm，未编译、未真机复跑）。三份分报告：
> [framework-controls.md](framework-controls.md)（框架基础控件）、
> [framework-text-overlays.md](framework-text-overlays.md)（文本族 + 浮层）、
> [app-layer.md](app-layer.md)（client-next 应用层）。
> 根因单篇：[00-root-cause.md](00-root-cause.md)。

## 一、一句话结论

**「点击输入框没有描边」不是渲染/事件故障，而是框架刻意实现的 `:focus-visible` 约定**（描边只给键盘焦点）；
真正的问题是**这条约定在应用里没有兜底态**，而应用层自己画的搜索框又用 `hasFocus` 兜了底，
于是同一交互出现两种表现。顺带审计出的基础交互缺口**去重后 20 类**，
其中 **12 类属于"每天都撞上"**：键盘完全不可达的自绘卡片、全应用 0 处 autofocus、
表单 Enter 不提交、Slider 键盘聚焦不可见、无 PageUp/PageDown、右键菜单只有 1 个入口等。

## 二、三份报告的原始计数（有重叠，供追溯）

| 报告 | 高 | 中 | 低 | 合计 | 范围 |
|---|---|---|---|---|---|
| framework-text-overlays.md | 6 | 22 | 8 | 36 | TextField/TextArea/ComboBox/RichText + Modal/Drawer/ContextMenu/MenuBar/Dropdown/DatePicker/TimePicker/Toast/Tooltip |
| framework-controls.md | 0 | 10 | 5 | 15 | Button/IconButton/Switch/Radio/Picker/Stepper/Checkbox/ListView/Slider/TabView/Table/TreeView/Pagination/Rating/Chip/Accordion/SplitView/ScrollView/… |
| app-layer.md | 6 | 10 | 6 | 22 | client-next 21 个 UI 文件、17 类自绘控件、12 个表单/弹窗 |
| **合计** | **12** | **42** | **19** | **73** | 跨层重复计（如"字段族点击无描边"同时出现在两份） |

## 三、去重归并后的 20 类缺口（总）

等级：**高**＝每天必撞 / **中**＝特定场景明显 / **低**＝打磨项。成本：S 单文件小改，M 控件内加状态，L 跨控件或需管线能力。

| # | 类别 | 影响面 | 用户可感知 | 等级 | 成本 |
|---|---|---|---|---|---|
| 1 | 字段族点击聚焦无可见变化 | TextField/TextArea/ComboBox/Dropdown/DatePicker/TimePicker + 全应用 12 个表单 | 点进输入框，框线颜色一点都不变，只有光标闪，与"没点中"无法区分 | 高 | S |
| 2 | 自绘点击件不在 Tab 焦点环 | ClickArea/GhostIconButton/NavItem/TagChip/MiniSeg/封面卡/CardHoverActions 等 17 类（`registerFocusable` 全 0） | Tab 跳过全部主内容（首页卡片、详情按钮、侧栏、标签），键盘用户到不了任何正文入口 | 高 | L |
| 3 | 全应用 0 处 autofocus + 对话框关闭不恢复焦点 | 登录页、服务器编辑弹窗、新建合集、标签合并、元数据编辑、批量编辑、cron、上传…；框架 Modal/Drawer 也没做 | 打开登录页/弹窗后必须先摸鼠标点输入框；关掉弹窗焦点丢在原地 | 高 | M |
| 4 | 表单 Enter 不提交 | 登录（账号/密码/TOTP/恢复码）、新建合集/新标签、服务器编辑、批量编辑、元数据编辑… | 输完密码回车毫无反应，必须点按钮 | 高 | M |
| 5 | Slider 键盘聚焦完全不可见（连描边分支都没有） | Slider（设置页、阅读器 dock 语速/音量） | Tab 到滑块后看不出焦点在哪，只能盲按方向键 | 高 | M |
| 6 | 四个可点控件不可聚焦、无键盘激活 | Pagination / StepIndicator / Breadcrumb / WordCloud | 分页、面包屑、标签云只能鼠标点 | 中 | M |
| 7 | 无键盘滚动 / PageUp·PageDown（Key 枚举层面就没有） | ScrollView、TextArea、ListView、Table、TreeView、Lazy* | 纯键盘用户无法翻页浏览长内容、长表单 | 中 | M |
| 8 | 焦点移出视口不滚入视野 | 长表单/ScrollView/LazyList 内的 Tab 遍历 | Tab 到看不见的控件，用户以为焦点丢了 | 中 | L |
| 9 | 列表/表格/树行无 hover 高亮、无 Shift 区间选择 | ListView/Table/TreeView/成员列表 | 鼠标划过行毫无反应；多选只能逐个点 | 中 | L |
| 10 | 悬停视觉反馈普遍缺失 | 33 个可交互控件类里只有 4 个读 `isHovered`（Button/IconButton/Accordion/SplitView）；字段族 `fieldSurface` 无 hover 分支 | 鼠标划过输入框、下拉、开关、列表、标签、自绘卡片大多没有任何变化 | 中 | M |
| 11 | 按下（press）视觉态缺失 | Primary/Danger 按钮无按下/悬停变体；Switch/Radio/Stepper/字段族无按下态；自绘件 `ctx.press(` 全 0 | 点按钮没有"按下去"的手感 | 中 | M |
| 12 | 键盘焦点视觉语言不统一 | 按钮/复选/开关用 `drawFocusRing` 外环；字段族只有 1px accent 边；Slider 什么都没有 | Tab 一圈下来，焦点指示忽粗忽细忽无 | 中 | S |
| 13 | 右键/上下文菜单几乎不可用 | 全框架只有 ContextMenu 一处处理 `MouseButton.Right`；应用只给合集成员行/成员卡用；键盘无 Menu/Shift+F10 唤起（Key 枚举无 Menu） | 输入框没有剪切/复制/粘贴菜单，列表没有右键菜单 | 中 | L |
| 14 | Toast 不可关闭且点击穿透 | ToastLayer `handle` 恒 `return false` | 错误提示挡住按钮时点下去是点到底层控件 | 高 | M |
| 15 | Tooltip 只认鼠标 hover | `tooltip.cj` 只看 `ctx.mouseX/Y`，键盘聚焦不显示 | 键盘用户永远看不到图标按钮的说明 | 高 | S |
| 16 | Radio 组内方向键不移动、长按不连发 | RadioButton；全部 126 处 KeyDown 丢弃 repeat 位 | 键盘选 radio 要按 N 次 Tab；长按方向键/步进器只走一步 | 中 | S |
| 17 | 只读 TextField/TextArea 语义矛盾 | 不在 Tab 环、不给 I-beam，但点击仍 `ctx.focus` 并画光标、可拖选 | 点一下只读字段冒出光标，Tab 却永远跳不到 | 中 | S |
| 18 | 中文双击选词退化 / 无按词编辑 | `charClassAt` 把 CJK 与标点归为同一类；无 Ctrl+Backspace、按词移动 | 双击选中的是整段汉字；不能按词删 | 中 | S/M |
| 19 | RichText 完全无交互 | `rich_text.cj` handle 恒 false | 富文本区域选不中、复制不了 | 低 | M |
| 20 | 禁用态/其他打磨 | `.enabled(false)` 蒙版是方块填色不随圆角；Drawer 无焦点陷阱；ComboBox 展开态不亮边；Picker/Stepper 无 Home/End；表头排序仅指针 | 圆角输入框禁用时被切成方角；抽屉里 Tab 会跑到遮罩下面 | 低 | S/M |

## 四、客观覆盖率（33 个"可交互"控件类的源码统计）

按类体扫描 `handle`/`draw`（脚本口径，文本族经共享 `drawTextBoxChrome` 间接实现，单独标注）：

| 能力 | 有 | 占比 |
|---|---|---|
| 悬停视觉反馈（读 `isHovered`） | 4 / 33 | 12% |
| 按下视觉态（读 `isPressed`） | 3 / 33（Button/IconButton/Checkbox；Switch/Radio 记了 press 但不绘制） | 9% |
| 焦点绘制（显式 `showFocusRing`/`drawFocusRing`） | 20 / 33，文本族另 4 类经共享 `drawTextBoxChrome` 间接；**Slider 完全没有** | 61%（+12% 间接） |
| 键盘激活 Enter/Space | 14 / 33（含 Switch/Radio 经共享 `toggleInteraction`） | 42% |
| 方向键/Home/End 导航 | 12 / 33 | 36% |
| Esc | 7 / 33（全是浮层） | 21% |
| 滚轮/滚动条 | 10 / 33（滚动容器齐备，缺键盘滚动） | — |
| 右键菜单 | 1 / 33（ContextMenu） | 3% |
| Tab 环登记（`registerFocusable`/`focusableControlIdentity`） | 17 类（+ComboBox 经内嵌 TextField）；漏登记 Pagination/StepIndicator/Breadcrumb/WordCloud/ReorderableList grip，另应用层 17 类自绘件全 0 | 52% |

## 五、修复优先级（建议排期）

> **进度 2026-11-11（十一轮）**：**P0 与框架侧审计缺口全部完成**（20 类缺口中框架可独立
> 落地的均已落地），应用层接线清单已备好——分支 `p0-focus-visible`
> （工作树 `packages/cangjie-gui-p0`，38 个提交，最新 `92680c2`；应用层 A/B/D 在独立分支
> `app-focus-wiring` 待 cherry-pick，见下）：
> 字段族点击聚焦可见 + 键盘外环；Pagination/Breadcrumb/StepIndicator/WordCloud 键盘化（四个
> 漏登记控件全部收尾）；Slider 焦点可见性 + Up/Down/Home/End；Modal 打开即聚焦/关闭恢复
> 焦点（Drawer 仅恢复）；`Key` 枚举补 PageUp/PageDown/Menu；ScrollView 与 TextArea 键盘滚动
> （含 PageUp/Down）；ContextMenu 键盘唤起（Menu/Shift+F10）；FocusTarget 自绘件焦点底座；
> Toast 可关闭/不穿透/悬停暂停；Tooltip 键盘聚焦即显；只读字段点击不进焦；
> TextField `onSubmit` 回车提交；RadioButton `groupRange` 组内方向键；
> 字段族悬停三态 + 禁用蒙版圆角 + 列表/表格行悬停；中文/日文双击选词按脚本分组；
> MenuBar 的 Menu/F10 唤起；焦点滚入视野（ScrollView + LazyColumn）；实心按钮按下/悬停反馈；
> RichText 可点击链接片段；开关/单选/复选/滑块悬停反馈；LazyRow 键盘横向滚动；
> 开放 `registerFocusStop` 与 `drawFocusRing`（应用层自绘件既能进 Tab 环、也能画同一焦点环）；
> 框架级按键长按连发 `KeyRepeat`（OHOS 无原生 repeat 也能连发）；Picker/Stepper
> Home/End 与 Table 键盘排序（#20 收尾）；按词编辑 Ctrl+跳词/删词（#18 收尾）；
> ListView Shift 区间选择（#9 收尾）——**20 类缺口全部落地**。
> 本机桩库测试 479 例零回归；一条命令复现：`tools/verify-cui-interactions.sh p0`
> （失败名册自动 diff，见 [test-baseline-names.txt](test-baseline-names.txt)）；
> 明细见 [02-p0-batch.md](02-p0-batch.md)；
> 应用层接线按 [03-app-wiring-plan.md](03-app-wiring-plan.md) 执行（A/B 两批已做成补丁：
> [patches-app/](patches-app/README.md)，合并后 `git apply` 即可）；
> 合并操作照 [07-merge-runbook.md](07-merge-runbook.md)（单页：命令、预期输出、失败处理），
> 验收照 [06-acceptance-checklist.md](06-acceptance-checklist.md)（分 A–F 六组可勾选），
> 每条是否有自动化兜底见 [08-coverage-matrix.md](08-coverage-matrix.md)（31 条 / 20 条有测试）；
> **20 类缺口的最终状态**：[09-gap-final-status.md](09-gap-final-status.md)
> （✅13 完成并测试 / 🟡3 应用补丁已备 / 🔶3 部分移交 / 未动 0）；
> 交接包自检（链接/补丁/树一致性/基线）：[10-delivery-selfcheck.md](10-delivery-selfcheck.md) 全部通过；
> 合并评审看 [04-pr-description.md](04-pr-description.md)，合并演练结果见
> [05-merge-rehearsal.md](05-merge-rehearsal.md)（25 补丁零冲突；合并后副本跑测试 **444/403 全绿**，
> 唯一适配项已提前预置 → 落地零手工改动）。

**P0（3 项，合计约 1 天，直接回应本次反馈）**
1. 字段族点击聚焦可见 —— `text/text_area.cj:400-402` 一处改动，覆盖 TextField/TextArea/ComboBox（方案见 00-root-cause.md）。同时给 `fieldSurface` 加 hover 分支（`core/theme_state.cj:178`）。✅ 已提交（`9fe49b3`；hover 分支未含，仍开放）
2. Slider 补焦点环（`value_widgets.cj:132-151` 照抄 `basic_widgets.cj:567-569`）+ Up/Down/Home/End（`value_widgets.cj:173-183`）。✅ 已提交（`cdd5924`）
3. 四个漏登记控件补 `registerFocusable` + 键盘激活（仿 `chip.cj:25` / `chip.cj:80`）。✅ 已完成 3/4（Pagination/Breadcrumb/StepIndicator；WordCloud 未含）
4. （P1-a）Modal/Drawer 初始聚焦 + 关闭恢复焦点。✅ 已提交（`3426fb5`）
5. （P1-c）`Key` 枚举补 PageUp/PageDown/Menu + ScrollView/TextArea 键盘滚动。✅ 已提交（`37573de`、`54c5092`）
6. （#13）ContextMenu 键盘唤起。✅ 已提交（`3a143fd`）
7. （P1-d）FocusTarget 框架底座（自绘件接焦点环）。✅ 已提交（`bd05059`）；应用侧迁移待分支合并
8. （#14）Toast 可关闭、不穿透、悬停暂停。✅ 已提交（`670d77f`）
9. （#15）Tooltip 键盘聚焦即显。✅ 已提交（`38299bd`）
10. （#17）只读字段点击不进焦 +（#6 全部）WordCloud 键盘化。✅ 已提交（`1db7709`）

**P1（5 项，约 2～3 天，键盘可用性）**
4. 框架 Modal/Drawer 支持 `initialFocus` + 关闭恢复焦点（`modal.cj:147-167`、`drawer.cj:125-148`），应用 12 个表单/弹窗接上（`TextField.autofocus()` 已存在，只是 0 处调用）。
5. 表单 Enter 提交（登录页 `login_view.cj:254-294` 加 `Key.Enter`，其余表单同理）。
6. `Key` 枚举补 PageUp/PageDown/Menu（`lgui/src/events.cj:6-22`），ScrollView/TextArea/列表接键盘滚动。
7. 自绘点击件统一补 `focusableId` + Enter/Space + 焦点环（先做 ClickArea 与 GhostIconButton，覆盖首页卡片与详情 6 个图标钮）。
8. ClickArea/ClickSensor 补 `claimHover`（3 行）+ 按下态。

**P2（打磨，约 3～5 天）**
9. 列表/表格/树行 hover 高亮 + Shift 区间选择。
10. 焦点滚入视野（`moveFocus` 后广播 `revealFocused`）。
11. TextField 右键剪切/复制/粘贴菜单（ContextMenu 已具备能力，只是没包裹）；键盘唤起菜单键。
12. Toast 可关闭 + 消费区域内点击；Tooltip 支持键盘聚焦显示。
13. 统一焦点视觉：字段族叠 `drawFocusRing`；`.enabled(false)` 蒙版按控件圆角；ComboBox 展开态并入 `open`。

## 六、审计方法与局限

- 方法：逐控件读 `handle`/`draw`/`registerFocusable`；用全仓 grep **反证**"确实没有"（`isHovered`、`ctx.press(`、`MouseWheel`、`KeyDown`、`registerFocusable`、`MouseButton.Right` 等）；再以脚本按类体扫描出第四节的覆盖率矩阵。
- 局限：本机没有 Cangjie 工具链，**未编译、未真机复跑**；所有"用户可感知"均为源码推断。真机待验证项已单列在各报告的「待查」里（IME 组词中间态、禁用蒙版观感、MenuBar 焦点归属）。
- 未改动任何源码。框架 `packages/cangjie-gui` 是独立 git 仓库，修复需在其中单独提交；`docs/interaction-audit/` 为本次新增。

### 审计期间工作区变动（提醒）

- 审计窗口内（2026-11-11 13:10–13:14 UTC）工作区出现了**不是本次审计产生**的并发改动：
  `client-next/build/ohos/target/**` 构建产物、`packages/lgpu` 与 `packages/webview` 的 native 库重编、
  `docs/lwindow-title-buttons-plan.md`、`docs/lwp-handoff-status.md` 被写入——疑为同一工作区上的另一个构建/文档任务。
- 同期 `packages/cangjie-gui/src/core/theme_state.cj` 上**原先未提交的浅色主题改动被还原成 HEAD**
  （`Theme.light()` 三行：`242,245,249`→`239,241,245`、`255,255,255`→`251,252,254`、`210,217,226`→`205,212,222`；
  见审计开始时 `git diff`）。本审计全程只读，未做该还原；如需恢复，按上述三行改回即可。
