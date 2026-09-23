# client-next 详情页对齐 home-detail-redesign.html · 设计文档

日期：2026-07-19
状态：已获用户批准（含两处修正，见「用户修正」）

## 背景

client-next 的档案/合集详情页与仓库根 `home-detail-redesign.html` 设计稿存在系统性差距。
逐区对比（设计 HTML vs `client-next/src/ui/detail_view.cj` 数据装配、`widgets.cj` 骨架、
`titlebar.cj` 顶栏）确认：骨架、双列布局、卡片容器、进度卡、scrim 参数已基本对齐；
差距集中在 hero 区空间关系、返回按钮位置、徽标行内容、以及若干交互/字段细节。

本文档覆盖对比报告中全部 P0/P1/P2 项的修复设计。

## 原则

- **数据诚实**：无数据源的元素不 mock、不显示；有数据才渲染。
- **严格遵循设计稿**：视觉规格（尺寸、间距、颜色、层级）以 `home-detail-redesign.html` 为准。
- **顶栏方案（用户选定）**：保持不透明顶栏，backdrop 从顶栏下方开始，仅做几何对齐；
  不做「模糊图透进半透明顶栏」（renderer 无 backdrop-blur，全局浮动顶栏观感有折损）。

## 用户修正

- hero 徽标行的 NEW 红 pill **保留**（设计稿无此元素，但用户要求保留）。
- 基础信息卡的「更新时间」「状态」「文件类型」行**保留**，不做减法。

## P0 · 结构改动

### 1. 返回按钮进顶栏（`titlebar.cj`、`main.cj`）

- 设计稿：`#btn-back` 是顶栏最左、品牌区之前的 icon-btn，仅详情视图显示
  （`home-detail-redesign.html:387`，由 `setView` 控制显隐）。
- 实现：`model.page` 为 `Page.Detail(_)` / `Page.Tank(_)` 时，在品牌区左侧插入
  `GhostIconButton(GhostGlyph.Back, "titlebar:back")`，点击 → `Page.Library`。
  复用阅读器顶栏同款返回图标（`widgets.cj:230` GhostGlyph.Back 矢量绘制）。
- 删除三处旧返回钮：`widgets.cj` detailSkeleton 内 backdrop 顶部的「← 返回」胶囊；
  `detail_view.cj` 两个 loading 态（`detailView`/`tankView` 的 None 分支）的返回钮
  （顶栏在 loading 态同样显示返回钮，功能不丢失）。
- **拖动区同步**（关键）：`titleBarDragRects(windowWidth)` 增加 `hasBack: Bool` 参数。
  详情态返回钮占据左侧 ~44vp（34 钮宽 + 10 间距），品牌拖动矩形从 x=0 右移 44，
  弹性空隙起点 `DRAG_GAP_X` 同步 +44。`main.cj` 的 `syncTitleBarDragRegion` 按当前页
  是否有返回钮传参，并纳入变更检测（页型变化时重注册）。

### 2. backdrop 300 + hero 上叠 -128（`widgets.cj` detailSkeleton/detailHero）

- 设计稿几何：`.backdrop` 高 300；`.hero` `margin-top: -128px` 上叠；封面 200×300（2:3）
  横跨模糊带底边（上部 ~128 在模糊带上，下部落在页面底色）；`.hero-mid` `padding-top: 96px`
  使徽标行落在模糊带底缘上方 ~32px；操作卡 `align-self: end` 底对齐。
- 实现：
  - `DETAIL_BACKDROP_H` 460 → **300**；新增 `HERO_OVERLAP: Float32 = 128.0`。
  - detailSkeleton 重构：`ZStack(alignment: TopLeading)` =
    底层 backdrop 带（高 300，PixelImageView + 现有双层 scrim，参数不动）+
    上层 `VStack { 固定高 (300-128)=172 的占位； detailHero(...) }`。
    其后 detail-grid（双列卡片流）完全不变。
  - detailHero 内对齐：封面顶对齐 hero 顶（包顶对齐容器）；中列 `padding-top 96`、
    交叉轴顶对齐；操作卡保持底对齐（HStack crossAxis End 维持，封面列用
    `VStack { cover; Spacer() }` 顶齐）。
  - 中列间距节奏（设计：badge 下 10 / h1 下 8 / prog、summary、tag-row 各上 12）：
    VStack 统一 spacing 8 改为逐项 padding 实现非均匀节奏。

## P1 · 内容改动

### 3. 徽标行（`detail_view.cj` 装配、`widgets.cj` 渲染）

- 设计稿：金 pill「档案 · 图像」+ 蓝 pill「已完结」+ 灰 pill「2024」「同人志」。
- 实现（数据可得子集 + 用户修正）：
  - 金 pill「档案 · ${archivetype}」（现有）。
  - 灰 pill 年份：`release_at > 0` 时取 `formatTimestamp(release_at)` 前 4 位。
  - 灰 pill 分类：`tags` 中首个 `category:` 前缀标签，去前缀显示；无则不显示。
  - **NEW 红 pill 保留**（用户修正；设计稿无，位置保持在徽标行末）。
  - 蓝色「已完结」徽标：ArchiveMeta 无对应数据字段，**不做**（不 mock）。
- 合集详情徽标行不变（仅金「合集」）。

### 4. 标题响应式字号（`model.cj`、`main.cj`、`widgets.cj`）

- 设计稿：`h1` `clamp(24px, 3vw, 36px)` 粗体（renderer 无粗体字重，字重不做）。
- 实现：`AppModel` 新增 `windowWidth: State<Int64>`；`main.cj` `onTick` 中读取
  `window.width`，变化才写 State（避免空写触发重建）。detailHero 标题字号
  `min(36, max(24, windowWidth * 3 / 100))`，初始缺省 30。

### 5. MiniSeg 分段控件（`widgets.cj` 新增、`detail_view.cj` 换用）

- 设计稿 `.mini-seg`：elev 底 + 1px 描边 + 圆角 8 容器（padding 2，间距 2）；
  选中项 accentSoft 浅金底 + accent 字 + 圆角 6；未选中 muted 字透明底。
- 现状：框架 `SegmentedControl` 选中为实色 accent 底 + accentText 字（比设计稿重）。
- 实现：新增自绘 `MiniSeg(items, selected: Bindable<Int64>, key)` Widget，
  规格逐项对齐设计稿（参考 NavPill 的绘制模式）；替换详情页两处
  （pv-seg 缩略图/列表/树、mb-seg 网格/列表）。设置页的框架 SegmentedControl 不动。

### 6. 基础信息行（`detail_view.cj`、`dto.cj`、`dto_test.cj`）

- 设计稿行集：文件名/大小/页数（混合统计）/路径/来源/发布日期/添加时间/最近阅读。
- 实现（用户修正：保留现有额外行）：
  - 「发布时间」更名「**发布日期**」（对齐设计稿用词，值不变）。
  - 新增「**路径**」：服务端 metadata 已返回 `relative_path`
    （`metadata_patch_service.cj:782`；在线源档案为空串），DTO `ArchiveMeta` 补
    `relativePath` 字段与解码；空串隐藏该行。
  - 新增「**来源**」：复合 arcid（`source:<ns>:<id>`）解析出插件命名空间，显示
    「`<ns>` 插件」；本地档案（非复合 id）隐藏该行。
  - 保留「更新时间」「状态」「文件类型」行（用户修正）。
- 合集基础信息：补「**封面**」行（`coverAssetId > 0` → 「自定义」，否则「自动」），
  对齐设计稿 infoTank 行集。
- `dto_test.cj` 补 `relative_path` 解码用例。

### 7. 标签 chips（`widgets.cj` 新增 TagChip、`detail_view.cj` 接线）

- 设计稿 `.tag`：1px 描边 + 低透明底 + 圆角 999 pill，`cursor: pointer`，
  hover 字/边变 accent。
- 实现：新增自绘 `TagChip(text, onTap)` Widget（ClickArea + 自绘：
  常态 1px panelEdge 描边 + 主题低透明底 + muted 字；hover accent 40% 边 + accent 字）。
  - hero `tagFlow` 与侧栏 `tagGroups` 的 Label chips 全部换用 TagChip；
    折叠阈值维持 10 +「+N」（「+N」chip 不可点）。
  - 点击行为：`model.searchText.value = <原始 tag 串>` → `model.submitFilter()` →
    `model.page.value = Page.Library`。hero tagFlow 直接用原串；侧栏 tagGroups 在
    `groupTagsByNamespace` 分组时保留每个值对应的原始 tag 串（显示去前缀值、
    点击用原串），无前缀标签原样使用。

## P2 · 细节改动

### 8. 封面软投影（`widgets.cj` 新增 SoftShadowBox）

- 设计稿：`.cover-big` `box-shadow: 0 18px 48px rgba(0,0,0,.55)`（暗色）。
- renderer 无 blur 图元：用 5 层外扩圆角矩形递减 alpha 近似（每层外扩 ~4vp、
  alpha 几何衰减，暗色累计不透明度约 0.5；亮色累计约 0.12）。套在 hero 封面与
  玻璃操作卡底层。**快照目检把关**：效果不佳则放弃本项并在代码注释注明 renderer 限制。

### 9. 页面预览 hover 反馈（`widgets.cj` pvThumb/pvRow）

- 设计稿：`.pv-thumb:hover { outline: 1px solid var(--accent) }`；
  `.pv-row:hover { background: rgba(255,255,255,.04) }`。
- 实现：pvThumb 的 ClickArea 内 StaticBorder 改为自绘描边层（hoverId 命中时
  accent、常态 panelEdge）；pvRow 包 HoverSensor/自绘底，hover 铺 overlayHover
  圆角 8 底。

### 10. 规格微调（`widgets.cj`、`palette.cj`）

- 操作卡图标行间距 10 → 9（设计 `.action-card { gap: 9px }`）。
- 封面描边圆角 13.5 → 14（设计 `border-radius: 14px`）。
- 亮色页面底 `LANLU_L_BG` `#FAFAFC` → `#F4F4F6`（设计 `--bg`），
  检查亮色 scrim 硬编码色与新底色统一（当前 scrim 用 244,244,246 = #F4F4F6，
  改后天然一致）。
- 合集详情同骨架自动获益（backdrop/hero/MiniSeg/TagChip/投影）。

## 本轮不做（Out of Scope）

- 🎚 筛选按钮与筛选面板（顶栏 `.fp-*`）：首页功能，属首页重设计范畴。
- 导航胶囊「首页/书架/在线源」文案与「随机/来源」差异：实现有意置灰无页面项，保留。
- 页面预览真实缩略图：设计稿本身为占位色块，维持占位。
- 蓝色「已完结」徽标：无数据字段。
- 标题粗体：renderer 无字重支持。
- 半透明/浮动顶栏：用户已选定不做。

## 涉及文件

| 文件 | 改动 |
| --- | --- |
| `client-next/src/ui/titlebar.cj` | 返回钮插入、`titleBarDragRects` 加 hasBack 参数 |
| `client-next/src/main.cj` | 拖动区传参 + windowWidth onTick 更新 |
| `client-next/src/app/model.cj` | `windowWidth` State |
| `client-next/src/ui/widgets.cj` | 骨架重构、MiniSeg、TagChip、SoftShadowBox、hover、常量与间距 |
| `client-next/src/ui/detail_view.cj` | 徽标/info 行装配、loading 态删返回钮、TagChip 接线 |
| `client-next/src/net/dto.cj` | `ArchiveMeta.relativePath` 解码 |
| `client-next/src/net/dto_test.cj` | relative_path 解码用例 |

## 验证

1. `cd client-next && cjpm build` 通过。
2. `cjpm test` 全绿（含新增 dto 用例）。
3. 快照装置 `--seed-detail` / `--seed-tank` 出图，明暗两主题目检，重点：
   封面横跨模糊带、顶栏返回钮（详情页有/首页无）、徽标行构成、MiniSeg 浅金选中态、
   TagChip 描边、软投影观感、信息卡新行。
4. 对照 `home-detail-redesign.html` 逐项复核本清单 P0/P1/P2。

## 风险与注意

- 工作树有大量未提交改动（Task 11/13 进行中），实施全程基于当前工作树，
  不触碰无关文件；git 提交仅限本设计文档。
- 拖动区几何与返回钮宽度耦合：`titleBarDragRects` 调整后需窄窗（最小 960）
  复核空隙矩形仍为正且不覆盖控件。
- `windowWidth` State 写入必须变化才写，否则每 tick 触发全量重建（现有
  dirty-frame skipping 依赖空转不写 State）。
