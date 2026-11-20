/*
 * 通讯录主题：干净的浅色配色、靛蓝强调，字号令牌集中于此。
 */
package cui_contacts

import cui.{Color, Length, LengthUnits, Theme}

let CONTACTS_TITLE: Length = 20.fp
let CONTACTS_HEADING: Length = 16.fp

func contactsTheme(): Theme {
    Theme(
        Color.rgb(245, 246, 249), // bg
        Color.rgb(255, 255, 255), // panel
        Color.rgb(224, 227, 233), // panelEdge
        Color.rgb(30, 34, 44), // text
        Color.rgb(114, 121, 135), // mutedText
        Color.rgb(79, 70, 229), // accent（靛蓝）
        Color.rgb(255, 255, 255), // accentText
        Color.rgb(220, 74, 68), // danger
        Color.rgb(250, 251, 253), // field
        Color.rgb(238, 240, 251), // fieldActive
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(230, 229, 251),
        shadow: Color.rgba(24, 26, 48, 30),
        radius: 14.0,
        controlRadius: 10.0
    )
}
