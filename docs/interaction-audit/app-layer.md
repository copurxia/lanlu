# client-next 应用层交互审计（task-3 / audit-app-layer）

> 审计对象：`client-next/src/ui/*`（自研 GUI 框架 packages/cangjie-gui，包名 cui/lgui 之上的应用层）。
> 审计性质：只读，未改动任何源码。所有结论均给出 file:line 证据。
> 框架既定约定（引用，不重复调查）：`theme_state.cj:435 showFocusRing(id) = focusId==id && focusRingVisible`；`theme_state.cj:441 focus(id, viaKeyboard!: Bool=false)` 指针点击把 focusRingVisible 置假；`text/text_area.cj:400 drawTextBoxChrome → ctx.theme.fieldSurface(ctx.showFocusRing(id))`，`theme_state.cj:178 fieldSurface(active)` 的 accent 描边只由 active 决定 —— **"点击聚焦不画描边"是框架刻意模仿 web :focus-visible 的约定**，api-reference.md:127-129 有记载。

## 范围

client-next/src/ui/ 下 21 个非测试源文件（约 1.78 万行）：widgets.cj（3251 行自定义件库）、titlebar.cj、login_view.cj、metadata_edit_view.cj、detail_view.cj、settings_view.cj、settings_content_view.cj、settings_admin_view.cj、advanced_filter_dialog.cj、detail_dialogs.cj、add_to_tank_dialog.cj、upload_drawer.cj、search_autocomplete.cj、reader_view/reader_bar/reader_dock/reader_panels/reader_stage.cj、theme_ripple.cj、library_view.cj、shelf_view.cj、page_transition.cj、embedded_logo.cj、lgpu_backend.cj。
框架参照物：cui.core Button（basic_widgets.cj:489-628）、IconButton（icon_widgets.cj:90-240）、TextField（text/text_field.cj）、Modal（controls/modal.cj）、Drawer（controls/drawer.cj）。

## 结论速览

| 组件 | 缺失交互 | 等级 | 成本 | 证据 |
|---|---|---|---|---|
| 登录页 TextField（用户名/密码/TOTP） | 无 Enter 提交、无 autofocus、无「回车跳下一字段」；点击聚焦无 accent 描边（框架约定，见页首） | **高** | M | login_view.cj:254-275、285-294；grep 全应用 autofocus=0 命中 |
| 服务器编辑弹窗（login_view.cj） | Modal 打开不聚焦首个输入框；Enter 不能保存；Esc 能关（框架 Modal 提供）但表单无默认按钮 | **高** | M | login_view.cj:321-340；modal.cj:147-167（Esc/Tab 由框架给，首焦点需 autofocus） |
| 全部自定义点击件（ClickArea/GhostIconButton/NavItem/TagChip/MiniSeg/卡片/上传拖放区等 17 类） | 无 registerFocusable/focusableId（grep FF=0 全 0），全部不进 Tab 焦点环 → 键盘用户完全无法触达；无 Enter/Space 激活、无键盘焦点描边 | **高** | L | widgets.cj:131-175(ClickSensor)、168-175(ClickArea)、495-566(GhostIconButton)、833-907(NavItem)、2421-2489(TagChip)、upload_drawer.cj:380-476；对照 framework basic_widgets.cj:603-605(focusableId)、icon_widgets.cj:166-168 |
| 全部自定义点击件 | 无按下（press）视觉态：框架 Button 有 ctx.press/isPressed→accentSoft（basic_widgets.cj:575-587、615-616），应用层 17 类自绘件 grep `ctx.press(`=0 | **中** | M | widgets.cj:552-566 等各 handle 只有 MouseMove/MouseUp |
| 表单弹窗通用（metadata/detail_dialogs/add_to_tank/settings/cron/批量编辑） | 打开时均不聚焦首个输入框（grep autofocus=0）；Enter 均不能提交 | **中** | M | add_to_tank_dialog.cj:58-151；detail_dialogs.cj:120-196、239-362；metadata_edit_view.cj:10-15；settings_admin_view.cj:115-142、671-715 |
| 服务器卡片/条目行（login/dlg 列表行） | 列表行无方向键/Home/End 键盘导航（框架 Dropdown/ContextMenu 有先例 selection_widgets.cj:232-235） | **中** | M | login_view.cj:92-99(serverCard 循环)；detail_dialogs.cj:140-152(tankPickRow ClickArea) |
| 设置页 Switch/表单 | 已知待查项：Switch 由框架 common_controls.cj:41-146 提供 Enter/Space+焦点环，应用侧未登记 key，焦点顺序按构建序——影响可控 | 低 | S | settings_view.cj:603-684 |
| 搜索框（titlebar） | 点击聚焦无描边变化依赖 SearchChrome 的 hasFocus 兜底（有，见下）；但与登录框表现不一致（见不一致清单） | 低 | S | titlebar.cj:290-300、1261-1265 |
| reader_stage/reader_dock 自绘按钮 | 同全局：hover 有（reader_dock.cj:365+、reader_stage.cj:1409+），press/键盘/焦点无（reader_view.cj:26-55 只处理翻页键，按钮本体无 KeyDown 分支） | 中 | M | reader_dock.cj:365-543；reader_stage.cj:1409-1490 |
| 滚动区（LazyRow/LazyList/ScrollView 行） | 键盘方向键/Home/End 不滚动（框架 scrolling.cj、lazy_*.cj grep KeyDown=0，属框架层缺口，应用未补） | 中 | M | scrolling.cj（全文无 KeyDown）；widgets.cj:1787-1821(cardRow) |
| 右键菜单 | 仅合集成员行/成员卡有 ContextMenu（widgets.cj:3045、3138），首页卡/书架卡/页缩略图无 | 低 | S | widgets.cj:1495-1500(archiveCard 无 ContextMenu 包裹) |
| IME 候选窗锚点 | 框架有 textInputAnchor 机制（desktop_app.cj:501-514），应用层无阻碍，标记待真机验证 | 低 | S | desktop_app.cj:501-514 |

计数（可判定的缺失项，按最高等级归类）：**高 3 组、中 5 组、低 4 组**；逐控件明细共 22 条缺失判定（高 6 / 中 10 / 低 6），见下节。

## 逐控件明细

判定口径见 task-3 描述（17 项）；每控件列「已有 / 缺失」。除特别标注，证据均在 client-next/src/ui/ 下。

### 1. SearchChrome + SearchKeys（titlebar 顶栏搜索框）
- 已有：hover accent40% 描边 + Text 光标（titlebar.cj:320-327 claimHover(CursorShape.Text)、293-299 描边）；聚焦描边用 **ctx.hasFocus**（291），点击聚焦也变金 —— 与框架 :focus-visible 约定不同但可用；Enter 提交、Esc 失焦（462-471）；「/」快捷聚焦（472-483）；autocomplete 上下键/Enter/Esc（search_autocomplete.cj:162-175）；聚焦展开动画（385-415）。
- 缺失：Tab 到搜索框时描边依赖 SearchKeys 之外的全局 Tab 遍历 —— TextField 有 focusableId（框架 text_field.cj:251-253），可达但到达瞬间 SearchChrome 用 hasFocus 画描边所以可见 ✅；真正缺失是 **无禁用态**（不可禁用，属设计）与 **占位层在聚焦空态仍显示**（titlebar.cj:353-361 注释声称与浏览器一致，实为聚焦空态仍显示占位——待查：是否符合原型）。整体判定：**此控件是全应用交互最完整的自绘件**。

### 2. 登录页 passwordFormPanel / totpFormPanel（login_view.cj）
- 已有：框架 TextField 全套编辑（拖选/Ctrl+A/C/X/V/undo/redo，text_field.cj:231-238）；密码明暗切换（login_view.cj:268-270）；登录中 spinner 态（219-229）。
- 缺失：
  - Enter 不提交：passwordFormPanel 无任何 KeyDown 分支（grep login_view.cj KD=0），用户填完账号密码必须用鼠标点「登录」。用户可感知：输完密码回车无反应，是桌面表单最大违和感。**高**。
  - 无 autofocus：页面打开焦点不在用户名框（grep autofocus=0；框架 TextField.autofocus() 存在 text_field.cj:87-89 但从未调用）。用户可感知：打开登录页不能直接打字。**高**。
  - 密码框点击聚焦无 accent 描边（框架 fieldSurface 只在键盘焦点时描边，页首引用）。用户可感知：即用户反馈的"点击输入框没有描边"。**高**（框架级，应用可自绘 chrome 绕过，做法见 titlebar SearchChrome）。
  - TOTP 表单同上三条（login_view.cj:285-294）。

### 3. serverEditModal（login_view.cj:305-341）
- 已有：Esc/外点关闭、Tab 焦点陷阱（框架 modal.cj:152-157）；「测试连接」按钮（329）。
- 缺失：打开不聚焦 name 框（无 autofocus，325-327）；Enter 不保存（无 KeyDown 分支）；保存按钮非默认按钮。用户可感知：弹窗打开要先用鼠标点输入框；填完回车无反应。**高**。

### 4. serverCard / cardActions（login_view.cj:104-155）
- 已有：ClickArea 点击选中（115）；选中金色描边（110-114）；编辑/删除小图标（148-153）。
- 缺失：无 hover 视觉（grep login_view.cj HV=0，ClickSensor 不认领 hover）→ 鼠标划过卡片无反馈、光标不变成手型（CursorShape 无 claim）。用户可感知：不知道卡片可点。**中**。
- 缺失：键盘完全不可达（无 focusableId）。**高**（并入全局项）。

### 5. ClickArea / ClickSensor（widgets.cj:131-175）
- 已有：左键 MouseUp 命中触发（151-161）。
- 缺失：**hover 认领**（ClickSensor 不 claimHover，widgets.cj:151-161 只有 MouseUp 分支）——用它叠层的按钮（登录页 7 处、dlg 列表行等）全都没有 hover 反馈和手型光标，除非调用方自己另叠 HoverSensor（仅 widgets.cj:2814、2969 pvThumb/pvRow 这么做了）。用户可感知：可点的行/按钮划过无底色、箭头光标不变手型。**中**。
- 缺失：focusableId/键盘激活/press 态（grep widgets.cj FF=0、KD=0、PR=0）。**高**。

### 6. GhostIconButton / DangerIconButton / ThemeToggleButton（widgets.cj:495-643；detail_view.cj:29-80）
- 已有：hover overlayHover 底 + 图标转 text 色（widgets.cj:526-548）；claimHover(Interactive) 手型光标（552-557）；active 常驻 accentSoft（533-534）；danger 红色 hover（detail_view.cj:59-61）。
- 缺失：无 focusableId → 详情操作卡 6 个图标钮 Tab 不可达（对照框架 IconButton focusableId icon_widgets.cj:166-168）。用户可感知：键盘用户进详情页后无法用键盘执行下载/收藏/删除。**高**。
- 缺失：无 Enter/Space 激活、无键盘焦点描边、无按下态。**中**（按下态：框架按钮有 isPressed→accentSoft，basic_widgets.cj:615-616，自绘件无）。

### 7. NavItem（widgets.cj:833-907，侧栏条目）
- 已有：hover overlayHover 底 + Interactive 光标（892-897）；active accentSoft+金字（862-867）。
- 缺失：键盘不可达/无激活键。**高**（并入全局）。
- 缺失：侧栏无上下方向键导航（列表语义）。**中**。

### 8. MiniSeg（widgets.cj:648-726，详情页迷你分段）
- 已有：hover 未选项转主文字色 + 光标（699-704、711-715）；点击切 selected（716-721）。
- 缺失：无 focusableId、无方向键在段间移动、无 Enter/Space。用户可感知：键盘用户无法切换缩略图/列表视图。**中**。

### 9. TagChip / tagFlow / tagGroups（widgets.cj:2421-2489、2492-2577）
- 已有：hover 金描边+金字+光标（2455-2463、2476-2479）；点击携 tag 跳搜索（2480-2484）；interactive:false 的 "+N" 不响应（2472-2473）。
- 缺失：键盘不可达。**高**（并入全局）。
- 缺失：右键无菜单（该控件不需要，不算缺失）。

### 10. 封面卡片族 homeCoverCard / archiveCard / tankCard / cardRow（widgets.cj:1474-1821）
- 已有：HoverLift 弹簧放大 5%+CoverBorder 金描边（1583-1591、1158-1205、732-764）；Interactive 光标（1195-1204）；悬浮操作层三钮（CardHoverActions 1300-1403，按钮自带 hover 白底渐显 1351-1356）；多选模式选中描边+勾点（1592-1594、768-832）；入场动画（1023-1156）。
- 缺失：键盘完全不可达（卡片无 focusableId，卡片是首页主内容，键盘用户无法打开任何档案详情）。用户可感知：Tab 遍历跳过全部卡片直达页脚。**高**。
- 缺失：卡片本体的 hover 浮层三钮仅鼠标可用（CardHoverActions 只处理 MouseMove/MouseUp 1375-1402）。**高**（并入上条）。
- 缺失：右键菜单未覆盖首页/书架卡（ContextMenu 仅在合集成员 3045、3138）。用户可感知：同一张卡在首页没有右键"打开详情"，在合集详情页有——不一致。**低**。

### 11. 成员卡/成员行 memberCard / memberListContent / MemberRowSelectEntry（widgets.cj:3042-3065、3118-3243）
- 已有：ContextMenu 右键菜单（3045-3057、3138-3150）；行首勾选圈 hover 变实底（3217-3233）；整行点击（3152-3157）。
- 缺失：键盘不可达；列表无方向键导航。**中**。

### 12. MetadataAssetsChrome（metadata_edit_view.cj:225-339，封面/横幅/clearlogo 悬浮操作层）
- 已有：三个热区 hover 浮现操作钮（255-258、261-267 claimHover）；点击触发 todoToast（268-278）。
- 缺失：键盘不可达、无 press 态；操作是 todoToast 占位（274）。用户可感知：元数据编辑器的图片上传/替换无法用键盘完成。**中**。

### 13. 表单弹窗组：addToTankDialog（add_to_tank_dialog.cj:41-152）、detail_dialogs 的两个（107-196、224-363）、批量编辑（detail_view.cj:797-828）、cron 编辑器（settings_admin_view.cj:671-715）、重置密码（115-142）、token 创建（1018-1024）
- 已有：Esc/外点关、Tab 循环（框架 Modal 提供）；tankPickRow/pick 行 hover 由 ClickArea 光标承担（add_to_tank_dialog.cj:162-172 注释承认 hover 只表达为光标）。
- 缺失（全部一致）：打开不聚焦过滤框/命名框（grep autofocus=0）。用户可感知：「加入合集」弹窗打开后想直接敲过滤词，需要先点一下输入框。**中**。
- 缺失：过滤框/新建名框 Enter 不触发创建/搜索（无 KeyDown 分支）。用户可感知：新建合集命名完回车无反应，必须点「创建并加入」。**中**。
- 缺失：列表行（tankPickRow、搜索结果行、批量勾选行）无方向键+Enter 选择。**中**。

### 14. advancedFilterDialog（advanced_filter_dialog.cj:14-78）
- 已有：全部用框架 Dropdown/Switch/TextField/Button（29-65），Esc/Tab 由 Modal 兜底。
- 缺失：打开不聚焦；「筛选」非默认提交键。**低**（框架控件自身交互完整）。

### 15. upload_drawer（upload_drawer.cj）
- 已有：Drawer Esc/外点关（框架 drawer.cj:152-165）；ArchiveDropZone hover accent 虚线框+光标（400-461）；DropFile 拖放（467-471）；TextArea 下载链接批量输入（60-62）。
- 缺失：抽屉打开不聚焦 TextArea；「添加下载任务」不能 Enter 提交。用户可感知：粘贴完链接要鼠标点按钮。**中**。
- 缺失：DropZone 键盘不可达（无 focusableId，键盘用户无法触发文件选择对话框）。**中**。

### 16. settings_view / settings_content_view / settings_admin_view
- 已有：几乎全部用框架控件（Dropdown/SegmentedControl/Switch/Button/TextField/TextArea/Modal），hover/press/焦点环/Esc/Tab 均由框架承担（basic_widgets.cj:560-601、common_controls.cj:69-94）；确认弹窗统一 confirmModal（settings_view.cj:797-806）。
- 缺失：API Token 命名框（settings_view.cj:1018）与 cron 参数等弹窗输入不聚焦、不 Enter 提交。**低**。
- 缺失：分类/标签/任务表用 IconButton 上下移（settings_content_view.cj:304-307）无键盘替代。**低**。

### 17. reader 族（reader_view/bar/dock/panels/stage）
- 已有：全局翻页键 Left/Right/Up/Down/Space/N/K/Esc（reader_view.cj:26-55）；顶栏 GhostIconButton hover（reader_bar.cj:265-281）；dock 各钮 hover（reader_dock.cj:365-543）；音量条拖拽（928-963）；Book 页码滑条几何换算（1227-1229）；双击缩放 clickCount（reader_stage.cj:1767-1771）；Esc 关 dock/面板（reader_dock.cj:771、958）；ReaderSwitch/ReaderModeSeg hover（reader_panels.cj:84-222）。
- 缺失：dock/stage 的自绘按钮（上一页/下一页/播放/静音/字幕/返回）全部无键盘激活与焦点（它们不注册 focusable；reader_view 的全局键盘分支也不覆盖它们）。用户可感知：纯键盘只能翻页，不能静音/暂停/回详情。**中**。
- 缺失：音量/页码滑条无方向键步进（对比框架 Slider 有 Left/Right value_widgets.cj:173-178——dock 是自绘滑条没继承）。**中**。

### 18. theme_ripple（theme_ripple.cj）
- 已有：纯视觉遮罩不消费任何事件（153-156），设计正确。
- 缺失：无（不计缺失）。

### 19. 框架已给、应用白拿的（列出不误报为缺失）
- Button/IconButton：hover/press/焦点环/Enter/Space/Tab（basic_widgets.cj:560-601）——登录「登录」按钮、设置页全部按钮已覆盖。
- Modal：Esc、外点、Tab 焦点陷阱（modal.cj:152-167）；Drawer：Esc、scrim（drawer.cj:152-191）。
- TextField/TextArea：选区、Ctrl+A/C/X/V/Z/Y、Home/End、IME（text_field.cj:231-245）。
- ScrollView/滚动条：滚轮 + 滑块拖拽（scrolling.cj:200-270）。
- Autocomplete 弹层：上下键/Enter/Esc（search_autocomplete.cj:162-175）。

## (a) "同一交互不同表现"不一致清单

1. **输入框聚焦描边**：titlebar 搜索框点击即变金（titlebar.cj:293 用 `ctx.hasFocus`）↔ 登录页/服务器弹窗/元数据/设置等全部框架 TextField 点击不变金（text_area.cj:400-402 用 `showFocusRing`，键盘才描边）。用户反馈即源于此。**建议统一为「聚焦即描边」或全站维持 :focus-visible 并给搜索框降级**——改 framework fieldSurface 调用点或应用给每个表单叠自绘 chrome（同 SearchChrome 做法）。
2. **hover 光标**：GhostIconButton/TagChip/NavItem/搜索框认领 Interactive/Text 光标（widgets.cj:556、2478、896；titlebar.cj:324）↔ ClickArea 一族（登录服务器卡、弹窗列表行、memberSelectCard、下载区部分按钮）不认领 → 箭头光标。同为"可点击"语义，光标形状不一致。
3. **hover 底色**：同样的列表行，合集成员行有 HoverFill（widgets.cj:2970）而登录服务器卡/合集选择行（add_to_tank_dialog.cj:164-172）无任何 hover 底。
4. **右键菜单**：合集成员行/卡有 ContextMenu（widgets.cj:3045、3138）↔ 首页卡/书架卡/详情页缩略图没有。同一张"档案卡"能力不同。
5. **Enter 语义**：搜索框 Enter=提交（titlebar.cj:462-466）↔ 其它全部表单 Enter 无效。autocomplete 弹层内 Enter=选词（search_autocomplete.cj:164-170）。
6. **Esc 语义**：Modal/Drawer/autocomplete/用户菜单/dock 弹层都能 Esc 关（modal.cj:152、drawer.cj:152、search_autocomplete.cj:171、titlebar.cj:1022、reader_dock.cj:771）↔ 详情页 DetailMoreButton 菜单也支持（detail_view.cj:210）——**此项一致**；但登录页 TOTP 表单的「返回密码登录」是 ClickArea（login_view.cj:295-300），无 Esc 快捷。轻微不一致。
7. **多选入口**：首页卡 hover 浮层"多选"（CardHoverActions selectRect widgets.cj:1339-1341）↔ 合集成员行行首勾选圈（3198-3243）↔ memberSelectCard 点击整卡（3083）。三种入口形态，均仅鼠标可用。
8. **禁用态**：框架 Button/.enabled() 有标准禁用（widget.cj:196-207 + IconButton focus 注销），batchActionBar「加入合集」用了（widgets.cj:1870）↔ NavPill 第三项"在线源"直接画灰字但仍可 hover 到（titlebar.cj:568-572、584-587 不响应点击但光标仍是手型——hmm 实际上 claimHover 在 0/1 项才认领，585 只判 itemRect(0)/(1)，第三项不给光标，判定：一致）→ 待查：NavPill 禁用项 hover 手型是否存在（代码显示不存在，585 行只包含前两项）。

## (b) Enter 提交 / Esc 取消 / 初始聚焦 矩阵

| 表单/弹窗 | Enter 提交 | Esc 关闭 | 打开聚焦首输入框 |
|---|---|---|---|
| 顶栏搜索 | ✅ titlebar.cj:462-466 | ✅ 467-471 | ✅ "/" 键快捷 472-483（等价能力） |
| 登录（账号/密码） | ❌（login_view.cj:254-275 无 KeyDown） | —（页面） | ❌（grep autofocus=0） |
| 登录 TOTP | ❌（285-294） | — | ❌ |
| 服务器编辑弹窗 | ❌（321-340） | ✅（框架 Modal modal.cj:152） | ❌ |
| 元数据编辑器 | ❌（metadata_edit_view.cj:10-15） | ✅ | ❌ |
| 加入合集（批量/单卡） | ❌（add_to_tank_dialog.cj:122-143；detail_dialogs.cj:177-196） | ✅ | ❌ |
| 合集添加档案搜索 | ❌（detail_dialogs.cj:263-267） | ✅ | ❌ |
| 批量编辑标签 | ❌（detail_view.cj:797-828） | ✅ | ❌ |
| cron 编辑器 | ❌（settings_admin_view.cj:671-715） | ✅ | ❌ |
| 重置密码 / 新建 Token | ❌（settings_admin_view.cj:115-142、1018-1024） | ✅ | ❌ |
| 上传抽屉下载链接 | ❌（upload_drawer.cj:60-62） | ✅（drawer.cj:152） | ❌ |
| 高级筛选 | ❌（advanced_filter_dialog.cj:14-78） | ✅ | ❌ |
| autocomplete | ✅ 选词（search_autocomplete.cj:164-170） | ✅ 171-175 | —（随搜索框） |

**结论：除顶栏搜索外，全应用没有任何表单支持 Enter 提交，没有任何弹窗做初始聚焦。**

## (c)(d) 自定义绘制件四态（hover/press/focus/键盘）总判定

| 自绘件 | hover | press | focus 描边 | 键盘激活 | 证据 |
|---|---|---|---|---|---|
| SearchChrome | ✅ | — | ✅(hasFocus 点击也亮) | —（TextField 承担） | titlebar.cj:290-330 |
| ClickArea/Sensor | ❌(不认领) | ❌ | ❌ | ❌ | widgets.cj:131-175 |
| HoverSensor | ✅(仅认领) | ❌ | ❌ | ❌ | widgets.cj:180-209 |
| GhostIconButton | ✅ | ❌ | ❌ | ❌ | widgets.cj:495-566 |
| DangerIconButton | ✅ | ❌ | ❌ | ❌ | detail_view.cj:29-80 |
| ThemeToggleButton | ✅ | ❌ | ❌ | ❌ | widgets.cj:571-643 |
| MiniSeg | ✅(字色) | ❌ | ❌ | ❌方向键也无 | widgets.cj:648-726 |
| NavItem | ✅ | ❌ | ❌ | ❌ | widgets.cj:833-907 |
| TagChip | ✅ | ❌ | ❌ | ❌ | widgets.cj:2421-2489 |
| 封面卡 homeCoverCard | ✅(弹簧+描边) | ❌ | ❌ | ❌ | widgets.cj:1523-1770 |
| CardHoverActions 钮 | ✅(白底) | ❌ | ❌ | ❌ | widgets.cj:1300-1403 |
| HoverBorder/HoverFill | ✅(纯显示) | ❌ | ❌ | ❌ | widgets.cj:1996-2058 |
| MemberRowSelectEntry | ✅ | ❌ | ❌ | ❌ | widgets.cj:3198-3243 |
| MetadataAssetsChrome | ✅ | ❌ | ❌ | ❌ | metadata_edit_view.cj:225-339 |
| ArchiveDropZone | ✅ | ❌ | ❌ | ❌ | upload_drawer.cj:380-476 |
| NavPill | ✅ | ❌ | ❌ | ❌ | titlebar.cj:494-601 |
| UserMenuChip | ✅ | ❌ | ❌ | ✅菜单内 Enter/方向键 | titlebar.cj:617+、1000-1062 |
| DetailMoreButton+菜单 | ✅ | ❌ | ❌ | ✅菜单内 Esc/Enter/↑↓ | detail_view.cj:102-254 |
| ReaderDock/Stage 钮 | ✅ | ❌ | ❌ | ❌ | reader_dock.cj:365-543、reader_stage.cj:1409-1490 |
| DetailMenu 弹层 | ✅ | ❌ | — | ✅ | detail_view.cj:166-254 |

（"—"= 该层不承担此语义，由叠层内框架控件承担。）

## 最该先补的 5 项

1. **表单 Enter 提交 + 弹窗初始聚焦（全套表单）**——为什么：桌面表单第一违和感，涉及登录（转化关键路径）、加入合集、cron/重置密码全部弹窗。影响界面：login_view.cj、add_to_tank_dialog.cj、detail_dialogs.cj、metadata_edit_view.cj、settings_admin_view.cj、upload_drawer.cj。改法：给框架 TextField 加 `onSubmit` 回调（text/text_field.cj handle 的 KeyDown 分支 text_field.cj:231-238 处加 Enter 分支；框架层改动 S）；应用侧在各 Modal body 末尾对首个 TextField 调 `autofocus()`（框架能力已存在 text_field.cj:87-89、242-245，零成本）。若不允许改框架，则在每个 Modal 里加 EventHandler（core/event_handler.cj:5-46 cui 已导出）拦截 Enter/Esc，成本 M。
2. **自绘点击件接入焦点环 + Enter/Space 激活**——为什么：键盘用户目前无法触达首页卡片、详情操作卡、侧栏、Tag、上传区（Tab 直接跳过全部主内容）。影响界面：首页/书架/详情/阅读器全部。改法：抽一个共用的 `InteractiveWidget` 基类（或给 ClickSensor/GhostIconButton/NavItem/TagChip 加三件事：构造期 registerFocusable——protected 于 cui.core/ui_build.cj:195-207 未导出，需框架导出或应用层在构造期经 Widget.focusableId() 重载 + 框架 adopt 链路；draw 末尾 `if (ctx.showFocusRing(id)) strokeRoundedRect(frame+2)`（参照 basic_widgets.cj:567-569）；handle 加 Enter/Space 分支）。框架需导出 registerFocusable/drawFocusRing（surface_draw.cj:52-54），成本 L，收益全局。
3. **登录页 TextField 点击聚焦描边（用户反馈原案）**——为什么：这是用户报告的直接症状，且登录是首屏。影响界面：登录页全部 6 个输入框、以及所有框架 chrome TextField。改法（应用侧不动框架）：仿 titlebar SearchChrome（titlebar.cj:290-300）给 passwordFormPanel/totpFormPanel/serverEditModal 的 TextField 叠一层 ZStack 底件，draw 时 `if (ctx.hasFocus(fieldId)) strokeRoundedRect(accent)`；或在框架把 drawTextBoxChrome（text_area.cj:400-402）的实参从 `showFocusRing` 换成 `hasFocus`（一行，但改变全站约定，需产品确认）。成本 S～M。
4. **ClickArea 补 hover 光标/底色**——为什么：登录服务器卡、弹窗列表行、下载任务行等大量可点区域既无手型光标也无 hover 底（用户不知道能点）。影响界面：login_view.cj:115/148-153、add_to_tank_dialog.cj:164-172、detail_dialogs.cj:143/295、widgets.cj:3083。改法：给 ClickSensor.handle 的 MouseMove 分支加 `ctx.claimHover(hoverId, CursorShape.Interactive)`（widgets.cj:151-161，3 行，成本 S）；需要视觉反馈的调用点配对叠 HoverFill/HoverBorder（现成件 widgets.cj:1996-2058）。
5. **reading 之外的自绘滑条/列表键盘化（阅读器 dock + 设置表格）**——为什么：阅读器是长时驻留界面，音量/页码滑条和 dock 钮完全键盘不可达；设置管理表格的上下移仅鼠标。影响界面：reader_dock.cj:919-991（音量/页码滑条）、settings_content_view.cj:304-307。改法：dock 滑条 handle 加 Left/Right 分支（参照框架 Slider value_widgets.cj:173-178，每处 ~10 行，成本 M）；列表上下移可先给 IconButton 链接快捷键（EventHandler 全局分支），成本 S。

## 待查（证据不足，未计入缺失）

- NavPill"在线源"禁用项 hover 是否显示手型（代码上不认领，titlebar.cj:584-587，但未实测）。
- IME 候选窗在 lgpu/OHOS 后端的锚点表现（lgpu_backend.cj:293-300 有消费 lastTextInputRect 的逻辑，真机行为未验证）。
- 设置页 Switch 在 Modal 内的 Tab 顺序是否与视觉顺序一致（框架按构建序登记，state.cj:349-355，未实测）。
- 表格/树（settings 表格为 IconButton 行而非框架 Table）键盘导航的完整缺口边界。
