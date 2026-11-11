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

// 颜色空间：整条 UI 画进 **Rgba8Unorm 离屏目标**（gamma 空间混合，与设计稿一致），
// 再由 lgpu 的 blit 管线转成线性写到 sRGB 交换链；硬件编码把它还原成原值。
// 因此这里直接按 v/255 输出 —— 预解码与 blit 只能留一个（见 docs/lgpu-color-pipeline.md）。

/// alpha 是线性量，不走 sRGB 解码。
func alphaChannel(v: UInt8): Float32 {
    Float32(v) / 255.0
}

/// 颜色通道：直传（gamma 空间）。离屏目标是 Unorm，混合与设计稿同空间；
/// 上屏时由 blit 转线性、硬件编码还原（见文件头注释）。
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
    // R5.1：文本测量缓存——宽度只取决于 (text, pointSize)，跨帧安全复用。
    // 之前每次 textWidth 都是一次 FFI（含 UTF-8 转换与逐字符 advance 求和），
    // 即时模式下每帧每个 Label 至少测一次；缓存命中率目标是 >95%。
    // 超过容量时整体清空（简单且足够：文本集合在稳态下远小于上限）。
    private static let MEASURE_CAP: Int64 = 8192
    private var measureCache: HashMap<String, Float32> = HashMap<String, Float32>()
    private var measureHits: Int64 = 0
    private var measureMisses: Int64 = 0

    /// 测量缓存统计 (hits, misses, entries)，供 M0 打点。
    public func measureStats(): (Int64, Int64, Int64) {
        (measureHits, measureMisses, measureCache.size)
    }

    /// 清空测量缓存（字体更换/内存压力时调用）。
    public func clearMeasureCache(): Unit {
        measureCache.clear()
    }

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

    /// 供上层在尺寸变化时 reconfigure（**复用 swapchain，不要重建**，见计划 §7.1）。
    /// 用法：`surfaceRef().resize(w, h)`；**不要**调用 `configure`（那会重建 device/pipeline）。
    public func surfaceRef(): Surface {
        this.surface
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
        surface.beginFrame(channel(clear.r), channel(clear.g), channel(clear.b), alphaChannel(clear.a))
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

    /// 释放一张后端纹理（R4：Texture.close → Canvas.releaseTexture）。
    /// 幂等：id 不存在时为空操作；释放后同 id 重新 uploadTexture 会创建新纹理。
    /// 注意：lgpu 侧纹理在本帧 draw 之后才会真正 drop（tex_instances 持有裸指针，
    /// Rust 侧 lgpu_texture_destroy 直接 free——同一帧内先画后关的顺序由 cui 的
    /// "close 发生在帧间"保证；帧内 close+draw 混用的场景由 LgpuCanvas 的 map
    /// 移除兜底：draw 找不到纹理直接跳过）。
    public func releaseTexture(id: Int64): Unit {
        match (textures.remove(id)) {
            case Some(tex) =>
                textureSizes.remove(id)
                tex.close()
                probeTrace("release tex id=" + id.toString())
            case None => ()
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

    /// GPU 快照注册为 lgui 纹理 id（替代 captureTo 的读回 + 写文件 + 再上传）。
    public func snapshotTexture(id: Int64, logicalW: Float32, logicalH: Float32): ?(Int32, Int32) {
        let (tex, w, h) = match (surface.snapshotTexture()) {
            case Some(v) => v
            case None => return None
        }
        match (textures.remove(id)) {
            case Some(old) => old.close()
            case None => ()
        }
        textures[id] = tex
        // UV 按逻辑尺寸换算：调用方的 source 矩形用屏幕逻辑坐标即可精确裁剪。
        let lw = if (logicalW > 0.0) { logicalW } else { Float32(w) }
        let lh = if (logicalH > 0.0) { logicalH } else { Float32(h) }
        textureSizes[id] = (lw, lh)
        Some((Int32(w), Int32(h)))
    }

    public func layerMark(): Unit {
        surface.layerMark()
    }

    public func discardRecorded(): Unit {
        surface.discardRecorded()
    }

    public func glowRing(cx: Float32, cy: Float32, radius: Float32, stroke: Float32, outer: Float32,
            inner: Float32, color: Color, glow: Float32): Bool {
        // 矩形管线在着色器里统一乘全局变换（同 fillCircle），这里传逻辑坐标。
        surface.glowRing(cx, cy, radius, stroke, outer, inner, glow, channel(color.r), channel(color.g),
            channel(color.b), alphaChannel(color.a))
        true
    }

    public func fill(rect: Rect, color: Color): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, 0.0,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
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
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func fillRoundedRectSoft(rect: Rect, radius: Float32, color: Color, feather!: Float32): Unit {
        // SDF 自带解析抗锯齿；feather 暂时忽略（见文件头说明）
        fillRoundedRect(rect, radius, color)
    }

    public func strokeRect(rect: Rect, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, 0.0, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func strokeRoundedRect(rect: Rect, radius: Float32, pen: Pen): Unit {
        surface.rect(rect.x, rect.y, rect.w, rect.h, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func strokeLine(x1: Float32, y1: Float32, x2: Float32, y2: Float32, pen: Pen): Unit {
        surface.line(x1, y1, x2, y2, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func line(x1: Float32, y1: Float32, x2: Float32, y2: Float32, color: Color): Unit {
        surface.line(x1, y1, x2, y2, 1.0,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func fillCircle(cx: Float32, cy: Float32, radius: Float32, color: Color): Unit {
        surface.circle(cx, cy, radius,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func strokeCircle(cx: Float32, cy: Float32, radius: Float32, pen: Pen, segments!: Int64 = 0): Unit {
        surface.strokeCircle(cx, cy, radius, pen.width,
            channel(pen.color.r), channel(pen.color.g), channel(pen.color.b), alphaChannel(pen.color.a))
    }

    public func text(text: String, x: Float32, y: Float32, color: Color, pointSize!: Float32 = 15.0): Unit {
        let _ = surface.text(font, text, x, y, pointSize,
            channel(color.r), channel(color.g), channel(color.b), alphaChannel(color.a))
    }

    public func textWidth(text: String, pointSize!: Float32 = 15.0): Float32 {
        // 缓存键带字号（q4 量化与 Rust 侧一致），命中即免 FFI。
        let key = text + "\u{0}" + Int64(pointSize * 4.0).toString()
        match (measureCache.get(key)) {
            case Some(w) =>
                measureHits += 1
                w
            case None =>
                measureMisses += 1
                if (measureCache.size >= MEASURE_CAP) {
                    measureCache.clear()
                }
                let w = font.measure(text, pointSize)
                measureCache[key] = w
                w
        }
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
