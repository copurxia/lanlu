package lanlu_client_next.ui

// P4 对照：CN_UI_BACKEND=lgpu 时，把整棵 UI 树的绘制交给 lgpu（wgpu/Vulkan）。
//
// 工作方式：lgui.Renderer 内部有一个可选后端（Canvas）；这里造一个 LgpuCanvas 装上，
// 于是所有图元/文本都走 lgpu，SDL 只保留事件循环与窗口管理。
// 预览缩放：把逻辑尺寸的 UI 缩到小窗口里（LANLU_LGPU_SCALE 覆盖，默认 0.25）。

import std.convert.*
import std.env.getVariable
import std.fs.{exists as fsExists, Path as FsPath, File as FsFile}
import lgpu.{Font, LgpuCanvas, Surface}
import lwindow
import lwindow.{LWindowEventType}
import lwindow.systemSansFontPath
import lgui.{Canvas, Key, MouseButton, SdlWindow, UiEvent, WindowSpec}
import lgui
import lgui.input.{ClipboardBackend, clipboardBackend, cursorsEnabled}
import lgui.input

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

/// 最近一次安装的后端画布（联调/抓帧用）。
public var lastCanvas: ?LgpuCanvas = None

public func installLgpuBackendIfRequested(apply: (Canvas) -> Unit): Bool {
    // P5：引擎现在由壳层在 libmain 加载时自启动，可能早于 ArkTS 设置环境变量。
    // 这里最多等 5 秒让 CN_UI_BACKEND 就绪（onCreate 里设置，通常 <1 秒）。
    var backend = getVariable("CN_UI_BACKEND") ?? ""
    var envWait = 0
    while (backend.size == 0 && envWait < 50) {
        sleep(Duration.millisecond * 100)
        envWait++
        backend = getVariable("CN_UI_BACKEND") ?? ""
    }
    probeTrace("backend mode=" + backend + " waited=" + envWait.toString())
    if (backend != "lgpu") {
        return false
    }
    // 等 ArkTS 把整窗 surfaceId 写进进程环境（最多 15 秒）。
    // 必须优先等 LANLU_MAIN_SURFACE_ID：测试小窗（LANLU_SURFACE_ID）会先就绪，
    // 过早回退会导致后端画到 240x160 的小窗上。
    var sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
    var waited = 0
    while (sidText.size == 0 && waited < 150) {
        sleep(Duration.millisecond * 100)
        waited++
        sidText = getVariable("LANLU_MAIN_SURFACE_ID") ?? ""
    }
    if (sidText.size == 0) {
        // 兜底：没有整窗时用测试小窗（仅调试）
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
    lgui.texturePngSink = {id, bytes => canvas.uploadTexturePng(id, bytes)}
    lgui.texturePixelsSink = {id, w, h, pixels => canvas.uploadTexture(id, w, h, pixels)}
    apply(canvas)
                lastCanvas = canvas
    return true
}

/// P5：用 L 层窗口 + lgpu 后端替代 SDL 窗口。
/// 返回 null 表示未启用（CN_WINDOW != lgpu）。
public func makeHeadlessWindow(spec: WindowSpec): ?SdlWindow {
    if ((getVariable("CN_WINDOW") ?? "sdl") != "lgpu") {
        return None
    }
    let window = SdlWindow.headless(spec)
    // 事件源：L 层输入桥（文件通道）→ UiEvent
    lgui.headlessEventSource = Some({ =>
        // ArrayList 没有 first()：用 size + 下标
        let events = lwindow.readInputEvents()
        if (events.size == 0) {
            return None
        }
        let ev = events[0]
        probeTrace("input ev kind=" + ev.x.toString() + "," + ev.y.toString())
        return match (ev.kind) {
            case lwindow.LWindowEventType.PointerDown => Some(UiEvent.MouseDown(MouseButton.Left, ev.x, ev.y))
            case lwindow.LWindowEventType.PointerMove => Some(UiEvent.MouseMove(ev.x, ev.y))
            case lwindow.LWindowEventType.PointerUp => Some(UiEvent.MouseUp(MouseButton.Left, ev.x, ev.y))
            case _ => Some(UiEvent.Unknown(0))
        }
    })
    return window
}
/// P5：headless 窗口的输入源——把 L 层事件桥映射成 UiEvent。
/// 必须在创建 headless 窗口之前调用（DesktopApp 内部读 CN_WINDOW）。
public func installHeadlessInputSource(): Unit {
    // 窗口控制：headless 下交给平台层（写命令文件，ArkTS 轮询执行）
    lgui.headlessWindowCommand = Some({command => lwindow.requestWindowCommand(command)})
    // 剪贴板：SDL 在真机读不到系统剪贴板，改走 L 层（文件通道 + ArkTS pasteboard）
    clipboardBackend = LWindowClipboard()

    // 无 SDL 窗口：鼠标样式由 L 层负责
    cursorsEnabled = false
    if ((getVariable("CN_WINDOW") ?? "sdl") != "lgpu") {
        return
    }
    lgui.headlessEventSource = Some({ =>
        // 1) IME 文本
        let texts = lwindow.readTextInputs()
        if (texts.size > 0) {
            return Some(UiEvent.TextInput(texts[0]))
        }
        // 2) 按键
        let keyEvents = lwindow.readKeyEvents()
        if (keyEvents.size > 0) {
            let tuple = keyEvents[0]
            let key = keyFromName(tuple[1])
            return Some(if (tuple[0]) { UiEvent.KeyDown(key, tuple[2].size > 0) } else { UiEvent.KeyUp(key) })
        }
        // 3) 指针
        let events = lwindow.readInputEvents()
        if (events.size == 0) {
            return None
        }
        let ev = events[0]
        probeTrace("input ev " + ev.x.toString() + "," + ev.y.toString() + " key=" + ev.key.toString())
        return match (ev.kind) {
            case lwindow.LWindowEventType.PointerDown => Some(UiEvent.MouseDown(MouseButton.Left, ev.x, ev.y))
            case lwindow.LWindowEventType.PointerMove => Some(UiEvent.MouseMove(ev.x, ev.y))
            case lwindow.LWindowEventType.PointerUp => Some(UiEvent.MouseUp(MouseButton.Left, ev.x, ev.y))
            case _ => Some(UiEvent.Unknown(0))
        }
    })
}

/// 联调：延迟 5 秒触发一次窗口命令（验证 L 层窗口控制通道）。
public func installLgpuProbeWindowCommand(command: String): Unit {
    spawn {
        sleep(Duration.second * 5)
        lwindow.requestWindowCommand(command)
    }
}

/// 壳层传来的按键名 → Key 枚举。
func keyFromName(name: String): Key {
    match (name) {
        case "Escape" => Key.Escape
        case "Backspace" => Key.Backspace
        case "Enter" => Key.Enter
        case "Tab" => Key.Tab
        case "Delete" => Key.Delete
        case "Space" => Key.Space
        case "Home" => Key.Home
        case "End" => Key.End
        case "Left" => Key.Left
        case "Right" => Key.Right
        case "Up" => Key.Up
        case "Down" => Key.Down
        case _ =>
            if (name.size == 1) {
                Key.Letter(UInt8(name.toArray()[0]))
            } else {
                Key.RawScancode(0)
            }
    }
}

/// L 层剪贴板后端（引擎 → ArkTS → OHOS pasteboard）。
class LWindowClipboard <: ClipboardBackend {
    public func setText(text: String): Unit {
        lwindow.clipboardSetText(text)
    }

    public func getText(): String {
        lwindow.clipboardGetText()
    }

    public func hasText(): Bool {
        lwindow.clipboardHasText()
    }
}
