package lanlu_client_next.app

import lanlu_ui.{Color, UiContext}
import lanlu_ui.{THEME_KEY_MISSING_COLOR, ThemeResources, ThemeValue, themeResource}
import std.env.getStdErr

/*
 * 应用侧主题资源字典（Phase 4）：把原先散落在 16 个视图里的
 * `if (明暗布尔) { LANLU_L_X } else { LANLU_X }` 颜色决策收敛成「按 key 查表」。
 *
 * 数值来源仍且仅是 palette.cj（单一来源原则不变）；这里只声明「哪个主题取哪个值」——
 * 明/暗双值随 key 进字典，选典只发生在两处（构建期 model.brush、绘制期 themeResource
 * 按当前主题挑 light/dark 分册），业务视图不再出现明暗分支。
 *
 * 等价性由 theme_tokens_test.cj 逐 key 断言守卫：任一 key 的明/暗取值必须与迁移前
 * 的 palette 常量逐位相同，这是「零视觉改变」的机器检查。
 */

/*
 * 应用笔刷 key（与框架 ThemeKeys 同风格：struct + static let 承载常量集，
 * 引用 key 一律经由此类型，避免裸字符串散落各处）。
 * 除标注外，明/暗两值都是同名 palette 常量；「混合对」注释说明两端来源。
 */
public struct AppKeys {
    // —— 基础层（同名 palette 对的直投）——
    public static let Bg = "AppBrushBackground"
    public static let Panel = "AppBrushPanel"
    public static let PanelRaised = "AppBrushPanelRaised"
    public static let PanelEdge = "AppBrushPanelEdge"
    public static let Text = "AppBrushText"
    public static let Muted = "AppBrushTextMuted"
    public static let Accent = "AppBrushAccent"
    public static let AccentText = "AppBrushTextOnAccent"
    public static let AccentSoft = "AppBrushAccentSoft"
    public static let Field = "AppBrushField"
    public static let TankStackHi = "AppBrushTankStackHi"
    public static let TankStackLo = "AppBrushTankStackLo"
    public static let OverlaySurface = "AppBrushOverlaySurface"
    // —— 混合对：同一语义下明/暗取自不同 token（原视图分支即如此，非新决策）——
    // 卡片底：亮 = panel、暗 = field（登录卡、统计卡、上传任务卡、详情卡、进度卡共用）。
    public static let CardBg = "AppBrushCardBg"
    // 浮层表面：亮 = panel（纯白）、暗 = panelRaised（原 search_autocomplete 与用户菜单弹层）。
    public static let PopupSurface = "AppBrushPopupSurface"
    // 详情卡计数 pill 底：亮 = panelRaised、暗 = panel（原 detailCard elev 支路）。
    public static let DetailCardElev = "AppBrushDetailCardElev"
    // —— 登录页提取对 ——
    public static let LoginShadow = "AppBrushLoginShadow"
    public static let LoginEdge = "AppBrushLoginEdge"
    public static let LoginEdgeSoft = "AppBrushLoginEdgeSoft"
    // —— 标题栏用户/服务器菜单（亮支为提取字面量，暗支走既有 token）——
    public static let UserMenuBorder = "AppBrushUserMenuBorder"
    public static let UserMenuHover = "AppBrushUserMenuHover"
    // —— 阅读器 ——
    public static let SegTrack = "AppBrushSegTrack"
    public static let SwitchOff = "AppBrushSwitchOff"
    public static let ReaderBarScrimTop = "AppBrushReaderBarScrimTop"
    public static let ReaderBarScrimBottom = "AppBrushReaderBarScrimBottom"
    // —— 分隔线 / chip 底 ——
    public static let Separator = "AppBrushSeparator"
    public static let TagChipBg = "AppBrushTagChipBg"
    // —— 详情页 ——
    public static let CoverShadow = "AppBrushCoverShadow"
    public static let DetailScrimSide = "AppBrushDetailScrimSide"
    public static let DetailScrimSideClear = "AppBrushDetailScrimSideClear"
    public static let DetailScrimBottom = "AppBrushDetailScrimBottom"
    // 底部 scrim 的融合拐点位置（数值型 token：亮 0.92 / 暗 0.96，原分支如此——
    // 渐变 knot 不是颜色，走 ThemeValue.Double）。
    public static let DetailScrimFade = "AppDoubleDetailScrimFade"
    // —— 页面预览（pvThumb/pvRow）——
    public static let PvThumbBg = "AppBrushPvThumbBg"
    public static let PvBadgeBg = "AppBrushPvBadgeBg"
    // 页码前景：亮 = text、暗 = onMedia（恒深舞台上的白字）。
    public static let PvBadgeFg = "AppBrushPvBadgeFg"
    public static let PvBadgeFgRead = "AppBrushPvBadgeFgRead"
    public static let PvIconFgRead = "AppBrushPvIconFgRead"
    public static let PvRowFgRead = "AppBrushPvRowFgRead"
}

/*
 * 组装应用字典：以框架 standard() 为底、应用 key 逐个叠加覆盖。standard() 自身的
 * key（elevation、TypeRamp 等）不受影响；应用 key 与之同住一张表，绘制期经
 * `themeResource(ctx, key)` 一并查询。构建期（无 ctx）走 paletteColor。
 */
public func appThemeResources(): ThemeResources {
    let resources = ThemeResources.standard()
    let overrides = ThemeResources()
    // 基础层。
    overrides.setLight(AppKeys.Bg, ThemeValue.Color(LANLU_L_BG)).setDark(AppKeys.Bg, ThemeValue.Color(LANLU_BG))
    overrides.setLight(AppKeys.Panel, ThemeValue.Color(LANLU_L_PANEL)).setDark(AppKeys.Panel,
        ThemeValue.Color(LANLU_PANEL))
    overrides.setLight(AppKeys.PanelRaised, ThemeValue.Color(LANLU_L_PANEL_RAISED)).setDark(AppKeys.PanelRaised,
        ThemeValue.Color(LANLU_PANEL_RAISED))
    overrides.setLight(AppKeys.PanelEdge, ThemeValue.Color(LANLU_L_PANEL_EDGE)).setDark(AppKeys.PanelEdge,
        ThemeValue.Color(LANLU_PANEL_EDGE))
    overrides.setLight(AppKeys.Text, ThemeValue.Color(LANLU_L_TEXT)).setDark(AppKeys.Text, ThemeValue.Color(LANLU_TEXT))
    overrides.setLight(AppKeys.Muted, ThemeValue.Color(LANLU_L_MUTED)).setDark(AppKeys.Muted,
        ThemeValue.Color(LANLU_MUTED))
    overrides.setLight(AppKeys.Accent, ThemeValue.Color(LANLU_L_ACCENT)).setDark(AppKeys.Accent,
        ThemeValue.Color(LANLU_ACCENT))
    overrides.setLight(AppKeys.AccentText, ThemeValue.Color(LANLU_L_ACCENT_TEXT)).setDark(AppKeys.AccentText,
        ThemeValue.Color(LANLU_ACCENT_TEXT))
    overrides.setLight(AppKeys.AccentSoft, ThemeValue.Color(LANLU_L_ACCENT_SOFT)).setDark(AppKeys.AccentSoft,
        ThemeValue.Color(LANLU_ACCENT_SOFT))
    overrides.setLight(AppKeys.Field, ThemeValue.Color(LANLU_L_FIELD)).setDark(AppKeys.Field,
        ThemeValue.Color(LANLU_FIELD))
    overrides.setLight(AppKeys.TankStackHi, ThemeValue.Color(LANLU_L_TANK_STACK_HI)).setDark(AppKeys.TankStackHi,
        ThemeValue.Color(LANLU_TANK_STACK_HI))
    overrides.setLight(AppKeys.TankStackLo, ThemeValue.Color(LANLU_L_TANK_STACK_LO)).setDark(AppKeys.TankStackLo,
        ThemeValue.Color(LANLU_TANK_STACK_LO))
    overrides.setLight(AppKeys.OverlaySurface, ThemeValue.Color(LANLU_L_OVERLAY_SURFACE)).setDark(AppKeys.OverlaySurface,
        ThemeValue.Color(LANLU_OVERLAY_SURFACE))
    // 混合对（明/暗语义端点不同，见 AppKeys 注释）。
    overrides.setLight(AppKeys.CardBg, ThemeValue.Color(LANLU_L_PANEL)).setDark(AppKeys.CardBg,
        ThemeValue.Color(LANLU_FIELD))
    overrides.setLight(AppKeys.PopupSurface, ThemeValue.Color(LANLU_L_PANEL)).setDark(AppKeys.PopupSurface,
        ThemeValue.Color(LANLU_PANEL_RAISED))
    overrides.setLight(AppKeys.DetailCardElev, ThemeValue.Color(LANLU_L_PANEL_RAISED)).setDark(AppKeys.DetailCardElev,
        ThemeValue.Color(LANLU_PANEL))
    // 登录页提取对。
    overrides.setLight(AppKeys.LoginShadow, ThemeValue.Color(LANLU_L_LOGIN_SHADOW)).setDark(AppKeys.LoginShadow,
        ThemeValue.Color(LANLU_LOGIN_SHADOW))
    overrides.setLight(AppKeys.LoginEdge, ThemeValue.Color(LANLU_L_LOGIN_EDGE)).setDark(AppKeys.LoginEdge,
        ThemeValue.Color(LANLU_LOGIN_EDGE))
    overrides.setLight(AppKeys.LoginEdgeSoft, ThemeValue.Color(LANLU_L_LOGIN_EDGE_SOFT)).setDark(AppKeys.LoginEdgeSoft,
        ThemeValue.Color(LANLU_LOGIN_EDGE_SOFT))
    // 用户/服务器菜单。
    overrides.setLight(AppKeys.UserMenuBorder, ThemeValue.Color(LANLU_L_USER_MENU_BORDER)).setDark(AppKeys.UserMenuBorder,
        ThemeValue.Color(LANLU_PANEL_EDGE))
    overrides.setLight(AppKeys.UserMenuHover, ThemeValue.Color(LANLU_L_USER_MENU_HOVER)).setDark(AppKeys.UserMenuHover,
        ThemeValue.Color(LANLU_OVERLAY_HOVER))
    // 阅读器。
    overrides.setLight(AppKeys.SegTrack, ThemeValue.Color(LANLU_L_SEG_TRACK)).setDark(AppKeys.SegTrack,
        ThemeValue.Color(LANLU_SEG_TRACK))
    overrides.setLight(AppKeys.SwitchOff, ThemeValue.Color(LANLU_L_SWITCH_OFF)).setDark(AppKeys.SwitchOff,
        ThemeValue.Color(LANLU_SWITCH_OFF))
    overrides.setLight(AppKeys.ReaderBarScrimTop, ThemeValue.Color(LANLU_L_READER_BAR_SCRIM_TOP))
        .setDark(AppKeys.ReaderBarScrimTop, ThemeValue.Color(LANLU_READER_BAR_SCRIM_TOP))
    overrides.setLight(AppKeys.ReaderBarScrimBottom, ThemeValue.Color(LANLU_L_READER_BAR_SCRIM_BOTTOM))
        .setDark(AppKeys.ReaderBarScrimBottom, ThemeValue.Color(LANLU_READER_BAR_SCRIM_BOTTOM))
    // 分隔线 / chip 底。
    overrides.setLight(AppKeys.Separator, ThemeValue.Color(LANLU_L_SEPARATOR)).setDark(AppKeys.Separator,
        ThemeValue.Color(LANLU_SEPARATOR))
    overrides.setLight(AppKeys.TagChipBg, ThemeValue.Color(LANLU_L_TAG_CHIP_BG)).setDark(AppKeys.TagChipBg,
        ThemeValue.Color(LANLU_TAG_CHIP_BG))
    // 详情页。
    overrides.setLight(AppKeys.CoverShadow, ThemeValue.Color(LANLU_L_COVER_SHADOW)).setDark(AppKeys.CoverShadow,
        ThemeValue.Color(LANLU_COVER_SHADOW))
    overrides.setLight(AppKeys.DetailScrimSide, ThemeValue.Color(LANLU_L_DETAIL_SCRIM_SIDE))
        .setDark(AppKeys.DetailScrimSide, ThemeValue.Color(LANLU_DETAIL_SCRIM_SIDE))
    overrides.setLight(AppKeys.DetailScrimSideClear, ThemeValue.Color(LANLU_L_DETAIL_SCRIM_SIDE_CLEAR))
        .setDark(AppKeys.DetailScrimSideClear, ThemeValue.Color(LANLU_DETAIL_SCRIM_SIDE_CLEAR))
    overrides.setLight(AppKeys.DetailScrimBottom, ThemeValue.Color(LANLU_L_DETAIL_SCRIM_BOTTOM))
        .setDark(AppKeys.DetailScrimBottom, ThemeValue.Color(LANLU_DETAIL_SCRIM_BOTTOM))
    overrides.setLight(AppKeys.DetailScrimFade, ThemeValue.Double(0.92)).setDark(AppKeys.DetailScrimFade,
        ThemeValue.Double(0.96))
    // 页面预览。
    overrides.setLight(AppKeys.PvThumbBg, ThemeValue.Color(LANLU_L_PV_THUMB_BG)).setDark(AppKeys.PvThumbBg,
        ThemeValue.Color(LANLU_PV_THUMB_BG))
    overrides.setLight(AppKeys.PvBadgeBg, ThemeValue.Color(LANLU_L_PV_BADGE_BG)).setDark(AppKeys.PvBadgeBg,
        ThemeValue.Color(LANLU_PV_BADGE_BG))
    overrides.setLight(AppKeys.PvBadgeFg, ThemeValue.Color(LANLU_L_TEXT)).setDark(AppKeys.PvBadgeFg,
        ThemeValue.Color(LANLU_ON_MEDIA))
    overrides.setLight(AppKeys.PvBadgeFgRead, ThemeValue.Color(LANLU_L_PV_READ_FG)).setDark(AppKeys.PvBadgeFgRead,
        ThemeValue.Color(LANLU_PV_PAGE_FG_READ))
    overrides.setLight(AppKeys.PvIconFgRead, ThemeValue.Color(LANLU_L_PV_READ_FG)).setDark(AppKeys.PvIconFgRead,
        ThemeValue.Color(LANLU_PV_ICON_FG_READ))
    overrides.setLight(AppKeys.PvRowFgRead, ThemeValue.Color(LANLU_L_PV_ROW_FG_READ)).setDark(AppKeys.PvRowFgRead,
        ThemeValue.Color(LANLU_PV_ROW_FG_READ))
    resources.merge(overrides)
    resources
}

/*
 * 构建期查表（无 ctx 时用；有 ctx 的绘制期走 themeResource(ctx, key)）：按 `light`
 * 选 light/dark 分册。缺 key 沿用框架语义——返回品红并往 stderr 打一行警告，不抛异常
 *（立即模式里把缺项「描红」到画面上更利于调试）。
 */
public func paletteColor(key: String, light: Bool): Color {
    let resources = appThemeResources()
    let found = if (light) {
        resources.lightValue(key)
    } else {
        resources.darkValue(key)
    }
    match (found) {
        case Some(ThemeValue.Color(c)) => c
        case Some(_) => THEME_KEY_MISSING_COLOR // 数值型 key 不是颜色，按缺项描红
        case None =>
            getStdErr().write("paletteColor: missing key \"${key}\" in ${if (light) {"light"} else {"dark"}} dictionary\n")
            THEME_KEY_MISSING_COLOR
    }
}

/*
 * 绘制期颜色查询的解包便捷件：AppKeys 全部颜色 key 都经它落到 Color。
 * 缺 key / 非 Color 值时 themeResource 已描红，这里仅兜底返回品红保持类型整齐。
 */
public func themeColor(ctx: UiContext, key: String): Color {
    match (themeResource(ctx, key)) {
        case ThemeValue.Color(c) => c
        case _ => THEME_KEY_MISSING_COLOR
    }
}
