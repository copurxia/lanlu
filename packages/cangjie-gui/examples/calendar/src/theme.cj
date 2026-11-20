/*
 * 日历的紫色主题与卡片表面样式。
 */
package cui_calendar

import cui.{Color, SurfaceStyle, Theme}

let CALENDAR_ACCENT = Color.rgb(126, 87, 194)

func calendarTheme(): Theme {
    Theme(
        Color.rgb(246, 241, 250),
        Color.rgb(255, 255, 255),
        Color.rgb(217, 205, 228),
        Color.rgb(36, 29, 44),
        Color.rgb(105, 93, 117),
        CALENDAR_ACCENT,
        Color.rgb(255, 255, 255),
        Color.rgb(198, 63, 91),
        Color.rgb(253, 251, 255),
        Color.rgb(241, 233, 255),
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(235, 224, 255),
        shadow: Color.rgba(43, 24, 70, 26),
        radius: 18.0,
        controlRadius: 12.0
    )
}

/** 选中日之外，“今天”保持柔和描边，切换选择时依旧可辨。 */
func todaySurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(241, 233, 255),
        border: CALENDAR_ACCENT,
        radius: 12.0,
        borderWidth: 1.5
    )
}

func agendaCardSurface(): SurfaceStyle {
    SurfaceStyle(Color.rgb(243, 237, 252), radius: 12.0)
}
