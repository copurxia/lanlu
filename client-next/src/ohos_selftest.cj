package lanlu_client_next

// OHOS 移植自检实现（仅在 OHOS_SELFTEST=1 时由 ohos_entry 调用）。
import std.env.getVariable
import std.fs.{File, Path}
import std.time.MonoTime
import vips_ffi.*
import qwest.*
import libavformat_ffi.*
import libass_ffi.*
import libvlc_ffi.{VlcPlayer}
import webview.{WebviewSession, HtmlFrame, warmup as wvWarmup}
import lanlu_client_next.ui.EMBEDDED_LOGO_PNG

private func decodeMsg(p: String): String {
    let fn = unsafe { LibC.mallocCString(p) }
    let img = VipsApi.imageNewFromFile(fn)
    unsafe { LibC.free(fn) }
    if (img.isNull()) {
        return "FAIL"
    }
    let w = VipsApi.imageWidth(img)
    let h = VipsApi.imageHeight(img)
    var sz: UIntNative = 0
    let mem = unsafe { VipsApi.writeToMemory(img, CPointer<UIntNative>(inout sz)) }
    VipsApi.unref(img)
    VipsApi.free(mem)
    return "w=${w} h=${h} sz=${sz}"
}

func ohosImageSelftest(base: String): Unit {
    try {
        let n = unsafe { LibC.mallocCString("lanlu-selftest") }
        let rc = VipsApi.initialize(n)
        unsafe { LibC.free(n) }
        File.writeTo(Path(base + "/vt.png"), EMBEDDED_LOGO_PNG)
        File.writeTo(Path(base + "/vt.webp"), WEBP_SAMPLE)
        let m1 = decodeMsg(base + "/vt.png")
        let m2 = decodeMsg(base + "/vt.webp")
        File.writeTo(Path(base + "/vipstest.txt"), "rc=${rc}\npng: ${m1}\nwebp: ${m2}\n".toArray())
    } catch (_) {
    }
}

private func httpMsg(url: String, trustAll: Bool): String {
    try {
        var cb = ClientBuilder().baseUrl(url)
        if (trustAll) {
            cb = cb.tlsVerify(TlsVerify.TrustAll)
        }
        let c = cb.build()
        let r = c.get("/").send()
        let body = r.text()
        c.close()
        return "status=${r.status} body=${body}"
    } catch (ex: Exception) {
        return "ERR ${ex}"
    }
}

func ohosNetSelftest(base: String): Unit {
    // 回环目标默认为主机调试地址，可用 OHOS_NET_HOST 覆盖
    let host = getVariable("OHOS_NET_HOST") ?? "192.168.0.131"
    File.writeTo(Path(base + "/net.txt"), httpMsg("http://${host}:18080", false).toArray())
    File.writeTo(Path(base + "/net2.txt"), httpMsg("https://${host}:18443", true).toArray())
}

func ohosMediaSelftest(base: String): Unit {
    try {
        File.writeTo(Path(base + "/mix.mkv"), MIXED_MKV)
        let (r, c, cr, cc) = libavVersions()
        var am = "ver runtime=${r}/${c} compiled=${cr}/${cc}"
        let streams = probeSubtitleStreams(base + "/mix.mkv")
        am += " streams=${streams.size}"
        if (streams.size > 0) {
            am += " first=${streams[0].codecName}"
        }
        File.writeTo(Path(base + "/avtest.txt"), am.toArray())
    } catch (ex2: Exception) {
        File.writeTo(Path(base + "/avtest.txt"), ("EXC " + ex2.message).toArray())
    }
    try {
        File.writeTo(Path(base + "/basic.ass"), BASIC_ASS)
        let amsg = try {
            let rend = AssRenderer(1280, 720)
            let track = rend.readAssDocument(BASIC_ASS)
            let bmp = rend.render(1000, [track])
            let s = "bitmap=${bmp.width}x${bmp.height} at(${bmp.x},${bmp.y}) rgba_bytes=${bmp.rgba.size}"
            track.close()
            rend.close()
            s
        } catch (ex3: Exception) {
            "EXC ${ex3.message}"
        }
        File.writeTo(Path(base + "/asstest.txt"), amsg.toArray())
    } catch (ex4: Exception) {
        File.writeTo(Path(base + "/asstest.txt"), ("EXC " + ex4.message).toArray())
    }
    try {
        File.writeTo(Path(base + "/test.mp4"), TEST_MP4)
        let vmsg = try {
            let player = VlcPlayer()
            player.open(base + "/test.mp4", muted: false)
            var frames = 0
            var lastW: Int32 = 0
            var lastH: Int32 = 0
            let t0 = MonoTime.now()
            while (MonoTime.now() - t0 < Duration.second * 4) {
                let _ = player.timeSec()  // 驱动解码（pull 模型）
                let fr = player.takeFrame()
                if (let Some(f) <- fr) {
                    frames += 1
                    lastW = f.width
                    lastH = f.height
                    if (frames == 1) {
                        // 首帧校验像素非全黑
                        var nonBlack = 0
                        for (i in 0..1000) { if (f.rgba[Int64(i) * 4] > 10) { nonBlack += 1 } }
                        if (nonBlack > 100) { frames += 1000 }  // 标记首帧有效
                    }
                }
                sleep(Duration.millisecond * 30)
            }
            player.seek(6.0)
            var seekTime = 0.0
            let ts = MonoTime.now()
            while (MonoTime.now() - ts < Duration.second * 2) {
                let _ = player.timeSec()
                seekTime = player.timeSec()
                if (seekTime > 5.5) { break }
                sleep(Duration.millisecond * 30)
            }
            let dur = player.durationSec()
            let t = player.timeSec()
            player.stop()
            player.close()
            "frames=${frames} last=${lastW}x${lastH} dur=${dur}s time=${t}s seekTo=${seekTime}s"
        } catch (ex5: Exception) {
            "EXC ${ex5.message}"
        }
        File.writeTo(Path(base + "/vlctest.txt"), vmsg.toArray())
    } catch (ex6: Exception) {
        File.writeTo(Path(base + "/vlctest.txt"), ("EXC " + ex6.message).toArray())
    }
    try {
        let wmsg = try {
            wvWarmup()
            let w = WebviewSession(800, 600, 1.0)
            w.loadHtml("<html><body><h1>Hello Blitz</h1><p>lanlu html reader</p></body></html>".toArray(), "about:blank")
            var fr: ?HtmlFrame = None
            let ts = MonoTime.now()
            while (MonoTime.now() - ts < Duration.second * 3) {
                fr = w.takeFrame()
                match (fr) { case Some(_) => break; case None => () }
                sleep(Duration.millisecond * 30)
            }
            let s = match (fr) {
                case Some(f) => "ok w=${f.width} h=${f.height} rgba=${f.rgba.size}"
                case None => "no frame"
            }
            w.close()
            s
        } catch (ex7: Exception) {
            "EXC ${ex7.message}"
        }
        File.writeTo(Path(base + "/wvtest.txt"), wmsg.toArray())
    } catch (ex8: Exception) {
        File.writeTo(Path(base + "/wvtest.txt"), ("EXC " + ex8.message).toArray())
    }
}
