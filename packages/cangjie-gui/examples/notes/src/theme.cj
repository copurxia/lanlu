/*
 * 笔记主题：清爽的浅色纸面配色，令牌集中于此。
 */
package cui_notes

import cui.{Color, Length, LengthUnits, Theme}

/** 应用主标题字号。 */
let NOTES_TITLE: Length = 20.fp

func notesTheme(): Theme {
    Theme(
        Color.rgb(244, 243, 239), // bg
        Color.rgb(255, 255, 255), // panel
        Color.rgb(224, 220, 210), // panelEdge
        Color.rgb(38, 34, 28), // text
        Color.rgb(124, 116, 102), // mutedText
        Color.rgb(196, 128, 44), // accent
        Color.rgb(255, 255, 255), // accentText
        Color.rgb(198, 74, 66), // danger
        Color.rgb(250, 249, 246), // field
        Color.rgb(248, 240, 228), // fieldActive
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(248, 236, 218),
        shadow: Color.rgba(60, 48, 30, 26),
        radius: 14.0,
        controlRadius: 10.0
    )
}
