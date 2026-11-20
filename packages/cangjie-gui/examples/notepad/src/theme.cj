/*
 * 记事本的应用元数据、SDL 提示项、青绿主题与表面样式。
 * 集中在一个文件里，视图层只管取用，不关心具体色值。
 */
package cui_notepad

import cui.{AppMetadata, AppMetadataType, Color, SdlHint, SdlHintSetting, SurfaceStyle, Theme}

func notepadMetadata(): AppMetadata {
    var metadata = AppMetadata(
        name: Some("CUI Notepad"),
        version: Some("0.1.0"),
        identifier: Some("dev.cui.examples.notepad")
    )
    metadata.creator = Some("CUI Examples")
    metadata.appType = Some(AppMetadataType.Application)
    metadata
}

func notepadHints(): Array<SdlHintSetting> {
    [
        SdlHintSetting(SdlHint.AppName, "CUI Notepad"),
        SdlHintSetting(SdlHint.AppId, "dev.cui.examples.notepad"),
        SdlHintSetting(SdlHint.WindowsCloseOnAltF4, "1")
    ]
}

func notepadTheme(): Theme {
    Theme(
        Color.rgb(238, 244, 248),
        Color.rgb(255, 255, 255),
        Color.rgb(201, 213, 222),
        Color.rgb(25, 34, 43),
        Color.rgb(92, 106, 119),
        Color.rgb(34, 132, 127),
        Color.rgb(255, 255, 255),
        Color.rgb(196, 59, 76),
        Color.rgb(250, 252, 253),
        Color.rgb(229, 245, 243),
        panelRaised: Color.rgb(255, 255, 255),
        accentSoft: Color.rgb(214, 241, 238),
        shadow: Color.rgba(11, 31, 45, 26),
        radius: 16.0,
        controlRadius: 11.0
    )
}

func toolbarSurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(255, 255, 255),
        border: Color.rgb(205, 218, 226),
        radius: 16.0,
        borderWidth: 1.0,
        shadow: Color.rgba(20, 44, 56, 24),
        shadowOffsetY: 2.0
    )
}

/**
 * “新建”确认条的暖色警示表面：与常规白色面板拉开视觉差，
 * 提醒用户接下来的操作会丢弃未保存内容。
 */
func confirmBarSurface(): SurfaceStyle {
    SurfaceStyle(
        Color.rgb(255, 248, 236),
        border: Color.rgb(238, 205, 160),
        radius: 12.0,
        borderWidth: 1.0
    )
}
