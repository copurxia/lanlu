package lanlu_client_next.app

import lanlu_ui.{Color, ThemeKeys, ThemeValue}

/*
 * Phase 4 等价性守卫：主题资源字典的每个颜色 key，其明/暗取值必须与迁移前视图
 * 分支所引用的 palette 常量（含从视图逐字提取的字面量对）逐位相同——这是
 * 「零视觉改变」的机器检查。任何 key 的取值调整都会在这里先行红灯。
 *
 * 数值型 token（DetailScrimFade）以 Double 断言（亮 0.92 / 暗 0.96，原分支如此）。
 * 混合对（CardBg/PopupSurface/DetailCardElev/PvBadgeFg 等）按 theme_tokens.cj
 * 声明的两端分别断言，端点即原视图分支的两支。
 */

// 断言单个 key 的明/暗两支都与期望色逐位一致（Color 的 == 即分量相等）。
private func expectPair(key: String, light: Color, dark: Color): Unit {
    @Expect(paletteColor(key, true), light)
    @Expect(paletteColor(key, false), dark)
}

@Test
func baseLayerKeysMatchPalette(): Unit {
    expectPair(AppKeys.Bg, LANLU_L_BG, LANLU_BG)
    expectPair(AppKeys.Panel, LANLU_L_PANEL, LANLU_PANEL)
    expectPair(AppKeys.PanelRaised, LANLU_L_PANEL_RAISED, LANLU_PANEL_RAISED)
    expectPair(AppKeys.PanelEdge, LANLU_L_PANEL_EDGE, LANLU_PANEL_EDGE)
    expectPair(AppKeys.Text, LANLU_L_TEXT, LANLU_TEXT)
    expectPair(AppKeys.Muted, LANLU_L_MUTED, LANLU_MUTED)
    expectPair(AppKeys.Accent, LANLU_L_ACCENT, LANLU_ACCENT)
    expectPair(AppKeys.AccentText, LANLU_L_ACCENT_TEXT, LANLU_ACCENT_TEXT)
    expectPair(AppKeys.AccentSoft, LANLU_L_ACCENT_SOFT, LANLU_ACCENT_SOFT)
    expectPair(AppKeys.Field, LANLU_L_FIELD, LANLU_FIELD)
    expectPair(AppKeys.TankStackHi, LANLU_L_TANK_STACK_HI, LANLU_TANK_STACK_HI)
    expectPair(AppKeys.TankStackLo, LANLU_L_TANK_STACK_LO, LANLU_TANK_STACK_LO)
    expectPair(AppKeys.OverlaySurface, LANLU_L_OVERLAY_SURFACE, LANLU_OVERLAY_SURFACE)
}

@Test
func mixedPairKeysMatchOriginalBranches(): Unit {
    // 卡片底：亮 = panel、暗 = field（原 16 个视图的分支即如此）。
    expectPair(AppKeys.CardBg, LANLU_L_PANEL, LANLU_FIELD)
    // 浮层表面：亮 = panel、暗 = panelRaised。
    expectPair(AppKeys.PopupSurface, LANLU_L_PANEL, LANLU_PANEL_RAISED)
    // 详情卡计数 pill 底：亮 = panelRaised、暗 = panel。
    expectPair(AppKeys.DetailCardElev, LANLU_L_PANEL_RAISED, LANLU_PANEL)
    // 页码前景：亮 = text、暗 = onMedia。
    expectPair(AppKeys.PvBadgeFg, LANLU_L_TEXT, LANLU_ON_MEDIA)
    // 用户/服务器菜单：亮支为提取字面量，暗支走既有 token。
    expectPair(AppKeys.UserMenuBorder, LANLU_L_USER_MENU_BORDER, LANLU_PANEL_EDGE)
    expectPair(AppKeys.UserMenuHover, LANLU_L_USER_MENU_HOVER, LANLU_OVERLAY_HOVER)
}

@Test
func loginLiteralPairsMatchVerbatimExtraction(): Unit {
    // login_view.cj 三对内联字面量（任务书点名）：提取必须逐字，一位不改。
    expectPair(AppKeys.LoginShadow, Color.rgba(0, 0, 0, 20), Color.rgba(0, 0, 0, 115))
    expectPair(AppKeys.LoginEdge, Color.rgba(199, 138, 30, 89), Color.rgba(232, 176, 75, 89))
    expectPair(AppKeys.LoginEdgeSoft, Color.rgba(199, 138, 30, 76), Color.rgba(232, 176, 75, 76))
}

@Test
func extractedLiteralPairsMatchVerbatimValues(): Unit {
    // 迁移中发现的其余内联字面量对（同一条提取规则）：palette 常量 ↔ 原字面量互证。
    expectPair(AppKeys.SegTrack, Color.rgba(0, 0, 0, 15), Color.rgba(255, 255, 255, 18))
    expectPair(AppKeys.SwitchOff, Color.rgba(0, 0, 0, 46), Color.rgba(255, 255, 255, 38))
    expectPair(AppKeys.Separator, Color.rgba(0, 0, 0, 15), Color.rgba(255, 255, 255, 10))
    expectPair(AppKeys.TagChipBg, Color.rgba(0, 0, 0, 13), Color.rgba(255, 255, 255, 15))
    expectPair(AppKeys.CoverShadow, Color.rgba(0, 0, 0, 26), Color.rgba(0, 0, 0, 140))
    expectPair(AppKeys.UserMenuBorder, Color.rgba(0, 0, 0, 28), LANLU_PANEL_EDGE)
    expectPair(AppKeys.UserMenuHover, Color.rgb(0xF2, 0xF2, 0xF4), LANLU_OVERLAY_HOVER)
}

@Test
func readerAndScrimKeysMatchPalette(): Unit {
    // 阅读器轨道/开关/顶栏渐隐（渐隐底色 = BG 烘焙 alpha，palette 内以 withAlpha 派生）。
    expectPair(AppKeys.SegTrack, LANLU_L_SEG_TRACK, LANLU_SEG_TRACK)
    expectPair(AppKeys.SwitchOff, LANLU_L_SWITCH_OFF, LANLU_SWITCH_OFF)
    expectPair(AppKeys.ReaderBarScrimTop, LANLU_L_READER_BAR_SCRIM_TOP, LANLU_READER_BAR_SCRIM_TOP)
    expectPair(AppKeys.ReaderBarScrimBottom, LANLU_L_READER_BAR_SCRIM_BOTTOM, LANLU_READER_BAR_SCRIM_BOTTOM)
    // 详情 backdrop 双层 scrim。
    expectPair(AppKeys.DetailScrimSide, LANLU_L_DETAIL_SCRIM_SIDE, LANLU_DETAIL_SCRIM_SIDE)
    expectPair(AppKeys.DetailScrimSideClear, LANLU_L_DETAIL_SCRIM_SIDE_CLEAR, LANLU_DETAIL_SCRIM_SIDE_CLEAR)
    expectPair(AppKeys.DetailScrimBottom, LANLU_L_DETAIL_SCRIM_BOTTOM, LANLU_DETAIL_SCRIM_BOTTOM)
    // 页面预览。
    expectPair(AppKeys.PvThumbBg, LANLU_L_PV_THUMB_BG, LANLU_PV_THUMB_BG)
    expectPair(AppKeys.PvBadgeBg, LANLU_L_PV_BADGE_BG, LANLU_PV_BADGE_BG)
    expectPair(AppKeys.PvBadgeFgRead, LANLU_L_PV_READ_FG, LANLU_PV_PAGE_FG_READ)
    expectPair(AppKeys.PvIconFgRead, LANLU_L_PV_READ_FG, LANLU_PV_ICON_FG_READ)
    expectPair(AppKeys.PvRowFgRead, LANLU_L_PV_ROW_FG_READ, LANLU_PV_ROW_FG_READ)
}

@Test
func doubleTokenMatchesOriginalBranches(): Unit {
    // 底部 scrim 融合拐点（原 detailSkeleton 分支：亮 0.92 / 暗 0.96）。
    let resources = appThemeResources()
    match (resources.lightValue(AppKeys.DetailScrimFade)) {
        case Some(ThemeValue.Double(v)) => @Expect(v, 0.92)
        case _ => @Expect(true, false)
    }
    match (resources.darkValue(AppKeys.DetailScrimFade)) {
        case Some(ThemeValue.Double(v)) => @Expect(v, 0.96)
        case _ => @Expect(true, false)
    }
}

@Test
func dictionaryMergesOverFrameworkStandard(): Unit {
    // 应用字典以 standard() 为底叠加：框架自身 key 不被应用覆盖删除，
    // 绘制期 framework 部件查询（elevation 等）依旧命中。
    let resources = appThemeResources()
    match (resources.lightValue(ThemeKeys.BrushBackgroundDefault)) {
        case Some(_) => ()
        case None => @Expect(true, false)
    }
    match (resources.lightValue(AppKeys.Bg)) {
        case Some(_) => ()
        case None => @Expect(true, false)
    }
}
