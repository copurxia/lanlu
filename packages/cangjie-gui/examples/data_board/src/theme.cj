/*
 * 看板主题、列/卡片表面与共享字号令牌。
 */
package cui_data_board

import cui.{Color, Length, LengthUnits, SurfaceStyle, Theme}

/** 列标题与展开态卡片标题共用的字号。 */
let BOARD_HEADING: Length = 17.fp
/** “进行中”列超过在制上限时的警示色。 */
let WIP_WARNING = Color.rgb(202, 69, 83)

func boardTheme(): Theme {
    Theme(
        Color.rgb(239, 243, 248),
        Color.rgb(255, 255, 255),
        Color.rgb(207, 216, 227),
        Color.rgb(27, 36, 48),
        Color.rgb(99, 112, 128),
        Color.rgb(54, 116, 210),
        Color.rgb(255, 255, 255),
        WIP_WARNING,
        Color.rgb(248, 250, 253),
        Color.rgb(232, 240, 252),
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(226, 237, 253),
        shadow: Color.rgba(27, 43, 63, 24),
        radius: 15.0,
        controlRadius: 10.0
    )
}

func columnSurface(): SurfaceStyle {
    SurfaceStyle(Color.rgb(247, 249, 252), border: Color.rgb(207, 216, 227), radius: 15.0, borderWidth: 1.0)
}

func taskSurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(255, 255, 255),
        border: Color.rgb(218, 225, 234),
        radius: 12.0,
        borderWidth: 1.0,
        shadow: Color.rgba(31, 51, 76, 20),
        shadowOffsetY: 2.0
    )
}
