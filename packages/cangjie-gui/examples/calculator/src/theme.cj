/*
 * 计算器的暗色主题与三类键面样式。
 */
package cui_calculator

import cui.{Color, SurfaceStyle, Theme}

func calculatorTheme(): Theme {
    Theme(
        Color.rgb(23, 25, 31),
        Color.rgb(31, 35, 44),
        Color.rgb(72, 78, 92),
        Color.rgb(246, 248, 252),
        Color.rgb(159, 168, 184),
        Color.rgb(106, 168, 255),
        Color.rgb(10, 20, 34),
        Color.rgb(255, 117, 117),
        Color.rgb(40, 45, 56),
        Color.rgb(47, 58, 76),
        panelRaised: Color.rgb(45, 51, 64),
        accentSoft: Color.rgb(39, 66, 104),
        shadow: Color.rgba(0, 0, 0, 84),
        radius: 18.0,
        controlRadius: 14.0
    )
}

func displaySurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(16, 19, 25),
        border: Color.rgb(61, 70, 86),
        radius: 18.0,
        borderWidth: 1.0,
        shadow: Color.rgba(0, 0, 0, 70),
        shadowOffsetY: 3.0
    )
}

func operatorKeySurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(255, 159, 67),
        border: Color.rgb(255, 178, 104),
        radius: 14.0,
        borderWidth: 1.0,
        shadow: Color.rgba(255, 159, 67, 30),
        shadowOffsetY: 2.0
    )
}

func functionKeySurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(61, 68, 82),
        border: Color.rgb(82, 92, 110),
        radius: 14.0,
        borderWidth: 1.0,
        shadow: Color.rgba(0, 0, 0, 36),
        shadowOffsetY: 1.0
    )
}
