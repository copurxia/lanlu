package lanlu_client_next.ui

// P4 对照：CN_UI_BACKEND=lgpu 时，把整棵 UI 树的绘制交给 lgpu（wgpu/Vulkan）。
//
// 工作方式：sdl.Renderer 内部有一个可选后端（Canvas）；这里造一个 LgpuCanvas 装上，
// 于是所有图元/文本都走 lgpu，SDL 只保留事件循环与窗口管理。
// 预览缩放：把逻辑尺寸的 UI 缩到小窗口里（LANLU_LGPU_SCALE 覆盖，默认 0.25）。

import std.convert.*
import std.env.getVariable
import std.fs.{exists as fsExists, Path as FsPath, File as FsFile}
import lgpu.{Font, LgpuCanvas, Surface}
import lwindow.systemSansFontPath
import sdl.Canvas
import sdl

func probeTrace(line: String): Unit {
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") != "1") {
        return
    }
    let home = getVariable("HOME") ?? "."
    let path = FsPath(home + "/probe_trace.txt")
    try {
        let old = if (fsExists(path)) { String.fromUtf8(FsFile.readFrom(path)) } else { "" }
        FsFile.writeTo(path, (old + line + String.fromUtf8(Array<UInt8>(1, repeat: 10))).toArray())
    } catch (_) {}
}

public func installLgpuBackendIfRequested(apply: (Canvas) -> Unit): Bool {
    if ((getVariable("CN_UI_BACKEND") ?? "sdl") != "lgpu") {
        return false
    }
    // 等 ArkTS 的 XComponent onLoad 把 surfaceId 写进进程环境（最多 10 秒）。
    // 优先用整窗 surface（LANLU_MAIN_SURFACE_ID，P5 预演）；没有则用测试小窗。
    var sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
    var waited = 0
    while (sidText.size == 0 && waited < 100) {
        sleep(Duration.millisecond * 100)
        waited++
        sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
        if (sidText.size == 0) {
            sidText = getVariable("LANLU_SURFACE_ID") ?? ""
        }
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
    let isMain = (getVariable("LANLU_MAIN_SURFACE_ID") ?? "").size > 0
    var surfW: Int64 = 240
    var surfH: Int64 = 160
    if (isMain) {
        try { surfW = Int64.parse(getVariable("LANLU_MAIN_W") ?? "0") } catch (_) {}
        try { surfH = Int64.parse(getVariable("LANLU_MAIN_H") ?? "0") } catch (_) {}
        if (surfW <= 0 || surfH <= 0) {
            surfW = 2090
            surfH = 1394
        }
    }
    let surface = Surface.fromSurfaceId(sid)
    surface.configure(surfW, surfH)
    // 字体路径由平台层给出（分层规则：业务层不写平台路径）
    let fontPath = match (systemSansFontPath()) {
        case Some(p) => p
        case None => return false
    }
    probeTrace("font path=" + fontPath)
    let font = Font.load(fontPath)
    probeTrace("install main=" + isMain.toString() + " sid=" + sid.toString() + " " + surfW.toString() + "x" + surfH.toString())
    let canvas = LgpuCanvas(surface, font)
    var scaleText = getVariable("LANLU_LGPU_SCALE") ?? (if (isMain) { "1.0" } else { "0.25" })
    var scale: Float32 = if (isMain) { 1.0 } else { 0.25 }
    try {
        scale = Float32.parse(scaleText)
    } catch (_) {}
    canvas.scale = scale
    if ((getVariable("LANLU_MAIN_PROBE_FILL") ?? "0") == "1") {
        canvas.forceClearRed = true
    }
    // 纹理委派：SDL 纹理创建/更新时把 RGBA 像素送给 lgpu 后端
    sdl.texturePngSink = {id, bytes => canvas.uploadTexturePng(id, bytes)}
    sdl.texturePixelsSink = {id, w, h, pixels => canvas.uploadTexture(id, w, h, pixels)}
    apply(canvas)
    return true
}