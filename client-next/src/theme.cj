package lanlu_client_next

import cui.{Color, Theme}
import lanlu_client_next.app.*

// lanlu 主题组装：调色板常量在 app/palette.cj（单一来源，那里附有原型令牌对照），
// 这里仅按明暗两套组装 Theme 字段（含 Task 1 的叠层/舞台/恒深 9 字段）。

// 暗色（默认）：金色 accent 近黑底；shadow 取深黑。
public func lanluThemeDark(): Theme {
    Theme(
        LANLU_BG,
        LANLU_PANEL,
        LANLU_PANEL_EDGE,
        LANLU_TEXT,
        LANLU_MUTED,
        LANLU_ACCENT,
        LANLU_ACCENT_TEXT,
        LANLU_DANGER,
        LANLU_FIELD,
        LANLU_PANEL_RAISED,               // fieldActive：激活/hover（= panelRaised）
        panelRaised: LANLU_PANEL_RAISED,
        accentSoft: LANLU_ACCENT_SOFT,
        shadow: Color.rgba(0, 0, 0, 72),
        radius: 8.0,
        smallRadius: 4.0,
        controlRadius: 8.0,
        borderWidth: 1.0,
        overlaySurface: LANLU_OVERLAY_SURFACE,
        overlayBorder: LANLU_OVERLAY_BORDER,
        overlayHover: LANLU_OVERLAY_HOVER,
        overlayTrack: LANLU_OVERLAY_TRACK,
        onOverlay: LANLU_ON_OVERLAY,
        onOverlayDim: LANLU_ON_OVERLAY_DIM,
        stageBg: LANLU_STAGE_BG,
        onMedia: LANLU_ON_MEDIA,
        onMediaDim: LANLU_ON_MEDIA_DIM
    )
}

// 亮色：白底深金 accent；危险色与恒深媒体舞台文字沿用暗色 token。
public func lanluThemeLight(): Theme {
    Theme(
        LANLU_L_BG,
        LANLU_L_PANEL,
        LANLU_L_PANEL_EDGE,
        LANLU_L_TEXT,
        LANLU_L_MUTED,
        LANLU_L_ACCENT,
        LANLU_L_ACCENT_TEXT,
        LANLU_DANGER,
        LANLU_L_FIELD,
        LANLU_L_PANEL_RAISED,             // fieldActive（= panelRaised）
        panelRaised: LANLU_L_PANEL_RAISED,
        accentSoft: LANLU_L_ACCENT_SOFT,
        shadow: Color.rgba(0, 0, 0, 28),
        radius: 8.0,
        smallRadius: 4.0,
        controlRadius: 8.0,
        borderWidth: 1.0,
        overlaySurface: LANLU_L_OVERLAY_SURFACE,
        overlayBorder: LANLU_L_OVERLAY_BORDER,
        overlayHover: LANLU_L_OVERLAY_HOVER,
        overlayTrack: LANLU_L_OVERLAY_TRACK,
        onOverlay: LANLU_L_ON_OVERLAY,
        onOverlayDim: LANLU_L_ON_OVERLAY_DIM,
        stageBg: LANLU_L_STAGE_BG,
        onMedia: LANLU_ON_MEDIA,
        onMediaDim: LANLU_ON_MEDIA_DIM
    )
}

// 设置值 → 主题（"light" 之外的值一律按暗色处理，与 AppSettings.theme 默认值对齐）。
public func lanluThemeFor(mode: String): Theme {
    if (mode == "light") {
        lanluThemeLight()
    } else {
        lanluThemeDark()
    }
}
