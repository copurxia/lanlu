package lanlu_client_next.ui

// P4 对照：CN_UI_BACKEND=lgpu 时，把整棵 UI 树的绘制交给 lgpu（wgpu/Vulkan）。
//
// 工作方式：sdl.Renderer 内部有一个可选后端（Canvas）；这里造一个 LgpuCanvas 装上，
// 于是所有图元/文本都走 lgpu，SDL 只保留事件循环与窗口管理。
// 预览缩放：把逻辑尺寸的 UI 缩到小窗口里（LANLU_LGPU_SCALE 覆盖，默认 0.25）。

import std.convert.*
import std.env.getVariable
import lgpu.{Font, LgpuCanvas, Surface}
import lwindow.systemSansFontPath
import sdl.Canvas
import sdl

public func installLgpuBackendIfRequested(apply: (Canvas) -> Unit): Bool {
    if ((getVariable("CN_UI_BACKEND") ?? "sdl") != "lgpu") {
        return false
    }
    // 等 ArkTS 的 XComponent onLoad 把 surfaceId 写进进程环境（最多 10 秒）
    var sidText = getVariable("LANLU_SURFACE_ID") ?? ""
    var waited = 0
    while (sidText.size == 0 && waited < 100) {
        sleep(Duration.millisecond * 100)
        waited++
        sidText = getVariable("LANLU_SURFACE_ID") ?? ""
    }
    if (sidText.size == 0) {
        return false
    }
    var sid: Int64 = 0
    try {
        sid = Int64.parse(sidText)
    } catch (_) {
        return false
    }
    let surface = Surface.fromSurfaceId(sid)
    surface.configure(240, 160)
    // 字体路径由平台层给出（分层规则：业务层不写平台路径）
    let fontPath = match (systemSansFontPath()) {
        case Some(p) => p
        case None => return false
    }
    let font = Font.load(fontPath)
    let canvas = LgpuCanvas(surface, font)
    var scaleText = getVariable("LANLU_LGPU_SCALE") ?? "0.25"
    var scale: Float32 = 0.25
    try {
        scale = Float32.parse(scaleText)
    } catch (_) {}
    canvas.scale = scale
    // 纹理委派：SDL 纹理创建/更新时把 RGBA 像素送给 lgpu 后端
    sdl.texturePngSink = {id, bytes => canvas.uploadTexturePng(id, bytes)}
    sdl.texturePixelsSink = {id, w, h, pixels => canvas.uploadTexture(id, w, h, pixels)}
    apply(canvas)
    return true
}