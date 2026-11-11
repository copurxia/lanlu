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

// sRGB → 线性（256 项查表）。
//
// 交换链是 sRGB 格式：硬件写入时执行 linear→sRGB 编码。调色板是设计稿的 sRGB 值，
// 若直接按 v/255 当线性值送进去会被**二次编码**——实测深色底 0x0B(11) 渲染成 61、
// 浅色底 F8(248) 渲染成 254，面板与背景压成一片白（真机"过曝"）。
// 这里预解码成线性，硬件编码后即还原为原值（实测输出 11,11,13 / 248,248,250）。
let SRGB_TO_LINEAR: Array<Float32> = [
    0.000000000f32, 0.000303527f32, 0.000607054f32, 0.000910581f32, 0.001214108f32, 0.001517635f32, 0.001821162f32, 0.002124689f32,
    0.002428216f32, 0.002731743f32, 0.003035270f32, 0.003346536f32, 0.003676507f32, 0.004024717f32, 0.004391442f32, 0.004776953f32,
    0.005181517f32, 0.005605392f32, 0.006048833f32, 0.006512091f32, 0.006995410f32, 0.007499032f32, 0.008023193f32, 0.008568126f32,
    0.009134059f32, 0.009721217f32, 0.010329823f32, 0.010960094f32, 0.011612245f32, 0.012286488f32, 0.012983032f32, 0.013702083f32,
    0.014443844f32, 0.015208514f32, 0.015996293f32, 0.016807376f32, 0.017641954f32, 0.018500220f32, 0.019382361f32, 0.020288563f32,
    0.021219010f32, 0.022173885f32, 0.023153366f32, 0.024157632f32, 0.025186860f32, 0.026241222f32, 0.027320892f32, 0.028426040f32,
    0.029556834f32, 0.030713444f32, 0.031896033f32, 0.033104767f32, 0.034339807f32, 0.035601315f32, 0.036889450f32, 0.038204372f32,
    0.039546235f32, 0.040915197f32, 0.042311411f32, 0.043735029f32, 0.045186204f32, 0.046665086f32, 0.048171824f32, 0.049706566f32,
    0.051269458f32, 0.052860647f32, 0.054480276f32, 0.056128490f32, 0.057805430f32, 0.059511238f32, 0.061246054f32, 0.063010018f32,
    0.064803267f32, 0.066625939f32, 0.068478170f32, 0.070360096f32, 0.072271851f32, 0.074213568f32, 0.076185381f32, 0.078187422f32,
    0.080219820f32, 0.082282707f32, 0.084376212f32, 0.086500462f32, 0.088655586f32, 0.090841711f32, 0.093058963f32, 0.095307467f32,
    0.097587347f32, 0.099898728f32, 0.102241733f32, 0.104616484f32, 0.107023103f32, 0.109461711f32, 0.111932428f32, 0.114435374f32,
    0.116970668f32, 0.119538428f32, 0.122138772f32, 0.124771818f32, 0.127437680f32, 0.130136477f32, 0.132868322f32, 0.135633330f32,
    0.138431615f32, 0.141263291f32, 0.144128471f32, 0.147027266f32, 0.149959790f32, 0.152926152f32, 0.155926464f32, 0.158960835f32,
    0.162029376f32, 0.165132195f32, 0.168269400f32, 0.171441101f32, 0.174647404f32, 0.177888416f32, 0.181164244f32, 0.184474995f32,
    0.187820772f32, 0.191201683f32, 0.194617830f32, 0.198069320f32, 0.201556254f32, 0.205078736f32, 0.208636870f32, 0.212230757f32,
    0.215860500f32, 0.219526200f32, 0.223227957f32, 0.226965874f32, 0.230740049f32, 0.234550582f32, 0.238397574f32, 0.242281122f32,
    0.246201327f32, 0.250158285f32, 0.254152094f32, 0.258182853f32, 0.262250658f32, 0.266355605f32, 0.270497791f32, 0.274677312f32,
    0.278894263f32, 0.283148740f32, 0.287440838f32, 0.291770650f32, 0.296138271f32, 0.300543794f32, 0.304987314f32, 0.309468923f32,
    0.313988713f32, 0.318546778f32, 0.323143209f32, 0.327778098f32, 0.332451536f32, 0.337163615f32, 0.341914425f32, 0.346704056f32,
    0.351532600f32, 0.356400144f32, 0.361306780f32, 0.366252596f32, 0.371237680f32, 0.376262123f32, 0.381326011f32, 0.386429434f32,
    0.391572478f32, 0.396755231f32, 0.401977780f32, 0.407240212f32, 0.412542613f32, 0.417885071f32, 0.423267670f32, 0.428690497f32,
    0.434153636f32, 0.439657174f32, 0.445201195f32, 0.450785783f32, 0.456411023f32, 0.462077000f32, 0.467783796f32, 0.473531496f32,
    0.479320183f32, 0.485149940f32, 0.491020850f32, 0.496932995f32, 0.502886458f32, 0.508881321f32, 0.514917665f32, 0.520995573f32,
    0.527115126f32, 0.533276404f32, 0.539479489f32, 0.545724461f32, 0.552011402f32, 0.558340390f32, 0.564711506f32, 0.571124829f32,
    0.577580440f32, 0.584078418f32, 0.590618841f32, 0.597201788f32, 0.603827339f32, 0.610495571f32, 0.617206562f32, 0.623960392f32,
    0.630757136f32, 0.637596874f32, 0.644479682f32, 0.651405637f32, 0.658374817f32, 0.665387298f32, 0.672443157f32, 0.679542470f32,
    0.686685312f32, 0.693871761f32, 0.701101892f32, 0.708375780f32, 0.715693501f32, 0.723055129f32, 0.730460740f32, 0.737910409f32,
    0.745404210f32, 0.752942217f32, 0.760524505f32, 0.768151147f32, 0.775822218f32, 0.783537792f32, 0.791297940f32, 0.799102738f32,
    0.806952258f32, 0.814846572f32, 0.822785754f32, 0.830769877f32, 0.838799012f32, 0.846873232f32, 0.854992608f32, 0.863157213f32,
    0.871367119f32, 0.879622397f32, 0.887923118f32, 0.896269353f32, 0.904661174f32, 0.913098652f32, 0.921581856f32, 0.930110858f32,
    0.938685728f32, 0.947306537f32, 0.955973353f32, 0.964686248f32, 0.973445290f32, 0.982250550f32, 0.991102097f32, 1.000000000f32,
]

func channel(v: UInt8): Float32 {
    SRGB_TO_LINEAR[Int64(v)]
}

/// alpha 是线性量，不做 sRGB 解码。
func alphaChannel(v: UInt8): Float32 {
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
