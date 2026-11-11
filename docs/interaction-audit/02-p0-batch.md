# P0/P1 修复批次 · 交付与验证记录

> 分支：`p0-focus-visible`（工作树 `packages/cangjie-gui-p0`，基于 `c39458f`）。
> 对应总账：[01-summary.md](01-summary.md)。提交序列：

| 提交 | 内容 |
|---|---|
| `9fe49b3` | P0-1 字段族点击聚焦可见 + 键盘外环；P0-3 Pagination/Breadcrumb/StepIndicator 键盘化 |
| `cdd5924` | P0-2 Slider 焦点可见性 + Up/Down/Home/End |
| `3426fb5` | P1-a Modal 打开即聚焦/关闭恢复焦点；Drawer 关闭恢复焦点 |
| `8bc83a7` | 文档同步（architecture/components/api-reference/user-guide） |
| `37573de` | P1-c Key 枚举补 PageUp/PageDown/Menu；ScrollView 键盘滚动（PageUp/Down=0.9 视口、方向键 48px、Home/End 直达；子树消费优先） |
| `54c5092` | P1-c TextArea 聚焦时 PageUp/PageDown 翻页（同缓动通路，未聚焦透传） |
| `3a143fd` | P1 ContextMenu 键盘唤起（Menu 键 / Shift+F10，焦点在子树内于控件中心弹出） |
| `bd05059` | P1-d 底座 FocusTarget：自绘内容的可聚焦/可点击包装器（注册停靠点 + Enter/Space + 焦点环 + 悬停光标） |
| `e5b26b1` | 文档：FocusTarget 用法、ScrollView 键盘滚动入册 |
| `670d77f` | P1 Toast 可点击关闭、事件不穿透、悬停暂停计时（缺口 #14） |
| `38299bd` | P1 Tooltip 键盘聚焦即显（缺口 #15） |
| `1db7709` | P1 只读字段点击不进焦（#17）；WordCloud 键盘走词/激活（#6 全部收尾） |
| `81fe548` | P1 RadioButton 可选组内方向键（`.groupRange(lower, upper)`，#16 收尾） |
| `a3bb419` | P1 TextField `onSubmit` 回车提交钩子（#4 的框架原语） |
| `8b1c3c6` | P1 字段族悬停反馈（#10）+ 禁用蒙版按控件圆角（#20） |
| `16d164b` | P1 列表/表格行悬停高亮（#9） |
| `9fdc0b4` | P1 中文/日文双击选词按 Unicode 脚本分组（#18） |
| `808332e` | P1 MenuBar 支持 Menu 键 / F10 唤起（#13 菜单栏部分） |
| `d509011` | P1 焦点滚入视野基础设施（#8）：UiContext 焦点矩形上报 + ScrollView 最小滚动 |
| `7b20493` | P1 LazyColumn 焦点滚入视野 |
| `8f44d11` | P1 实心按钮（Primary/Danger）补按下/悬停反馈（#11 收尾） |
| `3dfae21` | P1 RichText 可点击链接片段（#19，框架侧最后一项） |
| `bba0ef6` | P1 开关/单选/复选/滑块补悬停反馈（#10 最后一块） |
| `2289704` | test 探针预置 `Canvas.releaseTexture`（合并零适配） |
| `8671b44` | P1 LazyRow 键盘横向滚动 + 焦点滚入视野（#7/#8 横排） |
| `c62b524` | P1 开放 `registerFocusStop` / `reregisterFocusStop`（#2 第二个入口） |
| `e5ee7f9` | P1 公开 `drawFocusRing`（应用自绘件画同一焦点环） |
| `ebf79bd` | P1 框架级按键长按连发 `KeyRepeat`（#11/D2，无需改 L 层协议） |
| `7e7de10` | P1 缺口 #20 收尾：Picker/Stepper Home/End + Table 键盘排序 |
| `c117d4b` | P1 按词编辑：Ctrl+方向键跳词 / Ctrl+Backspace·Delete 删词（#18 收尾） |
| `33913285` | （主仓）可复现基线验证脚本 `tools/verify-cui-interactions.sh` + 失败名册 |

## 改动清单（首个提交，7 文件 +512/−50）

| 文件 | 改动 |
|---|---|
| `src/text/text_area.cj` | `drawTextBoxChrome`：激活 chrome 改按 `hasFocus`（点击也变 accent 边），键盘焦点叠 `drawFocusRing` 外环——一处覆盖 TextField / TextArea / ComboBox |
| `src/controls/pagination.cj` | 补 `registerFocusable`/`focusableId`/`claimHoverIfInside`/点击聚焦；Left/Right 翻页（越界 clamp）；删除被 claimHover 取代的死代码 `clickableAt` |
| `src/controls/breadcrumb.cj` | 有 `onSelect` 时进焦点环；点击聚焦；Left/Right 在链接段间移动；Enter/Space 激活；键盘段在 `showFocusRing` 下高亮 |
| `src/controls/step_indicator.cj` | 有 `onSelect` 时进焦点环；点击聚焦并记录键盘步；Left/Right 在已到达步间移动；Enter/Space 选择；键盘步画 accent 圆环 |
| `docs/architecture.md` | 焦点章节改写：`:focus-visible` 收窄为“只管外环”，激活 chrome 归 `hasFocus` |
| `src/text/text_focus_chrome_test.cj` | 新增 4 用例：指针聚焦画激活 chrome、键盘叠外环、未聚焦保持常态、TextArea 同策略 |
| `src/controls/nav_keyboard_test.cj` | 新增 6 用例：Pagination 聚焦+方向键翻页+越界收住、Breadcrumb 键盘走链+激活+纯展示不进环、StepIndicator 键盘走步+激活+纯展示不进环 |

## 行为变化（用户可感知）

- 点击任何输入框（登录、元数据、搜索框外壳以内嵌 TextField 的全部表单）：框线即刻变 accent 色、
  底色变 `fieldActive`、出现 accent 光晕——与顶栏搜索框（应用层自绘 `hasFocus`）终于一致。
- Tab 到输入框：在 accent 边之外再有一圈外扩描边；Tab 到分页、面包屑、步骤条：出现键盘高亮，
  Left/Right 移动、Enter/Space 激活。
- 指针点击的“无外环”约定保留（`:focus-visible`），键盘/鼠标用户仍可区分。

## 验证

- 本机（无 GPU/SDL 设备）用桩库链接：`/workspace/tmp/vips-stub/libvips.so`（vips 25 符号 +
  SDL 31 符号，全部恒空实现）+ `Renderer.useBackend(ChromeProbe)` 记录型画布。
- `cjpm test`（lts 工具链 1.0.5）：**TOTAL 397，PASSED 356**（含新增 10 例全过）；
  ERROR 40 与 FAILED 1（`pushWakeEventWakesWaitingLoopFromAnotherThread`）与改动前基线
  （baseline4：391 例，ERROR 40 + FAILED 1 完全同名单）逐例 diff 后**零回归、零新增失败**。
- 未做真机验证；真机需 OHOS 目标（`sts-1.2.0-linux-x64-ohos` 工具链 + `OHOS_SYSROOT`）重新编译。

## 第二批（`cdd5924` Slider + `3426fb5` Modal/Drawer）

**Slider（P0-2，缺口 #5）**：持有焦点时旋钮描边 2px→3px（点击可见的激活反馈）；键盘到达叠
`drawFocusRing` 外环。键盘补 Up/Down（与 Left/Right 同向）、Home/End（跳到范围两端）；未聚焦
不消费。新增 3 用例（`slider_keyboard_test.cj`）。

**Modal/Drawer（P1-a，缺口 #3）**：Modal 首次 layout 记住当前焦点并在 dismiss 完成后恢复；
同时聚焦弹窗内第一个停靠点（`viaKeyboard: true`，开弹窗即待键入）。Drawer 刻意只做恢复不做
抢焦（非模态侧栏，抢焦会打断阅读器翻页），且仅当关闭时焦点仍在面板内才恢复。
`modalTabCyclesDialogFocusOnly` 语义更新：打开即聚焦 m1，Tab 在 m1→m2→m1 环内移动。
新增 2 用例（`overlay_focus_test.cj`，经 `buildRoot` 构建使焦点停靠点真实登记）。

**第三批（`37573de` Key + ScrollView）**：`lgui` 的 `Key` 枚举补 `PageUp`/`PageDown`/`Menu`
（scancode 75/78/118 解码，此前落到 `RawScancode` 控件层无法匹配）；ScrollView 键盘滚动
（翻页 0.9 视口、方向键 48px、Home/End 直达顶/底），与滚轮同一条 `scrollBy` 通路、子树消费优先。
新增 4 用例（`scroll_keyboard_test.cj`）+ 3 个 scancode 断言。

**第四批（`3a143fd`/`bd05059`/`e5b26b1`）**：ContextMenu 键盘唤起（缺口 #13——Menu 键 /
Shift+F10，焦点在包裹子树内时于控件中心弹出，否则不拦截）；**FocusTarget**（缺口 #2 的框架侧
底座）：自绘内容的可聚焦/可点击包装器，一条链补齐注册停靠点/点击聚焦/Enter·Space 激活/键盘
焦点外环/Interactive 悬停光标，布局绘制透传、子树停靠点保持可达，已从 `cui` 伞包导出——
client-next 的 ClickArea 可薄封装迁移（17 类自绘件键盘不可达的根修）。

**第五批（`670d77f`/`38299bd`）**：**Toast**（缺口 #14，高）——点击关闭（dismiss 幂等）、
toast 区域内按下/抬起消费（不再穿透点到底层控件）、悬停暂停计时（阅读长文案不被打断）；
**Tooltip**（缺口 #15，高/S）——键盘焦点落在子控件停靠点上即显（无延时），失焦消失，
指针路径不变。

**第六批（`1db7709`）**：只读 TextField/TextArea 点击仅选择不进焦（#17 的矛盾消除）；
WordCloud 键盘化（#6 全部收尾）：key 参数 + 焦点停靠点（空词云除外）、Left/Right 走词、
Enter/Space 激活、键盘词下划线 + 整框焦点环。

**第七批（`81fe548`/`a3bb419`）**：RadioButton 组内方向键（opt-in `.groupRange`）；
TextField `onSubmit` 回车提交钩子（应用层十余处表单接上即得回车提交，无需各页自拦 KeyDown）。

**第八批（`8b1c3c6`/`16d164b`）**：字段族悬停反馈（`fieldSurface(active, hovered!)` 三态，
接线 TextField/TextArea/Picker/Stepper/Dropdown/Table/TreeView/DatePicker/TimePicker）；
禁用蒙版改圆角填充；ListView/Table 行悬停高亮。

**第九批（`9fdc0b4`/`808332e`）**：双击选词按 Unicode 脚本分类（汉字/平假名/片假名/谚文/
标点/其他字母各自成组，全角标点不再粘进中文词，日文混排不跨脚本）；MenuBar 支持 Menu 键 /
F10 窗口级唤起。

**第十批（`d509011`/`7b20493`）**：焦点滚入视野（#8）——`UiContext` 新增焦点矩形上报
（Button/IconButton/TextField/TextArea/FocusTarget 已接），外壳每帧清空，ScrollView 与
LazyColumn 在 layout 末尾做最小滚动。

**第十一批（`8f44d11`）**：实心按钮按下/悬停反馈（#11 收尾）——Primary/Danger 按下压暗 18%、
悬停提亮 12%（Button 与 IconButton 统一 `solidFeedback`）。

**可复现验证（`33913285`）**：`tools/verify-cui-interactions.sh [main|p0]` 自动生成 vips/SDL 桩库、
跑 `cjpm test`、并把失败名册与 `docs/interaction-audit/test-baseline-names.txt`（41 个环境相关
失败）逐条 diff——只有名单完全一致才返回 0，新增或消失的失败都会报错。其他协作者可用一条命令
复现本分支的测试结论。

**第十二批（`3dfae21`）**：RichText 链接片段（#19 收尾）——`RichSpan.link` 以 accent 色 +
下划线绘制、悬停下划线加粗并认领手型、点击触发回调；命中按片段矩形，多链接互不干扰。

**第十三批（`bba0ef6`）**：开关/单选/复选/滑块悬停反馈（#10 收尾）——未选中态向 accent
lerp 0.18，滑块旋钮悬停放大；带悬停视觉的控件文件从 4 个增至 11 个。

**第十四批（`2289704`/`8671b44`）**：测试探针预置对方新增的 `Canvas.releaseTexture`（合并零适配，
合并演练已验证）；LazyRow 键盘横向滚动（Left/Right 48px、PageUp/Down 0.9 视口、Home/End）+
焦点滚入视野——应用的书架行/缩略图条正是 LazyRow。

**第十五批（`c62b524`）**：开放 `registerFocusStop`/`reregisterFocusStop`——应用层"自身即控件"
的自绘件（GhostIconButton 等）终于能自登记焦点停靠点；顺带修掉 `cui.cj` 里 FocusTarget
重复 import 三遍的警告。对应应用层补丁 [patches-app/0002](patches-app/README.md)。

**第十六批（`e5ee7f9`）**：公开 `drawFocusRing`——配套 `registerFocusStop` 的另一半：应用自绘件
不仅进得了 Tab 环，还能画出与框架完全一致的焦点环（外扩 2px / 1.6px accent）。对应应用补丁
[patches-app/0003](patches-app/README.md)（阅读器 dock 键盘翻页 + `Key.PageUp/PageDown` 去魔数）。

**第十八批（`ebf79bd`）**：框架级按键长按连发 `KeyRepeat`——OHOS 的 LWP 输入桥不带 repeat
标志，桥接后 KeyDown 的 repeat 恒 false。现在外壳在派发完事件后合成连发（400ms 延迟 +
60ms 间隔；后端自带 repeat 时顺延不双发），**无需改 L 层协议**。D2 从"未实现"变为"框架就绪、
真机复验节奏"。

**第十九批（`7e7de10`）**：#20 收尾——Stepper/Picker Home/End 跳两端、Table 聚焦后
Shift+方向键换排序列 / Enter 翻升降序；核对出 ComboBox 展开亮边**已有**、Drawer 焦点陷阱
**与设计相悖不应做**（详见 09 状态表）。

**第二十批（`c117d4b`）**：按词编辑（#18 收尾）——Ctrl+Left/Right 跳词边界（Shift 扩展选区）、
Ctrl+Backspace/Delete 删词；词边界与双击选词同一套脚本分类，汉字连续串整串算一词。

**验证（累计）**：桩库 `cjpm test` TOTAL 463，PASSED 422（累计新增 75 例 + 改写 1 例全过），
失败名册与 41 条基线完全一致——零回归；`tools/verify-cui-interactions.sh` 自动做这条判断。

> ⚠️ 仓库卫生：主仓 `lanlu` 有另一任务方的**暂存**改动（125 条）。在其上提交必须用
> `git commit --only -- <paths>`（或用 `git commit -- <paths>`），否则会把这批无关改动一并提交。
> 本批次曾误提交 156 个路径，已用 `git reset --soft HEAD~1` + `commit --only` 复原，对方暂存区未受影响。

**第十七批（工具化，无代码提交）**：合并演练固化成 `tools/rehearse-merge.sh`——一条命令复制主仓
工作树快照、应用 29 个补丁、跑桩库测试并与基线名册比对；实测「29 补丁零冲突 + 合并后
TOTAL 450 / PASSED 409 / 基线匹配」。同时发现并定位对方 lcodec 迁移缺失的宿主机
`link-option`（补 `-lSDL3 -lSDL3_ttf` 即通，vips 已不需要）。详见
[05-merge-rehearsal.md](05-merge-rehearsal.md)。

## 待办（下一批）

**框架侧已完成，应用层 3 个补丁已备好**（[patches-app/](patches-app/README.md)：表单回车+初始聚焦 /
ClickArea 与图标钮焦点化 / 阅读器 dock 键盘翻页），验收清单见
[04-pr-description.md](04-pr-description.md) §七。

1. 分支合并：主仓 `packages/cangjie-gui` 仍有他人未提交改动（11 文件，对方 lcodec 迁移进行中），
   合并前需协调；合并后补宿主机 `link-option`；真机验证需 OHOS 目标重编。
2. 合并后 `git apply` 三个应用层补丁；其余接线（`library_view` 封面卡、列表 hover、L 层 repeat）
   见 [03-app-wiring-plan.md](03-app-wiring-plan.md)。
