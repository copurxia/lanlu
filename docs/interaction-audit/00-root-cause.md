# 点击输入框没有描边：根因与交互缺口总览

> 调查基线：仓库 /workspace/lanlu/lanlu，框架 packages/cangjie-gui（lgui/cui）自身是独立 git 仓库，
> 应用 client-next。本机无 cjc/cjpm，所有结论均为源码静态取证（未编译、未真机复跑）。

## 一、结论：不是 bug，是框架刻意实现 `:focus-visible`

点击输入框（TextField / TextArea / Dropdown / Table / TreeView / Picker 等“字段族”）
**确实拿到了焦点**（有光标闪烁、能输入、能 Tab 走），但描边不画，因为框架把
「焦点是否可见」拆成了两个概念：

| 位置 | 代码 | 行为 |
|---|---|---|
| `core/theme_state.cj:435` | `showFocusRing(id) = focusId == id && focusRingVisible` | 只有“键盘到达的焦点”才画描边 |
| `core/theme_state.cj:441` | `focus(id, viaKeyboard!: Bool = false)` → `focusRingVisible = viaKeyboard` | 指针按下调用 `focus(id)` 时把标志置假 |
| `core/theme_state.cj:405-424` | `moveFocus`（Tab/Shift+Tab） | 置真 |
| `text/text_field.cj:275` | 点击命中 `ctx.focus(id)`（无 `viaKeyboard`） | 点击 → 标志假 |
| `text/text_area.cj:400-402` | `drawTextBoxChrome` → `ctx.theme.fieldSurface(ctx.showFocusRing(id))` | 只有标志真时才换成 accent 边 |
| `core/theme_state.cj:178-199` | `fieldSurface(active)` | active 才用 `fieldActive` 底色 + `accent` 边 + accent 光晕；否则 `field` + `panelEdge`，且**没有 hover 分支** |
| `desktop/desktop_app.cj:405-416` | MouseDown → `beginPointerPress` → 分发 → `settleFocusAfterPress` | 点击聚焦链路本身是通的 |

设计意图写在框架文档里，`docs/architecture.md:93-98`：

> **键盘专属焦点环（`:focus-visible`）**：焦点圈是给键盘用户的导航线索，鼠标用户点哪儿一目了然、
> 不需要它。…控件绘制描边时用 `showFocusRing(id)`…**故点击聚焦不留描边、`Tab` 到达才显**。

`docs/api-reference.md:127-129` 同样记载。所以这是**照 web `:focus-visible` 约定做的设计取舍**，
不是渲染丢失、不是事件没到、不是主题色缺失。

### 为什么用户仍然会觉得“缺”

1. **同一个应用里两种视觉语言**：应用层自己画的顶栏搜索框 `client-next/src/ui/titlebar.cj:291`
   用的是 `ctx.hasFocus(SEARCH_FIELD_ID)`，点击也会把描边换成 accent 40%（:293-300）。
   于是「点搜索框有边、点登录框/元数据框没有边」，看起来像后者坏了。
2. **点击后唯一的反馈是光标闪烁**：字段常态描边是 `panelEdge`（很淡），点击后连 hover 反馈都没有
   （`fieldSurface` 没有 hover 参数），激活感几乎为零；而按钮族点击有配色变化 + 键盘外环。
3. 桌面软件的普遍约定（Windows/macOS/ArkUI 原生 TextField、Qt、GTK）是**点击聚焦也显示 accent 边**，
   只有“外扩 ring”留给键盘；框架把“边”和“环”绑在同一标志上，取舍比 web 更激进。

### 建议改法（三选一，成本递增）

```cangjie
// 方案 A（推荐，1 处改动）：点击聚焦也给“边”，键盘再加“环”，与按钮族视觉语言对齐
// packages/cangjie-gui/src/text/text_area.cj:400
internal func drawTextBoxChrome(ctx: UiContext, frame: Rect, id: String): Unit {
    drawSurface(ctx, frame, ctx.theme.fieldSurface(ctx.hasFocus(id)))   // 点击 → accent 1px 边
    if (ctx.showFocusRing(id)) {
        drawFocusRing(ctx, frame, ctx.theme.controlRadius)              // Tab → 再叠 1.6px 外环
    }
}
// fieldSurface(active) 已是现成的“激活”样式（fieldActive 底 + accent 边 + 光晕），无需改主题。
// 这一步会让「点击有边」，同时保留「键盘才有的外环」这一层区分，且与 client-next 搜索框一致。

// 方案 B（最小）：只把 fieldSurface 的入参从 showFocusRing 换成 hasFocus。
// 一行改动，但键盘/鼠标焦点视觉不再有区别（只剩按钮族有外环）。

// 方案 C（最完整）：Theme.fieldSurface(active, hover) 增加 hover 分支，
// 常态 panelEdge → hover accent 40%（对齐 titlebar.cj:293 的搜索框），点击/键盘 accent 100%，
// 键盘再叠 drawFocusRing。需要同步改 12 处 fieldSurface 调用点与主题文档。
```

注意：`drawFocusRing` 是 `core/surface_draw.cj:52` 的 1.6px accent 外环（外扩 2px），
与 `fieldSurface` 的 1px 内边不冲突，两者叠用即「按下的边 + 键盘的环」。

## 二、基础交互缺口总览

（由三路并行审计汇总：framework-controls.md / framework-text-overlays.md / app-layer.md）
