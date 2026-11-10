package lgpu

import std.env.getVariable
import std.fs.{File, Path, exists}
import std.collection.ArrayList
import std.collection.HashMap
import lgui.{Canvas, Color, Pen, Rect}

// lgpu（wgpu）实现的 Canvas：把视图图元映射到 L 层的 SDF/纹理管线。
//
// 与 lgui.Renderer 的差异（迁移期可见）：
// - 文本度量来自 lgpu 自己的字形光栅化（ab_glyph），与 fontkit 的度量在极端字号下
//   可能差 1px；切换后如需完全一致，再把 fontkit 的度量接进来。
// - 柔和圆角（feather）暂时按普通圆角绘制（SDF 自带抗锯齿，视觉上很接近）。

func channel(v: UInt8): Float32 {
    Float32(v) / 255.0
}

// 联调 trace：把关键步骤追加到 $HOME/probe_trace.txt（LANLU_PROBE_LGPU=1 时）。
func probeTrace(line: String): Unit {
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") != "1") {
        return
    }
    let home = getVariable("HOME") ?? "."
    let path = Path(home + "/probe_trace.txt")
    try {
        let old = if (exists(path)) { String.fromUtf8(File.readFrom(path)) } else { "" }
        File.writeTo(path, (old + line + nline()).toArray())
    } catch (_) {}
}

func lastErrorText(): String {
    unsafe { lgpu_last_error().toString() }
}

func nline(): String {
    String.fromUtf8(Array<UInt8>(1, repeat: 10))
}

public class LgpuCanvas <: Canvas {
    private let surface: Surface
    private let font: Font

    /// surface 由 lwindow 的窗口持有；font 用系统字体文件加载。
    public init(surface: Surface, font: Font) {
        this.surface = surface
        this.font = font
    }

    /// 离屏抓帧：把当前已录制的一帧重绘到离屏纹理并写出原始 RGBA（w*h*4）。
    /// 返回 >0 成功（w*1e6+h），<0 为错误码。
    public func captureTo(path: String): Int32 {
        this.surface.captureTo(path)
    }

    /// 开始一帧：清屏 + 可选的整体缩放（用于把逻辑尺寸的 UI 画进小窗口预览）。
    public var scale: Float32 = 1.0
    // 联调：把每帧清屏色强制成不透明红，用于判断"surface 能否上屏"（与 UI 绘制无关）。
    public var forceClearRed: Bool = false

    private var firstFrame = true

    public func beginFrame(clear: Color): Unit {
        if (forceClearRed) {
            surface.beginFrame(1.0, 0.0, 0.0, 1.0)
            if (firstFrame) {
                firstFrame = false
                probeTrace("first frame RED clear scale=" + scale.toString())
            }
            return
        }
        if (firstFrame) {
            firstFrame = false
            probeTrace("first frame begin scale=" + scale.toString())
        }
        // 每帧重置裁剪栈：Renderer.beginScene 只清它自己的栈（SDL 侧），
        // 后端栈不清会跨帧累积，表现为"越画越少"（只剩顶部一条）。
        clipStack.clear()
        surface.setClip(0.0, 0.0, 0.0, 0.0)
        if (scale != 1.0) {
            surface.setTransform(scale, scale, 0.0, 0.0)
        }
        surface.beginFrame(channel(clear.r), channel(clear.g), channel(clear.b), channel(clear.a))
    }

    private var firstPresent = true

    public func present(): Unit {
        surface.endFrame()
        if (firstPresent) {
            firstPresent = false
            probeTrace("first frame present err=[" + lastErrorText() + "]")
        }
    }

    // 裁剪栈：保存逻辑坐标，应用到 surface 时按 scale 换算成世界像素。
    private var clipStack: ArrayList<Rect> = ArrayList<Rect>()

    public func pushClip(rect: Rect): Unit {
        let effective = if (clipStack.isEmpty()) {
            rect
        } else {
            clipStack[clipStack.size - 1].intersection(rect)
        }
        clipStack.add(effective)
        applyClip()
    }

    public func popClip(): Unit {
        if (!clipStack.isEmpty()) {
            clipStack.remove(at: clipStack.size - 1)
        }
        applyClip()
    }

    private func applyClip(): Unit {
        if (clipStack.isEmpty()) {
            surface.setClip(0.0, 0.0, 0.0, 0.0)
        } else {
            let top = clipStack[clipStack.size - 1]
            surface.setClip(top.x * scale, top.y * scale, top.w * scale, top.h * scale)
        }
    }

    // 纹理缓存：lgui.Texture.id → lgpu 纹理（像素经 texturePixelsSink 注册进来）。
    private var textures: HashMap<Int64, Texture> = HashMap<Int64, Texture>()
    // 纹理尺寸（用于把 source 矩形换算成 UV）
    private var textureSizes: HashMap<Int64, (Float32, Float32)> = HashMap<Int64, (Float32, Float32)>()

    /// 注册/更新一张后端纹理（由 lgui.texturePixelsSink 调用）。
    public func uploadTexture(id: Int64, width: Int32, height: Int32, pixels: Array<UInt8>): Unit {
        if (width <= 0 || height <= 0) {
            return
        }
        let tex = match (textures.get(id)) {
            case Some(existing) => existing
            case None =>
                let created = surface.createTexture(Int64(width), Int64(height))
                textures[id] = created
                created
        }
        textureSizes[id] = (Float32(width), Float32(height))
        probeTrace("pixels id=" + id.toString() + " " + width.toString() + "x" + height.toString())
        // 真机验证用：记录纹理上传（LANLU_PROBE_LGPU=1 时）
        if ((getVariable("LANLU_PROBE_LGPU") ?? "0") == "1") {
            let base = getVariable("HOME") ?? "."
            try {
                let path = Path(base + "/lgpu_textures.txt")
                let existing = if (exists(path)) { String.fromUtf8(File.readFrom(path)) } else { "" }
                File.writeTo(path, (existing + "id=" + id.toString() + " " + width.toString() + "x" + height.toString() + "\n").toArray())
            } catch (_) {}
        }
        tex.upload(pixels, 0, 0, Int64(width), Int64(height), Int64(width) * 4)
    }

    /// 注册一张 PNG 纹理（解码在 lgpu 内完成）。
    public func uploadTexturePng(id: Int64, bytes: Array<UInt8>): Unit {
        match (surface.createTextureFromPng(bytes)) {
            case Some(tex) =>
                textures[id] = tex
                probeTrace("png id=" + id.toString() + " bytes=" + bytes.size.toString())
            case None =>
                probeTrace("png failed id=" + id.toString() + " err=" + lastErrorText())
        }
    }

    public func drawTextureRounded(id: Int64, destination: Rect, source: ?Rect, radius: Float32,
        alpha: Float32): Unit {
        let tex = match (textures.get(id)) {
            case Some(t) => t
            case None => return
        }
        if (destination.w <= 0.0 || destination.h <= 0.0) {
            return
        }
        var u0 = 0.0f32
        var v0 = 0.0f32
        var u1 = 1.0f32
        var v1 = 1.0f32
        match (source) {
            case Some(src) =>
                match (textureSizes.get(id)) {
                    case Some(size) =>
                        let tw = size[0]
                        let th = size[1]
                        if (tw > 0.0 && th > 0.0) {
                            u0 = src.x / tw
                            v0 = src.y / th
                            u1 = (src.x + src.w) / tw
                            v1 = (src.y + src.h) / th
                        }
                    case None => ()
                }
            case None => ()
        }
        let rc = surface.textureRoundedRc(tex, destination.x * scale, destination.y * scale,
            destination.w * scale, destination.h * scale, u0, v0, u1, v1, radius * scale, alpha)
        if (rc != 0) {
            let home = getVariable("HOME") ?? "."
            try {
                File.writeTo(Path(home + "/draw_skip.txt"),
                    ("drawTextureRounded rc=" + rc.toString() + " id=" + id.toString() + "\n").toArray())
            } catch (_) {}
        }
    }

    public func drawTexture(id: Int64, destination: Rect, source: ?Rect, alpha: Float32): Unit {
        let tex = match (textures.get(id)) {
            case Some(t) => t
            case None => return
        }
        // UV 子区：source 为空表示整张纹理
        var u0 = 0.0f32
        var v0 = 0.0f32
        var u1 = 1.0f32
        var v1 = 1.0f32
        match (source) {
            case Some(src) =>
                match (textureSizes.get(id)) {
                    case Some(size) =>
                        let tw = size[0]
                        let th = size[1]
                        if (tw > 0.0 && th > 0.0) {
                            u0 = src.x / tw
                            v0 = src.y / th
                            u1 = (src.x + src.w) / tw
                            v1 = (src.y + src.h) / th
                        }
                    case None => ()
                }
            case None => ()
        }
        // 退化矩形（宽或高 <= 0）直接跳过：lgpu 会返回 E_BAD_ARG(-5) 并抛异常。
        // 布局尚未稳定时（如 0 高度的占位图）这种情况是正常的，不该报错。
        if (destination.w <= 0.0 || destination.h <= 0.0) {
            return
        }
        let rc = surface.textureRc(tex, destination.x * scale, destination.y * scale,
            destination.w * scale, destination.h * scale, u0, v0, u1, v1, 1.0, 1.0, 1.0, alpha)
        if (rc != 0) {
            // 记录一次，便于定位（不抛异常：单张纹理失败不应中断整帧绘制）
            let home = getVariable("HOME") ?? "."
            try {
                File.writeTo(Path(home + "/draw_skip.txt"),
                    ("drawTexture rc=" + rc.toString() + " id=" + id.toString() +
                     " dst=" + destination.w.toString() + "x" + destination.h.toString() + "\n").toArray())
            } catch (_) {}
        }
    }

    public func fill(rect: Rect, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, 0.0,
            channel(color.r), channel(color.g), channel(color.b), channel(color.a))
    }

    public func fillRectGradient(rect: Rect, from: Color, to: Color, vertical: Bool): Unit {
        // 渐变直接推给 lgpu（mode 1=横向，2=纵向）
        let mode = if (vertical) { Int64(2) } else { Int64(1) }
        surface.gradient(rect.x, rect.y, rect.w, rect.h, mode, Float32(from.r) / 255.0,
            Float32(from.g) / 255.0, Float32(from.b) / 255.0, Float32(from.a) / 255.0,
            Float32(to.r) / 255.0, Float32(to.g) / 255.0, Float32(to.b) / 255.0, Float32(to.a) / 255.0)
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
