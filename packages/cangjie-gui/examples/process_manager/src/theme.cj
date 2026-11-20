/*
 * 桌面集成层：深色主题、应用元数据与 SDL 提示。
 * 视觉与桌面壳设置集中在一处，与业务逻辑完全解耦。
 */
package cui_process_manager

import cui.{AppMetadata, AppMetadataType, Color, SdlHint, SdlHintSetting, Theme}

// 深石板底 + 薄荷绿强调：监控类工具的低刺激配色，长时间盯着也不刺眼。
func processTheme(): Theme {
    Theme(
        Color.rgb(17, 24, 39),
        Color.rgb(24, 32, 46),
        Color.rgb(54, 68, 89),
        Color.rgb(236, 253, 245),
        Color.rgb(148, 163, 184),
        Color.rgb(52, 211, 153),
        Color.rgb(6, 32, 24),
        Color.rgb(251, 113, 133),
        Color.rgb(31, 41, 55),
        Color.rgb(36, 61, 55),
        panelRaised: Color.rgb(30, 41, 59),
        accentSoft: Color.rgb(26, 77, 66),
        shadow: Color.rgba(0, 0, 0, 82),
        radius: 16.0,
        controlRadius: 11.0
    )
}

// 元数据供操作系统展示（任务栏、关于对话框等），与窗口标题相互独立。
func processMetadata(): AppMetadata {
    var metadata = AppMetadata(
        name: Some("CUI Process Manager"),
        version: Some("0.1.0"),
        identifier: Some("dev.cui.examples.process-manager")
    )
    metadata.creator = Some("CUI Examples")
    metadata.appType = Some(AppMetadataType.Application)
    metadata
}

func processHints(): Array<SdlHintSetting> {
    [
        SdlHintSetting(SdlHint.AppName, "CUI Process Manager"),
        SdlHintSetting(SdlHint.AppId, "dev.cui.examples.process-manager"),
        SdlHintSetting(SdlHint.RenderVSync, "1")
    ]
}
