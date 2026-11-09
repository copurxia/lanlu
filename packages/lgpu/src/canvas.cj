package lgpu

import sdl.{Canvas, Color, Pen, Rect}

// lgpu（wgpu）实现的 Canvas：把视图图元映射到 L 层的 SDF/纹理管线。
//
// 与 sdl.Renderer 的差异（迁移期可见）：
// - 文本度量来自 lgpu 自己的字形光栅化（ab_glyph），与 fontkit 的度量在极端字号下
//   可能差 1px；切换后如需完全一致，再把 fontkit 的度量接进来。
// - 柔和圆角（feather）暂时按普通圆角绘制（SDF 自带抗锯齿，视觉上很接近）。

func channel(v: UInt8): Float32 {
    Float32(v) / 255.0
}

public class LgpuCanvas <: Canvas {
    private let surface: Surface
    private let font: Font

    /// surface 由 lwindow 的窗口持有；font 用系统字体文件加载。
    public init(surface: Surface, font: Font) {
        this.surface = surface
        this.font = font
    }

    public func fill(rect: Rect, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, 0.0,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func fillRoundedRect(rect: Rect, radius: Float32, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, radius, 0.0,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit {
        // SDF 自带解析抗锯齿；feather 暂时忽略（见文件头说明）
        fillRoundedRect(rect, radius, color)
    }

    public func strokeRect(rect: Rect, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), channel(pen.color.a))
    }

    public func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), channel(pen.color.a))
    }

    public func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {
        surface.line(x1, y1, x2, y2, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), channel(pen.color.a))
    }

    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit {
        surface.line(x1, y1, x2, y2, 1.0,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
        surface.circle(cx, cy, radius,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64 = 0): Unit {
        surface.strokeCircle(cx, cy, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), channel(pen.color.a))
    }

    public func text(text: String, x: Float32, y: Float32, color: Color, pointSize!: Float32 = 15.0): Unit {
        let _ = surface.text(font, text, x, y, pointSize,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func textWidth(text: String, pointSize!: Float32 = 15.0): Float32 {
        font.measure(text, pointSize)
    }

    public func textHeight(pointSize!: Float32 = 15.0): Float32 {
        // 与 SDL_ttf 的行高近似；后续接 fontkit 度量口径
        pointSize * 1.35
    }

    public func textCenter(text: String, rect: Rect, color: Color, pointSize!: Float32 = 15.0): Unit {
        let w = textWidth(text, pointSize: pointSize)
        let h = textHeight(pointSize: pointSize)
        this.text(text, rect.x + (rect.w - w) * 0.5, rect.y + (rect.h - h) * 0.5, color,
            pointSize: pointSize)
    }
}
