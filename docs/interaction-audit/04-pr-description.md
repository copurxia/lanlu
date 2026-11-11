# PR：cui 基础交互补齐（`p0-focus-visible`，25 个提交）

> 分支：`p0-focus-visible`（工作树 `packages/cangjie-gui-p0`，基于主仓 `c39458f`）
> 规模：60 文件、+2818/−124；25 个提交（22 功能 + 3 文档）
> 动机：[本次交互审计](01-summary.md) —— 用户反馈「点击输入框没有描边」牵出的 20 类基础交互缺口。

## 一、为什么值得合并

1. **直接修复用户反馈**：点击输入框现在有 accent 激活边（此前只有键盘聚焦才画，点击后整框纹丝不动）——
   这也是应用层顶栏搜索框早就用 `hasFocus` 自绘出的效果，如今框架侧统一。
2. **键盘可用性从「大部分不可用」到「基本可用」**：Tab 能到达分页/面包屑/步骤条/标签云/自绘件，
   焦点出视口会自动滚入视野，Enter/Space 可激活，Esc/菜单键语义完整。
3. **零行为破坏**：所有新 API 都是可选参数或新类型；未使用新参数时行为与合并前逐字节一致，
   唯一有意的语义变化是 Modal 打开即聚焦 + 关闭恢复焦点（见 §四）。测试基线名册（41 条环境相关
   失败）在合并前后逐条一致。

## 二、提交分组（便于逐个 review）

**A. 焦点可见性（P0，用户反馈原案）**
- `9fe49b3` 字段族点击聚焦可见 + 键盘外环（`drawTextBoxChrome` 一处改动覆盖 TextField/TextArea/ComboBox）
- `cdd5924` Slider 焦点可见性 + Up/Down/Home/End（此前 Slider 连焦点绘制分支都没有）
- `8b1c3c6` 字段族悬停三态（`fieldSurface(active, hovered!)`）+ 禁用蒙版按控件圆角

**B. 键盘可达性（P0/P1）**
- `9fe49b3` 同时含 Pagination/Breadcrumb/StepIndicator 焦点登记 + Left/Right + Enter/Space
- `1db7709` WordCloud 键盘走词/激活 + 只读字段点击不再进焦
- `81fe548` RadioButton `groupRange(lower, upper)` 组内方向键（opt-in）
- `37573de` `Key` 枚举补 `PageUp/PageDown/Menu` + ScrollView 键盘滚动
- `54c5092` TextArea 聚焦时 PageUp/PageDown 翻页
- `3a143fd` ContextMenu 键盘唤起（Menu / Shift+F10）
- `808332e` MenuBar 的 Menu / F10 唤起

**C. 焦点流程（P1）**
- `3426fb5` Modal 打开即聚焦首个停靠点 + 关闭恢复焦点；Drawer 关闭恢复焦点
- `bd05059` **FocusTarget** —— 自绘内容（应用层 ClickArea/GhostIconButton 等 17 类）的可聚焦/可点击底座
- `d509011` 焦点矩形上报 + ScrollView reveal-on-focus
- `7b20493` LazyColumn reveal-on-focus

**D. 反馈与细节（P1）**
- `670d77f` Toast 可点击关闭、事件不穿透、悬停暂停计时
- `38299bd` Tooltip 键盘聚焦即显
- `16d164b` 列表/表格行悬停高亮
- `9fdc0b4` 中文/日文双击选词按 Unicode 脚本分组（全角标点不再粘进中文词）
- `8f44d11` 实心按钮（Primary/Danger）按下/悬停反馈
- `3dfae21` RichText 可点击链接片段（`RichSpan.link`）

**E. 文档**：`8bc83a7`、`e5b26b1`、`19daf09`、`d51919b`（architecture / components / api-reference / user-guide）

## 三、如何验证

```bash
# 一条命令：生成 vips/SDL 桩库 → 跑 cui 全量单测 → 与基线失败名册逐条 diff
tools/verify-cui-interactions.sh p0
# 期望：Summary: TOTAL 441 / PASSED 400 / ERROR 40 / FAILED 1，且「基线匹配」
```

- ERROR 40 + FAILED 1 是**环境限制**（headless 画布无渲染后端、`pushWakeEvent` 需真实 SDL wake 事件），
  名单固化在 [`test-baseline-names.txt`](test-baseline-names.txt)，脚本会对整份名单做 diff。
- 新增 54 个测试用例覆盖每条行为（焦点/键盘/悬停/Toast/Tooltip/选词/reveal/链接）。
- 真机（OHOS）需用 `sts-1.2.0-linux-x64-ohos` 工具链重编并复验焦点环与实际观感。
- **合并演练已完成且全绿**（见 [05-merge-rehearsal.md](05-merge-rehearsal.md)）：把主仓工作树（含对方
  未提交改动）复制成同级副本、对方改动先落成提交、应用 25 个补丁——**零冲突**；随后在副本里跑
  桩库测试得到 **TOTAL 444 / PASSED 403 / 失败名册与基线完全一致**（与分支单独跑完全相同）。
  合并时唯一需适配的 `Canvas.releaseTexture`（对方新增抽象方法）已在分支提交 `2289704` 提前预置，
  **落地后无需任何手工适配**。注意主仓仍在变动（对方 lcodec 迁移进行中），合并时机以其提交完成为准。
- **无法直接合并分支时**（主仓被他人未提交改动占用）：用 [patches/](patches/README.md) 里的
  25 个补丁在干净克隆上 `git am --3way patches/*.patch` 落地——已验证重建出的 tree 与分支
  tip 完全一致（`b902e1a3`），也支持只应用前 N 个（例如先要 P0）。

## 四、合并注意与风险

1. **主仓 `packages/cangjie-gui` 当前有他人未提交改动**（cjpm.toml、lgui/src/{canvas,renderer,texture,window,cursor}.cj、
   src/controls/modal.cj、src/desktop/desktop_app.cj）。其中 `modal.cj` 与本分支的 Modal 焦点改动**同文件**，
   合并前请先让那批改动落地或与其作者对一下；其余文件本分支未触碰。
2. **唯一有意的行为变化**：Modal 打开即聚焦首个停靠点、关闭恢复原焦点；`modalTabCyclesDialogFocusOnly`
   的断言已随之更新（打开即聚焦 m1，Tab 在环内移动）。
3. `fieldSurface` 由 `fieldSurface(active)` 变为 `fieldSurface(active, hovered!: Bool = false)`——
   参数带默认值，调用点无需改；本分支顺手把 13 处字段族调用点接上了 hover。
4. `Key` 枚举新增 `PageUp/PageDown/Menu` 三个成员：**对 `Key` 做穷举 match 的外部代码需要补分支**
   （本仓内已全部处理，应用层 `lgpu_backend` 的 keyFromCode 不需要改）。
5. 分支里没有改动 `cjpm.toml` 的 OHOS sysroot 配置——那部分属于对方未提交改动。

## 五、合并后待办（应用层，见 [03-app-wiring-plan.md](03-app-wiring-plan.md)）

- A 表单回车提交（`TextField(onSubmit:)` 已就绪，约 12 处）
- B 弹窗初始聚焦（`.autofocus()`，约 8 处）
- C 自绘点击件迁移到 `FocusTarget`（17 类，解掉「Tab 跳过主内容」）
- D 阅读器 dock 滑条换 `Slider`、列表行 hover、Radio 组用 `groupRange`
- E 长按连发：需 L 层 `LWindowEvent` 增加 repeat 字段（已在接线清单里记录）


## 六、调用点一致性核对（合并前已做，2026-11-11）

合并前对"新签名 / 新枚举 / 新语义"做了全仓核对，结论如下（附证据命令）：

| 项 | 核对结果 |
|---|---|
| `fieldSurface(active, hovered!)` 调用点 | 全仓 26 处：13 处字段族已接 `hovered`，其余 13 处是纯展示/容器（ProgressBar、ListView 外框、CanvasWidget、Tab 头、时间步进弹层等），悬停无语义，**故意不接**；参数带默认值，未改的调用点零影响 |
| `Key` 新增 `PageUp/PageDown/Menu` 的穷举 `match` | 框架内全部已处理；**应用层 client-next 没有对 `Key` 的穷举 match**（`grep "case Key\."` 只命中 reader/dto 里对 String key 的 match），合并后无需改应用代码 |
| `drawTextBoxChrome` 调用点 | 仅 3 处（TextArea 自身、TextArea 盒子、TextField），全部走新的激活/外环策略，无旁路 |
| 悬停视觉覆盖 | 带视觉悬停的控件文件从合并前 4 个增至 11 个（`grep -rl isHovered`）；其余 `claimHover` 只提供光标形状，属有意 |
| 剩余 `hasFocus(...)` 的绘制路径 | 全部是行为门控（导航、键盘激活、拖选），**没有**任何控件再用 `hasFocus` 画描边——焦点视觉统一走 `showFocusRing` |
| `Pagination/Table/TreeView/Accordion/Checkbox/RadioButton/TabView/Rating/Chip/SplitView/StepIndicator/ProgressRing/ReorderableList/WordCloud` | client-next 目前 **0 处使用**（审计时统计），这些控件的键盘化改动对应用零风险 |

命令（在工作树 `packages/cangjie-gui-p0` 下）：

```bash
grep -rn "fieldSurface(" src | wc -l          # 26
grep -rn "case Key\." ../../client-next/src   # 不命中 Key 枚举的穷举
grep -rl "isHovered(" src | grep -v _test     # 11 个文件有悬停视觉
grep -rn "hasFocus(" src | grep -v _test      # 均为行为门控，无绘制用途
```

## 七、回滚策略

改动集中在独立提交、互不依赖构建配置；如需回退某个方向，可单独 revert 对应分组（A/B/C/D 互不冲突）。
`FocusTarget`、`RichSpan.link`、`groupRange` 都是纯新增 API，revert 不会影响未使用它们的代码。
