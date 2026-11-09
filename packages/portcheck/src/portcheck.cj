package portcheck

// 移植自检入口（跨平台）：OHOS_SELFTEST=1 时执行，结果写入 HOME 下文本文件，
// 便于 `hdc file recv` 取回核对。桌面构建默认关闭，行为与之前一致。
import std.env.getVariable
import std.fs.{File, Path}
import std.convert.*
import libavformat_ffi.probeSubtitleStreams
import sdl.input.Clipboard
import lgpu
import lwindow
import sdl

public func enabled(): Bool {
    (getVariable("OHOS_SELFTEST") ?? "0") == "1"
}

// 媒体探测自检：LANLU_PROBE_URL=<url> 时用 libavformat 探测该 URL（支持 http），
// 结果写入 $HOME/probe.txt 便于 hdc 取回。用于验证自造样片/线上片源是否可解。
func runProbeIfRequested(): Unit {
    let url = getVariable("LANLU_PROBE_URL") ?? ""
    if (url.size == 0) {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = "url=" + url + "\n"
    try {
        let streams = probeSubtitleStreams(url)
        out += "streams=" + streams.size.toString() + "\n"
        for (s in streams) {
            out += "  idx=" + s.streamIndex.toString() + " codec=" + s.codecName +
                " lang=" + s.language + " title=" + s.title + "\n"
        }
    } catch (e: Exception) {
        out += "probe failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/probe.txt"), out.toArray())
    } catch (_) {}
}

// 剪贴板自检：LANLU_PROBE_CLIPBOARD=1 时写入一段文本再读回，结果落 $HOME/clipboard.txt。
// 用于确认真机上 SDL 剪贴板后端（OHOS pasteboard）是否可用——复制/粘贴是阅读器的基础能力。
public func runClipboardProbeIfRequested(): Unit {
    if ((getVariable("LANLU_PROBE_CLIPBOARD") ?? "0") != "1") {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = ""
    let want = "lanlu-clip-ok"
    try {
        Clipboard.setText(want)
        // 系统剪贴板写入是异步的：读之前忙等一小会儿并重试（不依赖 sleep API）
        var got = ""
        var attempts = 0
        for (i in 0..8) {
            attempts = i + 1
            var spin: Int64 = 0
            while (spin < 20000000) {
                spin += 1
            }
            got = Clipboard.getText()
            if (got == want) {
                break
            }
        }
        // 集成校验：直接预置 clip_in.txt（模拟系统层读桥写入），再经 Clipboard 后端读回，
        // 用于验证引擎侧剪贴板后端接线（不依赖系统 pasteboard 授权）。
        var backendGot = ""
        try {
            File.writeTo(Path(base + "/clip_in.txt"), "backend-read".toArray())
            backendGot = Clipboard.getText()
        } catch (_) {}
        out += "backend=" + backendGot + "\n"
        out = "set=" + want + "\ngot=" + got + "\nmatch=" + (got == want).toString() + "\n" +
            "hasText=" + Clipboard.hasText().toString() + "\nattempts=" + attempts.toString() + "\n"
    } catch (e: Exception) {
        out = "clipboard failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/clipboard.txt"), out.toArray())
    } catch (_) {}
}

// L 层渲染器自检：C 调用 lgpu_self_check() 并把版本落 $HOME/lgpu.txt。
// P0 阶段用来证明 "Rust staticlib → HAP → Cangjie FFI" 这条链路真的通了。
foreign {
    func lgpu_self_check(): Int32
    func lgpu_version(): CString
    func lgpu_debug_dump(out: CPointer<UInt8>, outLen: Int64): Int32
}

func runLgpuProbe(): Unit {
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") != "1") {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = ""
    try {
        let rc = unsafe { lgpu_self_check() }
        let ver = unsafe { lgpu_version() }
        out = "self_check=" + rc.toString() + "\nversion=" + ver.toString() + "\n"
        // wgpu 实例 + 适配器枚举（VK_OHOS_surface 是否真的可用，看这里）
        let buf = Array<UInt8>(8192, repeat: 0u8)
        let handle = unsafe { acquireArrayRawData(buf) }
        unsafe { lgpu_debug_dump(handle.pointer, 8192) }
        unsafe { releaseArrayRawData(handle) }
        let text = String.fromUtf8(buf)
        let end = text.indexOf("\u{0}") ?? text.size
        out += "---- wgpu ----\n" + text[0..end] + "\n"
    } catch (e: Exception) {
        out = "lgpu probe failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/lgpu.txt"), out.toArray())
    } catch (_) {}
}

// L 层渲染器自检（Cangjie 包装层路径）：与 runLgpuProbe 的裸 C 调用互补，
// 这条验证 packages/lgpu 的 Cangjie 绑定能编译、链接并被调用。
func runLgpuCjProbe(): Unit {
    if ((getVariable("LANLU_PROBE_LGPU") ?? "0") != "1") {
        return
    }
    let base = getVariable("HOME") ?? "."
    var out = ""
    try {
        out = "version=" + lgpu.version() + "\nself_check=" + lgpu.selfCheck().toString() + "\n"
        out += "-- adapters --\n" + lgpu.adapterSummary() + "\n"
    } catch (e: Exception) {
        out = "lgpu cj probe failed: " + e.toString() + "\n"
    }
    try {
        File.writeTo(Path(base + "/lgpu_cj.txt"), out.toArray())
    } catch (_) {}
}

public func runIfEnabled(): Unit {
    runProbeIfRequested();
    runClipboardProbeIfRequested();
    runLgpuProbe();
    runLgpuCjProbe();
    runLwindowProbeIfRequested();
    if (!enabled()) {
        return
    }
    let base = getVariable("HOME") ?? "."
    ohosImageSelftest(base)
    ohosNetSelftest(base)
    ohosMediaSelftest(base)
}

// lwindow 自建窗口探针：surfaceId 由 ArkTS 写进进程环境（LANLU_SURFACE_ID），
// Cangjie 在**自己的线程**里建窗口 + surface 并画一帧，全程不跨边界传指针。
func runLwindowProbeIfRequested(): Unit {
    if ((getVariable("LANLU_PROBE_LWINDOW") ?? "0") != "1") {
        return
    }
    let base = getVariable("HOME") ?? "."
    var sidText = ""
    var waited = 0
    while (waited < 200) {
        sidText = getVariable("LANLU_SURFACE_ID") ?? ""
        if (sidText.size > 0) {
            break
        }
        sleep(Duration.millisecond * 100)
        waited++
    }
    var out = ""
    if (sidText.size == 0) {
        out = "lwindow probe: no surface id"
    } else {
        var sid: Int64 = 0
        try {
            sid = Int64.parse(sidText)
        } catch (_) {
            sid = 0
        }
        try {
            let surface = lgpu.Surface.fromSurfaceId(sid)
            surface.configure(240, 160)
            let font = lgpu.Font.load("/system/fonts/HarmonyOS_Sans.ttf")
            let canvas = lgpu.LgpuCanvas(surface, font)
            surface.beginFrame(0.05, 0.07, 0.14, 1.0)
            canvas.fillRoundedRect(sdl.Rect(8.0, 8.0, 120.0, 30.0), 8.0, sdl.Color(0xE8, 0xB0, 0x4B, 0xFF))
            canvas.fillCircle(200.0, 30.0, 16.0, sdl.Color.rgb(80, 200, 255))
            canvas.strokeLine(8.0, 120.0, 220.0, 120.0, sdl.Pen(width: 3.0, color: sdl.Color.rgb(255, 255, 255)))
            canvas.text("lwindow+lgpu", 8.0, 60.0, sdl.Color.rgb(255, 255, 255), pointSize: 18.0)
            surface.endFrame()
            out = "lwindow probe: drawn ok sid=" + sidText + " waited=" + waited.toString()
            // collect 5s（文件通道，读一次即可；这里短循环给 ArkTS 触摸留时间）
            var evs = lwindow.readInputEvents()
            var rounds = 0
            while (rounds < 50 && evs.size == 0) {
                sleep(Duration.millisecond * 100)
                rounds++
                evs = lwindow.readInputEvents()
            }
            out = out + " | events=" + evs.size.toString()
            for (ev in evs) {
                out = out + " [" + ev.x.toString() + "," + ev.y.toString() + " key=" + ev.key.toString() + "]"
            }
        } catch (e: Exception) {
            out = "lwindow probe failed: " + e.toString()
        }
    }
    try {
        File.writeTo(Path(base + "/lwindow.txt"), out.toArray())
    } catch (_) {}
}
