package lanlu_client_next.app

import cui.Color

// lanlu 三层语义调色板常量：设计事实来源是仓库根目录的高保真原型
// reader-redesign.html / home-detail-redesign.html（金色系，--accent:#e8b04b 暗 /
// #c78a1e 亮，accent-soft 为金的低透明度铺底），取代早期 frontend globals.css 蓝色系。
// 三层 = 基础层（bg/panel/text 等）+ 叠层（overlay*：阅读器/详情页毛玻璃浮层）
// + 恒深舞台（stageBg/onMedia*：媒体舞台两主题恒深）。
// 调色板的单一来源：根包 theme.cj 的 lanluThemeDark()/lanluThemeLight() 由它们组装；
// 视图构建期拿不到 ctx.theme（那是绘制期上下文），需要铺底/描边颜色时直接用这些常量。
// 放在 app 包而非根包：根包 main.cj 依赖 ui，ui 反向依赖根包会成环。

// ── 暗色（默认）──
public let LANLU_BG = Color.rgb(0x0B, 0x0B, 0x0D)            // 页面底
public let LANLU_PANEL = Color.rgb(0x16, 0x16, 0x1A)         // 卡片/面板
public let LANLU_PANEL_RAISED = Color.rgb(0x1E, 0x1E, 0x23)  // 抬升面/hover
public let LANLU_PANEL_EDGE = Color.rgba(255, 255, 255, 20)  // 边框
public let LANLU_TEXT = Color.rgb(0xE8, 0xE8, 0xEA)          // 主文字
public let LANLU_MUTED = Color.rgb(0x9A, 0x9A, 0xA2)         // 次文字
public let LANLU_ACCENT = Color.rgb(0xE8, 0xB0, 0x4B)        // 主色（金）
public let LANLU_ACCENT_TEXT = Color.rgb(0x1A, 0x12, 0x06)   // 主色上的文字
public let LANLU_ACCENT_SOFT = Color.rgb(0x3A, 0x2F, 0x18)   // 选中底：金 16% 底的近似实色
public let LANLU_DANGER = Color.rgb(0xE0, 0x5D, 0x5D)        // 危险
public let LANLU_SUCCESS = Color.rgb(0x4C, 0xAF, 0x7D)       // 成功/已存会话绿点（明暗共用）
public let LANLU_NEW_RED = Color.rgb(0xE0, 0x5D, 0x5D)       // NEW 徽标红
public let LANLU_FIELD = Color.rgb(0x13, 0x13, 0x16)         // 输入框底
public let LANLU_WIN_CLOSE_HOVER = Color.rgb(0xE8, 0x11, 0x23) // 窗口关闭键 hover（标题栏用）

// 暗色叠层/舞台/恒深 token（Task 1 表 dark 列）
public let LANLU_OVERLAY_SURFACE = Color.rgba(18, 18, 22, 199)
public let LANLU_OVERLAY_BORDER = Color.rgba(255, 255, 255, 36)
public let LANLU_OVERLAY_HOVER = Color.rgba(255, 255, 255, 31)
public let LANLU_OVERLAY_TRACK = Color.rgba(255, 255, 255, 56)
public let LANLU_ON_OVERLAY = Color.rgb(0xF2, 0xF2, 0xF4)
public let LANLU_ON_OVERLAY_DIM = Color.rgba(242, 242, 244, 158)
public let LANLU_STAGE_BG = Color.rgb(0, 0, 0)
public let LANLU_ON_MEDIA = Color.rgb(0xF2, 0xF2, 0xF4)
public let LANLU_ON_MEDIA_DIM = Color.rgba(242, 242, 244, 158)

// 合集卡叠层面板色（原型 home-detail-redesign.html .card.tank .stack::before/::after
// 渐变近色，明暗两组；盖在封面底下的两张错位垫底面板用，非 ctx.theme token 故单列）。
public let LANLU_TANK_STACK_HI = Color.rgb(0x22, 0x30, 0x4A)
public let LANLU_TANK_STACK_LO = Color.rgb(0x10, 0x15, 0x1F)

// ── 亮色 ──
// 页面底比原型的 #F4F4F6 提亮一档，减少大面积灰感，同时与纯白卡片保留轻微层次。
public let LANLU_L_BG = Color.rgb(0xF8, 0xF8, 0xFA)
public let LANLU_L_PANEL = Color.rgb(0xFF, 0xFF, 0xFF)
public let LANLU_L_PANEL_RAISED = Color.rgb(0xF0, 0xF0, 0xF3)
public let LANLU_L_PANEL_EDGE = Color.rgba(0, 0, 0, 26)
public let LANLU_L_TEXT = Color.rgb(0x1D, 0x1D, 0x21)
public let LANLU_L_MUTED = Color.rgb(0x6D, 0x6D, 0x76)
public let LANLU_L_ACCENT = Color.rgb(0xC7, 0x8A, 0x1E)      // 主色（亮底上的深金）
public let LANLU_L_ACCENT_TEXT = Color.rgb(0xFF, 0xFF, 0xFF)
public let LANLU_L_ACCENT_SOFT = Color.rgb(0xF3, 0xE6, 0xC8)
public let LANLU_L_FIELD = Color.rgb(0xFF, 0xFF, 0xFF)
// 危险色两主题共用 LANLU_DANGER。

// 亮色叠层/舞台 token（Task 1 表 light 列；onMedia/onMediaDim 恒深，与暗色相同，不重复定义）
public let LANLU_L_OVERLAY_SURFACE = Color.rgba(255, 255, 255, 209)
public let LANLU_L_OVERLAY_BORDER = Color.rgba(0, 0, 0, 26)
public let LANLU_L_OVERLAY_HOVER = Color.rgba(0, 0, 0, 18)
public let LANLU_L_OVERLAY_TRACK = Color.rgba(0, 0, 0, 36)
public let LANLU_L_ON_OVERLAY = Color.rgb(0x1D, 0x1D, 0x21)
public let LANLU_L_ON_OVERLAY_DIM = Color.rgba(29, 29, 33, 148)
public let LANLU_L_STAGE_BG = Color.rgb(0xEC, 0xEC, 0xF1)
// 合集卡叠层面板亮色组（原型 #window.light .card.tank .stack 覆写）。
public let LANLU_L_TANK_STACK_HI = Color.rgb(0xD5, 0xDC, 0xEA)
public let LANLU_L_TANK_STACK_LO = Color.rgb(0xC0, 0xC9, 0xD9)
