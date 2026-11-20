/*
 * 命令面板主题：深色浮层观感，配色令牌集中于此。
 */
package cui_command_palette

import cui.{Color, Length, LengthUnits, Theme}

/** 面板主标题字号。 */
let PALETTE_TITLE: Length = 20.fp

func paletteTheme(): Theme {
    Theme(
        Color.rgb(23, 25, 33), // bg
        Color.rgb(33, 36, 47), // panel
        Color.rgb(52, 57, 72), // panelEdge
        Color.rgb(232, 235, 244), // text
        Color.rgb(150, 157, 173), // mutedText
        Color.rgb(112, 143, 255), // accent
        Color.rgb(255, 255, 255), // accentText
        Color.rgb(233, 92, 102), // danger
        Color.rgb(27, 30, 40), // field
        Color.rgb(40, 45, 60), // fieldActive
        panelRaised: Color.rgb(45, 50, 65),
        accentSoft: Color.rgb(43, 53, 92),
        shadow: Color.rgba(0, 0, 0, 90),
        radius: 14.0,
        controlRadius: 10.0
    )
}
